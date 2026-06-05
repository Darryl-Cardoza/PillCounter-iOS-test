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
    // The value of the barcode currently locked in frame. Non-nil means we already
    // fired the scan event and are waiting for the physical barcode to leave the
    // camera's field of view before we fire again. Set to nil the moment the
    // metadata delegate reports an empty (or different-value) frame.
    private var lockedBarcodeValue: String? = nil

    // MARK: - IMAGE PROCESSING
    // Three-model inference pipeline running on every captured camera frame:
    //   1. GloveDetectionService  — YOLOX-Nano 320×320 (rate-limited to 400 ms after first hit)
    //   2. TrayDetectionService   — MobileNetV2-UNet segmentation 384×384 (every frame)
    //                               argmax → 384×384 label map → bounding boxes for TRAY / CHUTE
    //   3. PillDetectionService   — PP-YOLOE+s 640×640 (every frame, filtered by tray rects)
    private let detector       = PillDetectionService()
    private let trayDetector   = TrayDetectionService.shared
    private let gloveDetector  = GloveDetectionService()

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

    /// All glove detections from the most recent inference run (rate-limited to 400 ms
    /// after the first detection).  Empty when gloves have never been checked or when
    /// no hands are visible in the frame.
    @Published var gloveDetections: [GloveDetectionResult] = []

    /// True when at least one detected region in the current frame has a bare hand
    /// (GloveClass.noGlove).  Drives the UI warning banner.
    @Published var isGloveHazardous: Bool = false

    /// True once gloves (GloveClass.glove) have been confirmed for the current session.
    /// When true, glove model inference is skipped — the hand icon stays green.
    /// Reset to false via resetGloveDetection() when the inactivity-pause resume button is tapped.
    @Published var glovesConfirmed: Bool = false

    /// Set to true by UnifiedCameraView when the current drug is hazardous (drug.is_hazardous == true).
    /// When false, glove model inference is completely skipped and the indicator is hidden.
    @Published var isGloveDetectionEnabled: Bool = false

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
            self.barcodeEnabled = true
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        }
    }

    func disableBarcodeScanning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.barcodeEnabled = false
            // Intentionally preserve lockedBarcodeValue. If scanning is re-enabled
            // while the same physical barcode is still in frame, the lock prevents
            // it from immediately re-firing. The lock is only released when the
            // frame-presence check sees the barcode has left the camera view.
            self.metadataOutput.setMetadataObjectsDelegate(nil, queue: .main)
        }
    }

    func resetBarcodeScanState() {
        // Clears published values so the view's onChange does not re-fire with a
        // stale value. lockedBarcodeValue is NOT cleared here — the physical barcode
        // may still be in frame. Clearing it would re-fire the scan event on the
        // very next metadata callback. The lock releases only when the frame-presence
        // check confirms the barcode has physically left the camera view.
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
            // Session is fully stopped — no barcodes are visible. Clear the lock
            // so the next start() begins fresh rather than blocking on a stale value.
            self.lockedBarcodeValue = nil
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
            self.stableCount      = 0
            self.detections       = []
            self.trayDetections   = []
            self.gloveDetections  = []
            self.isGloveHazardous = false
        }
    }

    func resumeCounting() {
        guard !isCountingEnabled else { return }
        isCountingEnabled = true
    }

    /// Resets glove-detection state so the glove model runs again from scratch.
    /// Call this when the user resumes from an inactivity pause (new operator may have
    /// taken over) so gloves must be re-verified for the resumed session.
    func resetGloveDetection() {
        gloveDetector.reset()
        DispatchQueue.main.async {
            self.glovesConfirmed  = false
            self.gloveDetections  = []
            self.isGloveHazardous = false
        }
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

        // ── Model 1: Glove safety detection (YOLOX-Nano 320×320) ──────────────
        // Only runs when the current drug is hazardous (isGloveDetectionEnabled) AND
        // gloves haven't been confirmed yet for this session (glovesConfirmed).
        // GloveDetectionService applies its own 400 ms rate limiter internally;
        // the call returns [] immediately when the throttle is active.
        let gloves: [GloveDetectionResult] = (isGloveDetectionEnabled && !glovesConfirmed)
            ? gloveDetector.detect(pixelBuffer: pixelBuffer)
            : []

        // ── Model 2: Tray / chute detection (RTMDet-Tiny 640×640) ────────────
        // Returns both .tray and .chute regions; only .tray regions gate pill counts.
        let allTrays = trayDetector.detect(pixelBuffer: pixelBuffer)

        // Only TRAY regions (class 0) are used to filter pill positions.
        // CHUTE regions (class 1) are passed to the overlay for display only.
        let trayRects = allTrays.filter { $0.trayClass == .tray }.map { $0.rect }

        // ── Model 3: Pill detection (PP-YOLOE+s 640×640) ─────────────────────
        detector.detect(pixelBuffer: pixelBuffer) { [weak self] allPills, _ in
            guard let self else { return }

            // Keep only pills whose centre falls inside a TRAY (not CHUTE) rect.
            // An empty trayRects list means no tray is visible → count = 0.
            let filtered: [DetectionResult]
            if trayRects.isEmpty {
                filtered = []
            } else {
                filtered = allPills.filter { pill in
                    trayRects.contains { trayRect in trayRect.contains(pill.center) }
                }
            }

            let hazardous        = gloves.contains { $0.isHazardous }
            let glovesNowSafe    = !self.glovesConfirmed && gloves.contains { $0.gloveClass == .glove }

            DispatchQueue.main.async {
                guard self.isCountingEnabled else { return }
                self.detections       = filtered
                self.stableCount      = filtered.count
                self.trayDetections   = allTrays
                self.gloveDetections  = gloves
                self.isGloveHazardous = hazardous
                if glovesNowSafe { self.glovesConfirmed = true }
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
        guard barcodeEnabled else { return }

        // Collect all currently-visible barcode values this frame.
        let visibleValues = metadataObjects
            .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .compactMap { $0.stringValue }

        // If the previously locked barcode is no longer in the frame, release the
        // lock immediately — no timer, no cooldown. The next real barcode can fire
        // the moment it enters the frame.
        if let locked = lockedBarcodeValue, !visibleValues.contains(locked) {
            lockedBarcodeValue = nil
        }

        // Fire a scan event only when:
        //   • there is no locked barcode (we are ready for a new scan), AND
        //   • a barcode is actually present in the current frame.
        guard lockedBarcodeValue == nil,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }

        lockedBarcodeValue = value
        scannedCode = value
        scannedCodeType = object.type.rawValue
    }
}
