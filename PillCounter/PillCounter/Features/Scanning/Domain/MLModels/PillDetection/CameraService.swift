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

    /// Fraction of each tray rect's own width/height used to expand the counting
    /// region outward. Absorbs the tray model's tendency to draw the box slightly
    /// inside the real tray edge, so pills lying right at the border (e.g. the
    /// landscape gap between chute and tray) still count. Chute exclusion runs
    /// after this padding, so widening the tray can't re-add chute pills.
    private static let trayInsetPadFraction: CGFloat = 0.06

    /// Cap on how far a tray rect may be extended toward the chute, as a fraction of
    /// the tray's size along the extension axis. Prevents a far or spurious chute
    /// detection from ballooning the counting region across the whole frame.
    private static let trayChuteExtendMaxFraction: CGFloat = 0.30

    /// Reject a "tray" whose bbox covers at least this fraction of the frame — a
    /// background surface (e.g. the table) fills the frame, whereas a real tray is
    /// a bounded object inside it. Mirrors Android TRAY_MAX_FRAME_COVERAGE.
    private static let trayMaxFrameCoverage: CGFloat = 0.75

    /// Fraction the CHUTE rect is shrunk (inward) before a pill's centre is tested
    /// for "inside the chute". The chute mask's bounding box is a coarse rectangle
    /// that overhangs the tray↔chute boundary, so a pill lying in the channel right
    /// at the lip would land inside the raw chute box one frame and outside it the
    /// next — flickering in and out of the count. Requiring the centre to be WELL
    /// inside the chute (not just touching its bbox) keeps those border pills
    /// counted stably while still excluding pills that are genuinely deep in the
    /// dispenser slot.
    private static let chuteExclusionInsetFraction: CGFloat = 0.18

    /// Number of recent frames whose pill counts are kept for median smoothing.
    /// The raw per-frame count jitters ±1–2 even on a static scene (boundary pills
    /// crossing the confidence/region threshold); reporting the median over this
    /// window steadies the displayed number. Markers (dots) still come from the
    /// live frame, so they stay responsive. Mirrors Android PILL_COUNT_SMOOTH_WINDOW.
    private static let countSmoothWindow: Int = 5

    /// Rolling buffer of recent per-frame counts, oldest first. Median → stableCount.
    private var recentCounts: [Int] = []

    /// Extends `tray` toward the nearest chute rect so pills in the gap between the
    /// chute and the tray (which sit on the tray but outside its drawn box) are
    /// included. Only the tray edge that faces the chute is moved, up to the chute's
    /// near edge, capped by `trayChuteExtendMaxFraction`. Orientation-independent —
    /// it reacts to the actual chute position, so landscape and portrait match.
    private static func extendTowardNearestChute(_ tray: CGRect,
                                                 chuteRects: [CGRect]) -> CGRect {
        // Nearest chute by centre distance.
        guard let chute = chuteRects.min(by: { a, b in
            let da = hypot(a.midX - tray.midX, a.midY - tray.midY)
            let db = hypot(b.midX - tray.midX, b.midY - tray.midY)
            return da < db
        }) else { return tray }

        let dx = chute.midX - tray.midX
        let dy = chute.midY - tray.midY

        var result = tray

        if abs(dy) >= abs(dx) {
            // Chute is above or below — extend the tray vertically toward it.
            let maxExtend = tray.height * trayChuteExtendMaxFraction
            if dy < 0 {
                // Chute above: pull the top edge up to the chute's bottom.
                let target = max(chute.maxY, tray.minY - maxExtend)
                let newMinY = min(tray.minY, max(target, tray.minY - maxExtend))
                result = CGRect(x: tray.minX, y: newMinY,
                                width: tray.width, height: tray.maxY - newMinY)
            } else {
                // Chute below: push the bottom edge down to the chute's top.
                let target = min(chute.minY, tray.maxY + maxExtend)
                let newMaxY = max(tray.maxY, min(target, tray.maxY + maxExtend))
                result = CGRect(x: tray.minX, y: tray.minY,
                                width: tray.width, height: newMaxY - tray.minY)
            }
        } else {
            // Chute is left or right — extend the tray horizontally toward it.
            let maxExtend = tray.width * trayChuteExtendMaxFraction
            if dx < 0 {
                // Chute left: pull the left edge out to the chute's right.
                let target = max(chute.maxX, tray.minX - maxExtend)
                let newMinX = min(tray.minX, max(target, tray.minX - maxExtend))
                result = CGRect(x: newMinX, y: tray.minY,
                                width: tray.maxX - newMinX, height: tray.height)
            } else {
                // Chute right: push the right edge out to the chute's left.
                let target = min(chute.minX, tray.maxX + maxExtend)
                let newMaxX = max(tray.maxX, min(target, tray.maxX + maxExtend))
                result = CGRect(x: tray.minX, y: tray.minY,
                                width: newMaxX - tray.minX, height: tray.height)
            }
        }

        return result
    }

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

    /// The generic colour of the currently-visible tray. Re-published whenever the
    /// classified colour CHANGES (not every frame), so the hazardous-tray flow can
    /// react both to the first tray and to the operator swapping trays mid-session.
    /// nil until the first tray is sampled. Drives the hazardous-tray flow.
    @Published var detectedTrayColor: TrayColor? = nil

    /// The last colour we published to `detectedTrayColor`, used to suppress
    /// duplicate frame-by-frame emissions and only fire on an actual colour change.
    private var lastSampledTrayColor: TrayColor? = nil

    /// Gates tray-colour sampling. The view enables this only while the pill-count
    /// bottom sheet is showing in the dispense / stock-scan-pills flows; otherwise
    /// the camera classifies no trays at all (hazardous-tray flow is inactive).
    var isTrayColorDetectionEnabled: Bool = false

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
            if !self.session.isRunning {
                self.session.startRunning()
            }
            // Always re-attach the preview layer to the session AFTER the session is
            // confirmed running. start() is self-healing and symmetric with stop():
            // whatever state the preview was left in (detached by a prior stop(), or
            // never bound), calling start() guarantees the live feed shows. Doing this
            // here — on the session queue, post-startRunning — also closes the old race
            // where a stray `previewLayer.session = nil` from stop() could land on the
            // main queue *after* a start() and blank a freshly-running preview.
            DispatchQueue.main.async {
                if self.previewLayer?.session !== self.session {
                    self.previewLayer?.session = self.session
                }
            }
        }
        setZoom(zoomFactor == 0 ? 1.0 : zoomFactor)
        resetInactivityTimer()
    }

    /// STOPS CAMERA SESSION
    /// Stops the running session but intentionally KEEPS the preview layer bound to it.
    /// A stopped AVCaptureSession freezes the preview on its last frame (smooth), and
    /// the next start() resumes instantly. Nulling previewLayer.session here is what
    /// previously caused the permanent blank-screen-with-detection-still-working bug,
    /// because start() never re-attached it. So we no longer detach on stop.
    func stop() {
        cancelInactivityTimer()

        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            // Session is fully stopped — no barcodes are visible. Clear the lock
            // so the next start() begins fresh rather than blocking on a stale value.
            self.lockedBarcodeValue = nil
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
            self.recentCounts.removeAll()   // start the next session's median fresh
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
            self.detectedTrayColor    = nil
            self.lastSampledTrayColor = nil
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

        // CHUTE regions: pills sitting in the chute (dispenser slot) must NOT be
        // counted even if the tray box happens to overlap them. Excluding any pill
        // whose centre is inside a chute rect fixes the portrait case where chute
        // pills near the tray's top lip were being counted.
        let chuteRects = allTrays.filter { $0.trayClass == .chute }.map { $0.rect }

        // Build the counting region from each tray rect in two steps:
        //
        //  1. Uniform pad — the tray model draws the box slightly inside the real
        //     tray edge, so pills at the border fall just outside. Pad by a fraction
        //     of the rect's own size to recover them.
        //
        //  2. Extend toward the chute — pills lying in the gap between the chute and
        //     the tray (most visible in landscape, where the tray's top edge cuts
        //     right below the chute lip) are on the tray but outside its box. Grow
        //     the tray rect's chute-facing edge up to the chute's near edge so those
        //     pills are included. This is geometric, not orientation-specific, so
        //     portrait and landscape behave identically. Chute exclusion still runs
        //     afterward, so anything actually in the chute is removed.
        let countingRects = trayRects.map { rect -> CGRect in
            let padX = rect.width  * Self.trayInsetPadFraction
            let padY = rect.height * Self.trayInsetPadFraction
            let padded = rect.insetBy(dx: -padX, dy: -padY)
            return Self.extendTowardNearestChute(padded, chuteRects: chuteRects)
        }

        // ── "Complete product" gate (mirrors Android TrayGate) ───────────────
        // A valid scene requires BOTH a tray AND a chute, and the tray must NOT
        // fill the frame (that would be the background surface, not a tray).
        // When the gate is closed: no pill count and no tray/chute overlay. This
        // matches Android: a tray-only, chute-only, or table-filling-frame scene
        // is "not a complete product" and surfaces nothing.
        let frameSz = pixelBuffer.size
        let frameArea = max(1, frameSz.width * frameSz.height)
        let trayCoverage = trayRects
            .map { ($0.width * $0.height) / frameArea }
            .max() ?? 0
        let trayFillsFrame = trayCoverage >= Self.trayMaxFrameCoverage
        let isCompleteTray = !trayRects.isEmpty && !chuteRects.isEmpty && !trayFillsFrame

        // Overlay shows tray/chute only when the scene is a complete product.
        let displayTrays = isCompleteTray ? allTrays : []

        // ── Tray colour sampling (hazardous-tray feature) ────────────────────
        // Continuously classify the visible tray's generic colour and publish it
        // only when the colour CHANGES (not every frame). This lets the flow react
        // to the operator swapping trays mid-session. Gated by
        // isTrayColorDetectionEnabled so it runs ONLY while the pill-count sheet is
        // showing in the dispense / stock-scan-pills flows. Runs regardless of
        // isGloveDetectionEnabled because the non-hazardous flow also needs it.
        if isTrayColorDetectionEnabled, let firstTrayRect = trayRects.first,
           let color = TrayColorClassifier.dominantColor(in: pixelBuffer, rect: firstTrayRect) {
            DispatchQueue.main.async {
                guard self.isTrayColorDetectionEnabled, self.isCountingEnabled else { return }
                guard color != self.lastSampledTrayColor else { return }
                self.lastSampledTrayColor = color
                self.detectedTrayColor    = color
            }
        }

        // ── Model 3: Pill detection (PP-YOLOE+s 640×640) ─────────────────────
        detector.detect(pixelBuffer: pixelBuffer) { [weak self] allPills, _ in
            guard let self else { return }

            // Counting GATE: only count once the scene is a complete product
            // (tray AND chute, tray not filling frame). Otherwise count = 0.
            // Then keep only pills whose centre falls inside a (padded) TRAY rect
            // AND is NOT inside any CHUTE rect.
            let filtered: [DetectionResult]
            if !isCompleteTray || countingRects.isEmpty {
                filtered = []
            } else {
                // Shrink each chute rect inward so only pills WELL inside the chute
                // are excluded; pills in the channel right at the tray↔chute lip
                // stay counted (and stop flickering frame-to-frame).
                let chuteExclusionRects = chuteRects.map { rect -> CGRect in
                    rect.insetBy(dx: rect.width  * Self.chuteExclusionInsetFraction,
                                 dy: rect.height * Self.chuteExclusionInsetFraction)
                }
                filtered = allPills.filter { pill in
                    let center = pill.center
                    let inTray  = countingRects.contains { $0.contains(center) }
                    guard inTray else { return false }
                    let inChute = chuteExclusionRects.contains { $0.contains(center) }
                    return !inChute
                }
            }

            let hazardous        = gloves.contains { $0.isHazardous }
            let glovesNowSafe    = !self.glovesConfirmed && gloves.contains { $0.gloveClass == .glove }

            DispatchQueue.main.async {
                guard self.isCountingEnabled else { return }

                // Markers (dots) come from the LIVE frame so they stay responsive.
                self.detections = filtered

                // Displayed/committed count is the MEDIAN over the last few frames,
                // so a single boundary pill blinking across the threshold doesn't
                // jitter the number. Median (not mean) ignores the occasional spike.
                self.recentCounts.append(filtered.count)
                if self.recentCounts.count > Self.countSmoothWindow {
                    self.recentCounts.removeFirst()
                }
                let sortedCounts = self.recentCounts.sorted()
                self.stableCount = sortedCounts[sortedCounts.count / 2]

                self.trayDetections   = displayTrays
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
