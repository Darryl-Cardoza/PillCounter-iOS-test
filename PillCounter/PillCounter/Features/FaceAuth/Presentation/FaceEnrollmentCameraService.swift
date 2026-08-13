//
//  FaceEnrollmentCameraService.swift
//  PillCounter
//
//  Minimal front-camera capture session for the face enrollment screen.
//  Deliberately separate from Features/Scanning's CameraService — that
//  class is wired for the back-camera pill-counting pipeline (barcode
//  metadata, tray/glove/pill detectors) and isn't a fit for a front-facing,
//  face-only capture screen. Frame delivery pattern (AVCaptureVideoDataOutput
//  delegate on a dedicated queue) mirrors CameraService's approach.
//

import AVFoundation
import CoreVideo

final class FaceEnrollmentCameraService: NSObject, ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var errorMessage: String?
    /// Which physical camera is currently feeding the session — drives the
    /// flip-camera button's icon/state in the UI.
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back

    /// Called on the session queue for every frame — NOT the main thread.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "faceauth.camera.session.queue")
    private var isRunning = false
    private var currentInput: AVCaptureDeviceInput?

    var previewSession: AVCaptureSession { session }

    func start() {
        checkPermissions()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.session.stopRunning()
            self.isRunning = false
        }
    }

    /// Swaps the active camera between front and back without tearing down
    /// the session — just reconfigures the input. Face detection/alignment
    /// is unaffected by which physical camera is active (YuNet/SFace work
    /// on either), so this is purely a UX convenience.
    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.cameraPosition == .front ? .back : .front

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                let newInput = try? AVCaptureDeviceInput(device: device)
            else {
                Log("FaceEnrollmentCameraService: flip failed — no camera at position \(newPosition)")
                return
            }

            self.session.beginConfiguration()
            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
            } else if let currentInput = self.currentInput {
                // Roll back rather than leave the session with no input.
                self.session.addInput(currentInput)
            }
            self.session.commitConfiguration()
            self.applyConnectionOrientation(position: newPosition)

            DispatchQueue.main.async { self.cameraPosition = newPosition }
            Log("FaceEnrollmentCameraService: flipped to \(newPosition)")
        }
    }

    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.errorMessage = "Camera access denied"
                    }
                }
            }
        default:
            isAuthorized = false
            errorMessage = "Camera access denied"
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else {
                self.session.sessionPreset = .photo
            }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.errorMessage = "Camera unavailable" }
                return
            }
            self.session.addInput(input)
            self.currentInput = input

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.session.commitConfiguration()
            self.applyConnectionOrientation(position: self.cameraPosition)
            self.session.startRunning()
            self.isRunning = true
        }
    }

    /// Without this, AVCaptureVideoDataOutput delivers frames in the
    /// sensor's native (landscape) orientation regardless of how the phone
    /// is held — every downstream box/landmark/roll computation assumes an
    /// upright portrait face, so a real face never passes YuNet's
    /// confidence gate and never passes FaceQualityChecker's roll gate
    /// (roll reads as ~±90° for a portrait-held phone's landscape buffer).
    /// This was the primary reason detection appeared to silently do
    /// nothing. Must be called after every input change (initial configure
    /// AND flipCamera) since a fresh input creates a fresh connection.
    /// Takes the target position explicitly rather than reading
    /// `cameraPosition` — that's `@Published` and updated on the main queue
    /// asynchronously, so it can't be trusted to already reflect a flip
    /// that just happened on this (session) queue.
    private func applyConnectionOrientation(position: AVCaptureDevice.Position) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = (position == .front)
        }
    }
}

extension FaceEnrollmentCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
