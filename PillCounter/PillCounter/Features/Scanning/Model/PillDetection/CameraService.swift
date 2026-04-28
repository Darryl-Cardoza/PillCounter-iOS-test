//
//  CameraService.swift
//  PillCounter
//
//  Optimized for performance, safety, and maintainability
//

import AVFoundation
import SwiftUI

final class CameraService: NSObject, ObservableObject {

    // MARK: - CONSTANTS
    private let inactivityTimeout: TimeInterval = 25
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    // MARK: - CAMERA CORE
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var captureDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    // MARK: - IMAGE PROCESSING
    private let detector = PillDetectionService()
    private let trayDetector = TrayDetectionService.shared

    
    private let ciContext = CIContext()
    private(set) var lastPixelBuffer: CVPixelBuffer?

    // MARK: - TIMER
    private var inactivityTimer: DispatchSourceTimer?

    // MARK: - PREVIEW
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - STATE
    @Published var stableCount: Int = 0
    @Published var detections: [DetectionResult] = []
    @Published var trayDetections: [TrayResult] = []

    @Published var isAuthorized = false
    @Published var error: String?
    @Published private(set) var isPausedDueToInactivity = false
    @Published private(set) var currentCameraOrientation: UIDeviceOrientation =
        .portrait
    @Published var zoomFactor: CGFloat = 1.0

    private let minZoom: CGFloat = 1.0
    private var maxzoom: CGFloat = 1.0

    // MARK: - INIT
    /// INITIALIZES CAMERA SERVICE AND CHECKS PERMISSIONS
    override init() {
        super.init()
        checkPermissions()
    }

    // MARK: - PERMISSIONS
    /// CHECKS AND REQUESTS CAMERA AUTHORIZATION
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configureSession() }
                }
            }
        default:
            error = "Camera access denied"
        }
    }

    // MARK: - SESSION CONFIGURATION
    /// CONFIGURES CAMERA INPUT, OUTPUT AND SESSION PRESET
    private func configureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                DispatchQueue.main.async { self.error = "Camera unavailable" }
                self.session.commitConfiguration()
                return
            }

            self.captureDevice = device
            self.maxzoom = min(device.activeFormat.videoMaxZoomFactor, 5.0)
            self.videoInput = input
            self.session.addInput(input)

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(
                self,
                queue: self.sessionQueue)

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - ZOOM CONTROL
    func setZoom(_ factor: CGFloat) {
        guard let device = captureDevice else { return }

        let clamped = max(minZoom, min(factor, maxzoom))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()

            DispatchQueue.main.async {
                self.zoomFactor = clamped
            }
        } catch {
            // Intentionally silent – zoom failure should not break camera
        }
    }

    // MARK: - SESSION CONTROL
    /// STARTS CAMERA SESSION
    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
        setZoom(zoomFactor == 0 ? 1.0 : zoomFactor)
        resetInactivityTimer()
    }

    /// STOPS CAMERA SESSION
    func stop() {
        cancelInactivityTimer()

        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }

        DispatchQueue.main.async {
            self.previewLayer?.session = nil   // ✅ IMPORTANT
        }
    }

    /// RETURNS ACTIVE CAPTURE SESSION
    func getSession() -> AVCaptureSession {
        session
    }

    // MARK: - INACTIVITY HANDLING
    /// RESETS USER INACTIVITY TIMER
    func resetInactivityTimer() {
        cancelInactivityTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + inactivityTimeout)
        timer.setEventHandler { [weak self] in
            self?.pauseForInactivity()
        }
        timer.resume()
        inactivityTimer = timer
    }

    /// CANCELS INACTIVITY TIMER
    private func cancelInactivityTimer() {
        inactivityTimer?.cancel()
        inactivityTimer = nil
    }

    /// PAUSES CAMERA WHEN USER IS INACTIVE
    private func pauseForInactivity() {
        guard !isPausedDueToInactivity else { return }
        stop()
        isPausedDueToInactivity = true
    }

    /// RESUMES CAMERA AFTER INACTIVITY
    func resumeIfPaused() {
        guard isPausedDueToInactivity else { return }
        configureInitialOrientation()
        startObservingOrientation()
        start()
        isPausedDueToInactivity = false
    }

    // MARK: - ORIENTATION
    /// STARTS LISTENING TO DEVICE ORIENTATION CHANGES
    func startObservingOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    /// HANDLES DEVICE ORIENTATION CHANGE
    @objc private func handleOrientationChange() {
        let newOrientation = UIDevice.current.orientation
        guard newOrientation.isValidInterfaceOrientation,
            newOrientation != currentCameraOrientation
        else { return }

        currentCameraOrientation = newOrientation
        applyOrientation()
    }

    /// CONFIGURES INITIAL CAMERA ORIENTATION
    func configureInitialOrientation() {
        currentCameraOrientation = initialOrientation()
        applyOrientation()
    }

    /// RETURNS INITIAL ORIENTATION FROM WINDOW SCENE
    private func initialOrientation() -> UIDeviceOrientation {
        guard
            let scene = UIApplication.shared.connectedScenes.first
                as? UIWindowScene
        else { return .portrait }

        switch scene.interfaceOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    /// APPLIES VIDEO ROTATION TO PREVIEW LAYER
    private func applyOrientation() {
        DispatchQueue.main.async {
            guard let connection = self.previewLayer?.connection else { return }
            let angle = self.rotationAngle(for: self.currentCameraOrientation)
            guard connection.isVideoRotationAngleSupported(angle) else {
                return
            }
            connection.videoRotationAngle = angle
            self.previewLayer?.frame =
                self.previewLayer?.superlayer?.bounds ?? .zero
        }
    }

    /// MAPS DEVICE ORIENTATION TO ROTATION ANGLE
    private func rotationAngle(for orientation: UIDeviceOrientation) -> CGFloat
    {
        switch orientation {
        case .portrait: return 90
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 90
        default: return 90
        }
    }
    
    private func ciImageOriented(
        _ image: CIImage,
        orientation: UIDeviceOrientation
    ) -> CIImage {

        switch orientation {
        case .portrait:
            return image.oriented(.right)

        case .landscapeLeft:
            return image

        case .landscapeRight:
            return image.oriented(.down)

        case .portraitUpsideDown:
            return image.oriented(.left)

        default:
            return image.oriented(.right)
        }
    }
}

// MARK: - SAMPLE BUFFER DELEGATE
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// RECEIVES CAMERA FRAMES AND RUNS DETECTION
//    func captureOutput(
//        _ output: AVCaptureOutput,
//        didOutput sampleBuffer: CMSampleBuffer,
//        from connection: AVCaptureConnection
//    ) {
//
//        guard !isPausedDueToInactivity,
//            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
//        else { return }
//
//        lastPixelBuffer = pixelBuffer
//
//        detector.detect(pixelBuffer: pixelBuffer) {
//            [weak self] detections, count in
//            DispatchQueue.main.async {
//                self?.detections = detections
//                self?.stableCount = count
//            }
//        }
//    }
    
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isPausedDueToInactivity,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        lastPixelBuffer = pixelBuffer

        // 1. Run tray detection FIRST (synchronous — no completion needed)
        let trays = trayDetector.detect(pixelBuffer: pixelBuffer)

        // 2. Run pill detection, then filter results by tray bounds
        detector.detect(pixelBuffer: pixelBuffer) { [weak self] allPills, count in
            guard let self else { return }

            // 3. Keep only pills whose centre falls inside any tray rect
            let filtered: [DetectionResult]
            if trays.isEmpty {
                filtered = []
            } else {
                filtered = allPills.filter { pill in
                    trays.contains { tray in
                        tray.rect.contains(pill.center)
                    }
                }
            }

            DispatchQueue.main.async {
                self.detections     = filtered
                self.stableCount    = filtered.count
                self.trayDetections = trays
            }
        }
    }
}

// MARK: - SNAPSHOT CAPTURE
extension CameraService {
    /// CAPTURES SNAPSHOT WITH DETECTION OVERLAYS
    func captureSnapshotWithOverlays() -> UIImage? {
        guard let pixelBuffer = lastPixelBuffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard
            let cgImage = ciContext.createCGImage(
                ciImage,
                from: ciImage.extent)
        else { return nil }

        let size = CGSize(
            width: ciImage.extent.width,
            height: ciImage.extent.height)

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let context = ctx.cgContext

            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()

            detections.enumerated().forEach { index, detection in
                drawBadge(
                    context: context,
                    index: index,
                    rect: detection.rect
                )
            }
        }
    }
    
    func captureSnapshot() -> UIImage? {

        guard let pixelBuffer = lastPixelBuffer else { return nil }

        let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciImage = ciImageOriented(rawImage, orientation: currentCameraOrientation)

        guard let cgImage = ciContext.createCGImage(
            ciImage,
            from: ciImage.extent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
    
    
    /// DRAWS NUMBERED BADGE OVER DETECTION RECT
    private func drawBadge(
        context: CGContext,
        index: Int,
        rect: CGRect
    ) {
        let circleSize: CGFloat = min(rect.width, rect.height) * 0.6
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let circleRect = CGRect(
            x: center.x - circleSize / 2,
            y: center.y - circleSize / 2,
            width: circleSize,
            height: circleSize
        )

        // Fill circle
        context.setFillColor(UIColor.black.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(in: circleRect)

        // Stroke circle
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: circleRect)

        // Draw count text
        let text = "\(index + 1)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: circleSize * 0.4),
            .foregroundColor: UIColor.white
        ]

        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        text.draw(in: textRect, withAttributes: attributes)
    }

}
