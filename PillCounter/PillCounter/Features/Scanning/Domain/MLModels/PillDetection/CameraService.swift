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
    private let inactivityTimeout: TimeInterval = 100
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    // MARK: - CAMERA CORE
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var captureDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    // MARK: - BARCODE SCANNING
    @Published var scannedCode: String = ""
    @Published var scannedCodeType: String = ""
    private var barcodeEnabled: Bool = false
    private var hasScanned: Bool = false

    // MARK: - IMAGE PROCESSING
    private let detector = PillDetectionService()
    private let trayDetector = TrayDetectionService.shared

    
    private let ciContext = CIContext()
    private(set) var lastPixelBuffer: CVPixelBuffer?

    // MARK: - TIMER
    private var inactivityTimer: DispatchSourceTimer?

    // MARK: - PREVIEW
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    @Published private(set) var isSessionPaused = false

    // MARK: - STATE
    @Published var stableCount: Int = 0
    @Published var detections: [DetectionResult] = []
    @Published var trayDetections: [TrayResult] = []

    @Published var isAuthorized = false
    @Published var error: String?
    @Published private(set) var isPausedDueToInactivity = false
    /// When false, ML inference is skipped every frame — model stays loaded, camera keeps running.
    @Published private(set) var isCountingEnabled: Bool = true
    @Published private(set) var currentCameraOrientation: UIDeviceOrientation = .portrait
    @Published var zoomFactor: CGFloat = 1.0

    private let minZoom: CGFloat = 1.0
    private var maxzoom: CGFloat = 1.0
    


    @objc private func handleSessionInterruptionEnded() {
        DispatchQueue.main.async {
            self.start() // or resumeIfPaused()
        }
    }

    // MARK: - INIT
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

            // Barcode metadata output — added once; delegate set when enableBarcodeScanning() is called
            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.metadataObjectTypes = [
                    .qr, .ean8, .ean13, .pdf417,
                    .code128, .code39, .code93,
                    .upce, .aztec, .dataMatrix,
                    .interleaved2of5, .itf14
                ]
            }

            self.session.commitConfiguration()
        }
    }

    // MARK: - BARCODE CONTROL

    func enableBarcodeScanning() {
        // Must run on sessionQueue so it executes AFTER configureSession() completes.
        // Setting the delegate before the output is added to the session silently fails.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.hasScanned = false
            self.barcodeEnabled = true
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        }
    }

    func disableBarcodeScanning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.barcodeEnabled = false
            self.metadataOutput.setMetadataObjectsDelegate(nil, queue: .main)
        }
    }

    func resetBarcodeScanState() {
        // Clear published values synchronously — caller is always on main thread.
        // Doing this async allowed scannedCode onChange to re-fire with the stale
        // value before the clear landed, causing repeated API calls on NDC mismatch.
        // hasScanned is intentionally NOT reset here — only enableBarcodeScanning()
        // re-arms it, preventing the camera delegate from re-firing haptic/sound
        // while the barcode is still in frame between reset and the next enable call.
        scannedCode = ""
        scannedCodeType = ""
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
            self.previewLayer?.session = nil
        }
    }

    
    func rebindPreviewLayer() {
        guard let previewLayer = previewLayer else { return }

        previewLayer.session = nil
        previewLayer.session = session
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
    func cancelInactivityTimer() {
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

    // MARK: - COUNTING PAUSE / RESUME
    func pauseCounting() {
        guard isCountingEnabled else { return }
        isCountingEnabled = false
        DispatchQueue.main.async {
            self.stableCount = 0
            self.detections = []
            self.trayDetections = []
        }
    }

    func resumeCounting() {
        guard !isCountingEnabled else { return }
        isCountingEnabled = true
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
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isPausedDueToInactivity,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        lastPixelBuffer = pixelBuffer

        guard isCountingEnabled else { return }

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
                guard self.isCountingEnabled else { return }
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

        // 1. Build the oriented CIImage
        let rawCI = CIImage(cvPixelBuffer: pixelBuffer)
        let orientedCI = ciImageOriented(rawCI, orientation: currentCameraOrientation)

        guard let cgImage = ciContext.createCGImage(orientedCI, from: orientedCI.extent)
        else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // 2. Transform detection rects from raw-buffer space → oriented image space
        let rawSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let transformedDetections = detections.map { detection -> DetectionResult in
            let transformed = transformRect(
                detection.rect,
                from: rawSize,
                to: imageSize,
                orientation: currentCameraOrientation
            )
            return DetectionResult(
                rect: transformed,
                confidence: detection.confidence,
                originalFrameSize: detection.originalFrameSize
            )
        }

        // 3. Render
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { ctx in
            let context = ctx.cgContext

            // Draw oriented image (no flip needed — CIImage already handled it)
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: imageSize))

            // Draw badges at transformed positions
            transformedDetections.enumerated().forEach { index, detection in
                drawBadge(context: context, index: index, rect: detection.rect)
            }
        }
    }
    
    private func transformRect(
        _ rect: CGRect,
        from rawSize: CGSize,
        to orientedSize: CGSize,
        orientation: UIDeviceOrientation
    ) -> CGRect {

        // Normalise to [0,1] in raw space
        let nx = rect.minX / rawSize.width
        let ny = rect.minY / rawSize.height
        let nw = rect.width  / rawSize.width
        let nh = rect.height / rawSize.height

        // Apply the same logical rotation that ciImageOriented applies,
        // but in normalised coordinates, then scale to orientedSize.
        switch orientation {

        case .portrait:
            // CIImage.oriented(.right): (x,y) → (1-y, x)
            let tx = 1.0 - ny - nh
            let ty = nx
            let tw = nh
            let th = nw
            return CGRect(
                x: tx * orientedSize.width,
                y: ty * orientedSize.height,
                width: tw * orientedSize.width,
                height: th * orientedSize.height
            )

        case .landscapeLeft:
            // No rotation applied (.landscapeLeft)
            return CGRect(
                x: nx * orientedSize.width,
                y: ny * orientedSize.height,
                width: nw * orientedSize.width,
                height: nh * orientedSize.height
            )

        case .landscapeRight:
            // CIImage.oriented(.down): (x,y) → (1-x, 1-y)
            let tx = 1.0 - nx - nw
            let ty = 1.0 - ny - nh
            return CGRect(
                x: tx * orientedSize.width,
                y: ty * orientedSize.height,
                width: nw * orientedSize.width,
                height: nh * orientedSize.height
            )

        case .portraitUpsideDown:
            // CIImage.oriented(.left): (x,y) → (y, 1-x)
            let tx = ny
            let ty = 1.0 - nx - nw
            let tw = nh
            let th = nw
            return CGRect(
                x: tx * orientedSize.width,
                y: ty * orientedSize.height,
                width: tw * orientedSize.width,
                height: th * orientedSize.height
            )

        default:
            // Default to portrait
            let tx = 1.0 - ny - nh
            let ty = nx
            return CGRect(
                x: tx * orientedSize.width,
                y: ty * orientedSize.height,
                width: nh * orientedSize.width,
                height: nw * orientedSize.height
            )
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

// MARK: - BARCODE METADATA DELEGATE

extension CameraService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard barcodeEnabled,
              !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }

        hasScanned = true
        scannedCode = value
        scannedCodeType = object.type.rawValue
    }
}
