//
//  FaceCameraService.swift
//  PillCounter
//
//  Minimal front-camera capture session shared by the face enrollment and
//  face authentication screens.
//  Deliberately separate from Features/Scanning's CameraService — that
//  class is wired for the back-camera pill-counting pipeline (barcode
//  metadata, tray/glove/pill detectors) and isn't a fit for a front-facing,
//  face-only capture screen. Frame delivery pattern (AVCaptureVideoDataOutput
//  delegate on a dedicated queue) mirrors CameraService's approach.
//

import AVFoundation
import CoreVideo
import UIKit

final class FaceCameraService: NSObject, ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var errorMessage: String?
    /// Which physical camera is currently feeding the session — drives the
    /// flip-camera button's icon/state in the UI.
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .front

    /// Live interface orientation the capture connections are rotated to.
    /// Published so FaceCameraPreview re-runs updateUIView on rotation and can
    /// re-assert the same angle on its own (separate) preview connection.
    /// Same shape as Features/Scanning's CameraService.currentCameraOrientation.
    @Published private(set) var currentCameraOrientation: UIDeviceOrientation = .portrait

    /// Called on the session queue for every frame — NOT the main thread.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "faceauth.camera.session.queue")
    private var isRunning = false
    private var currentInput: AVCaptureDeviceInput?
    /// Inputs/outputs survive a stop(), so a second start() must only
    /// resume the existing graph. Re-running the full configure would try
    /// to add a second input, fail canAddInput, and leave the session with
    /// no usable connection — the black preview seen on retry.
    private var isConfigured = false
    private var isObservingOrientation = false

    var previewSession: AVCaptureSession { session }

    func start() {
        seedOrientationFromScene()
        startObservingOrientation()
        checkPermissions()
    }

    func stop() {
        stopObservingOrientation()
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
            // Derived from the ACTIVE INPUT, not from `cameraPosition`: that is
            // @Published and only assigned on the main queue at the end of this
            // block, so two taps in quick succession would both read the same
            // stale value and compute the same "new" position — the second tap
            // reconfiguring to the camera already running. Same reasoning as
            // applyConnectionOrientation's `position` parameter.
            let currentPosition = self.currentInput?.device.position ?? .front
            let newPosition: AVCaptureDevice.Position = currentPosition == .front ? .back : .front

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                let newInput = try? AVCaptureDeviceInput(device: device)
            else {
                Log("FaceCameraService: flip failed — no camera at position \(newPosition)")
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
            Log("FaceCameraService: flipped to \(newPosition)")
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

            // Already built by an earlier start() — just resume it.
            if self.isConfigured {
                self.applyConnectionOrientation(position: self.cameraPosition)
                if !self.isRunning {
                    self.session.startRunning()
                    self.isRunning = true
                }
                return
            }

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
            self.isConfigured = true
            self.applyConnectionOrientation(position: self.cameraPosition)
            self.session.startRunning()
            self.isRunning = true
        }
    }

    // MARK: - Orientation

    /// Starts tracking device rotation. Same pattern as Features/Scanning's
    /// CameraService.startObservingOrientation — the service owns the
    /// notification so no view has to push orientation into it.
    private func startObservingOrientation() {
        // start() is re-entrant (retry re-runs it), so guard against stacking
        // duplicate observers that would each fire handleOrientationChange.
        guard !isObservingOrientation else { return }
        isObservingOrientation = true

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    private func stopObservingOrientation() {
        guard isObservingOrientation else { return }
        isObservingOrientation = false

        NotificationCenter.default.removeObserver(
            self, name: UIDevice.orientationDidChangeNotification, object: nil
        )
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    @objc private func handleOrientationChange() {
        let newOrientation = UIDevice.current.orientation
        guard newOrientation.isValidInterfaceOrientation,
              newOrientation != currentCameraOrientation
        else { return }

        currentCameraOrientation = newOrientation
        // Rotation invalidates the buffer geometry the aligner assumes, so the
        // data-output connection has to follow the device — without this the
        // connection stays pinned to the angle it had at configure time and
        // keeps feeding rotated buffers into alignment.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyConnectionOrientation(position: self.currentInput?.device.position ?? .front)
        }
    }

    /// Seeds `currentCameraOrientation`, preferring the live device sensor
    /// reading over the window scene's interface orientation.
    ///
    /// The scene reading is only a fallback, used when the device sensor
    /// hasn't reported yet — UIDevice.orientation is `.unknown` until
    /// `beginGeneratingDeviceOrientationNotifications()` has been called at
    /// least once anywhere in the process (this class's own
    /// `startObservingOrientation()` is the first and only place that
    /// happens for this service). On the very first scan of a cold launch —
    /// e.g. tapping "Verify with Face" on SessionLockOverlay — that has never
    /// run yet, so this fallback is not a rare edge case, it is the ONLY path
    /// taken on every first open.
    ///
    /// The scene reports a UIInterfaceOrientation, which uses the opposite
    /// landscape convention from UIDeviceOrientation: physically rotating the
    /// device so its right edge is up (device orientation `.landscapeRight`)
    /// makes the interface read as `.landscapeLeft`, and vice versa — a
    /// documented UIKit inversion, not a typo. Copying the case name directly
    /// (as a previous version of this method did) is off by 180° in
    /// landscape on that first-ever open; matches the swap
    /// `IdScanCameraService.initialOrientation()` already applies for the
    /// same reason.
    private func seedOrientationFromScene() {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isValidInterfaceOrientation {
            currentCameraOrientation = deviceOrientation
            return
        }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        switch scene.interfaceOrientation {
        case .landscapeLeft: currentCameraOrientation = .landscapeRight
        case .landscapeRight: currentCameraOrientation = .landscapeLeft
        case .portraitUpsideDown: currentCameraOrientation = .portraitUpsideDown
        default: currentCameraOrientation = .portrait
        }
    }

    /// Rotates the data-output connection to match how the device is held, and
    /// mirrors it for the front camera.
    ///
    /// Without the rotation, AVCaptureVideoDataOutput delivers frames in the
    /// sensor's native orientation regardless of how the device is held — every
    /// downstream box/landmark computation assumes an upright face, so a
    /// rotated buffer corrupts detection and (worse) silently shifts
    /// alignment/embeddings enough to match the wrong enrolled user.
    ///
    /// Must be called after every input change (initial configure AND
    /// flipCamera), since a fresh input creates a fresh connection, and after
    /// every rotation. Takes the target position explicitly rather than reading
    /// `cameraPosition` — that's `@Published` and updated on the main queue
    /// asynchronously, so it can't be trusted to already reflect a flip that
    /// just happened on this (session) queue.
    ///
    /// The rotation angle's landscape cases depend on whether `position` is
    /// mirrored (front camera) — see `rotationAngle(for:mirrored:)`. Confirmed
    /// on device: an un-mirrored-table angle left the front camera's preview
    /// 180° off in landscape, since mirroring the frame after rotating it
    /// reverses which landscape angle looks upright.
    private func applyConnectionOrientation(position: AVCaptureDevice.Position) {
        guard let connection = videoOutput.connection(with: .video) else { return }

        let angle = Self.rotationAngle(for: currentCameraOrientation, mirrored: position == .front)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = (position == .front)
        }
    }

    /// Rotation angle per device orientation. The four cases are 90° apart, in
    /// order, as they must be — any two orientations that differ by a physical
    /// 180° must differ by 180° here too.
    ///
    /// Based on Features/Scanning's CameraService.rotationAngle, with two
    /// corrections:
    /// - That table returns 90 for BOTH .portrait and .portraitUpsideDown,
    ///   which is 180° wrong for upside-down. It never surfaced there
    ///   (back camera, effectively single-orientation screens); here it
    ///   showed up as an inverted preview as soon as that orientation
    ///   became reachable.
    /// - `mirrored` swaps the landscapeLeft/landscapeRight angles. Confirmed
    ///   by device log: on an iPad physically in landscapeRight,
    ///   currentCameraOrientation correctly resolved to .landscapeLeft, but
    ///   the un-mirrored angle (0°) rendered the front-camera preview 180°
    ///   wrong — mirroring the frame after rotating it (vs. before) reverses
    ///   which landscape angle looks upright, so the front (mirrored) camera
    ///   needs the opposite angle from the back (unmirrored) camera for the
    ///   same physical orientation.
    static func rotationAngle(for orientation: UIDeviceOrientation, mirrored: Bool) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .landscapeLeft: return mirrored ? 180 : 0
        case .landscapeRight: return mirrored ? 0 : 180
        case .portraitUpsideDown: return 270
        // .faceUp / .faceDown / .unknown have no meaningful angle — hold
        // portrait rather than snapping the preview to something arbitrary.
        default: return 90
        }
    }
}

extension FaceCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
