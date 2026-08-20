//
//  IdScanCameraService.swift
//  PillCounter
//
//  Back-camera capture session for the photo ID scan step. Modelled on
//  FaceCameraService (same AVCaptureSession + AVCaptureVideoDataOutput +
//  dedicated session queue shape), with ID-scan-specific differences: back
//  camera fixed (no flip), never mirrored, continuous autofocus/exposure.
//  See plans/face-auth/ocr/19-08-2026-12-31-ocr-id-scan.md §3.1.
//
//  Does not touch FaceCameraService, whose orientation/mirroring logic is
//  tuned for front-camera face alignment.
//

import AVFoundation
import CoreVideo
import UIKit

final class IdScanCameraService: NSObject, ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var currentCameraOrientation: UIDeviceOrientation = .portrait
    @Published private(set) var isRunning = false

    /// Called on the session queue for every frame — NOT the main thread.
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "ocr.idscan.camera.session.queue")
    private var currentInput: AVCaptureDeviceInput?

    /// Second start() must only resume the existing graph — see
    /// FaceCameraService's identical guard for the black-preview failure mode
    /// this avoids.
    private var isConfigured = false
    private var isObservingOrientation = false
    private var isObservingInterruptions = false

    var previewSession: AVCaptureSession { session }

    /// Sets the initial rotation angle and starts observing rotation
    /// notifications. Call BEFORE `start()`, same order as
    /// `CameraService.configureInitialOrientation()` +
    /// `startObservingOrientation()` — that back-camera service has the
    /// identical preview-connection-vs-session-setup timing requirement and
    /// is proven not to show the initial-frame inversion this ordering avoids.
    func configureInitialOrientation() {
        currentCameraOrientation = Self.initialOrientation()
        startObservingOrientation()
    }

    func start() {
        startObservingInterruptions()
        checkPermissions()
    }

    func stop() {
        stopObservingOrientation()
        stopObservingInterruptions()
        sessionQueue.async { [weak self] in
            guard let self, self.isRunningUnsafe else { return }
            self.session.stopRunning()
            self.setRunning(false)
        }
    }

    // Read/write only from the session queue.
    private var isRunningUnsafe = false
    private func setRunning(_ value: Bool) {
        isRunningUnsafe = value
        DispatchQueue.main.async { self.isRunning = value }
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

            if self.isConfigured {
                self.applyConnectionOrientation()
                if !self.isRunningUnsafe {
                    self.session.startRunning()
                    self.setRunning(true)
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
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.errorMessage = "Camera unavailable" }
                return
            }
            self.session.addInput(input)
            self.currentInput = input
            self.configureContinuousFocusAndExposure(on: device)

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
            self.applyConnectionOrientation()
            self.session.startRunning()
            self.setRunning(true)
        }
    }

    /// `.continuousAutoFocus` is a device mode, not a one-shot, so (unlike
    /// Android's periodic-autofocus loop) it only needs to be set once here.
    private func configureContinuousFocusAndExposure(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            Log("IdScanCameraService: could not lock device for continuous AF/AE — \(error)")
        }
    }

    // MARK: - Orientation

    private func startObservingOrientation() {
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
        sessionQueue.async { [weak self] in
            self?.applyConnectionOrientation()
        }
    }

    /// Converts UIInterfaceOrientation (what the scene reports) to
    /// UIDeviceOrientation (what this service's rotation table and
    /// handleOrientationChange speak) — landscape swaps, since the two enums
    /// name opposite physical rotations. Exact convention as
    /// CameraService.initialOrientation, the other back-camera service in
    /// this app, proven not to show an initial-frame inversion.
    private static func initialOrientation() -> UIDeviceOrientation {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return .portrait }
        switch scene.interfaceOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    /// Same rotation table as CameraService.rotationAngle (the other
    /// back-camera service — paired with the same seed convention above),
    /// never mirrored since Vision expects upright, unmirrored text.
    private func applyConnectionOrientation() {
        guard let connection = videoOutput.connection(with: .video) else { return }

        let angle = Self.rotationAngle(for: currentCameraOrientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }
    }

    /// Not private — IdScanCameraPreview's own connection needs the same
    /// table so the preview and the Vision-facing videoOutput connection
    /// never disagree on rotation.
    static func rotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 90
        default: return 90
        }
    }

    // MARK: - Interruption handling

    /// The session lock overlay runs its own AVCaptureSession, so iOS may
    /// interrupt ours (Android has no equivalent to port — CameraX doesn't
    /// compete with a second session the way AVFoundation can here).
    private func startObservingInterruptions() {
        guard !isObservingInterruptions else { return }
        isObservingInterruptions = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: .AVCaptureSessionWasInterrupted, object: session
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded, object: session
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRuntimeError),
            name: .AVCaptureSessionRuntimeError, object: session
        )
    }

    private func stopObservingInterruptions() {
        guard isObservingInterruptions else { return }
        isObservingInterruptions = false

        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
    }

    @objc private func handleInterruption() {
        sessionQueue.async { [weak self] in
            self?.setRunning(false)
        }
    }

    @objc private func handleInterruptionEnded() {
        restartSession()
    }

    @objc private func handleRuntimeError() {
        restartSession()
    }

    private func restartSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.setRunning(self.session.isRunning)
        }
    }
}

extension IdScanCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
