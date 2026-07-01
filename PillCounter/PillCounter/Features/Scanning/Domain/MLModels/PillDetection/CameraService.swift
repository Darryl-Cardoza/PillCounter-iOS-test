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
    // fired the scan event and are waiting for the physical barcode to physically
    // leave the camera's field of view before we fire again.
    //
    // The lock is released only after barcodeLockMissThreshold consecutive frames
    // with no matching barcode. This debounce absorbs brief metadata dropouts from
    // camera shake (1-2 frames) without blocking a genuine remove-and-rescan — a
    // physical hand moving a bottle away takes well over 5 frames at 30 fps.
    private var lockedBarcodeValue: String? = nil

    // How many consecutive frames the locked barcode must be absent before the lock
    // releases. 5 frames at 30 fps ≈ 165 ms — enough to survive a shake dropout but
    // short enough that a real remove-and-rescan is never blocked.
    private static let barcodeLockMissThreshold: Int = 5
    // Running count of consecutive metadata frames where lockedBarcodeValue was absent.
    private var barcodeLockMissFrames: Int = 0

    // MARK: - IMAGE PROCESSING
    // Three-model inference pipeline running on every captured camera frame:
    //   1. GloveDetectionService  — YOLOX-Nano 320×320 (rate-limited to 400 ms after first hit)
    //   2. TrayDetectionService   — MobileNetV2-UNet segmentation 384×384 (every frame)
    //                               argmax → 384×384 label map → bounding boxes for TRAY / CHUTE
    //   3. PillDetectionService   — PP-YOLOE+s 640×640 (every frame, filtered by tray rects)
    private let detector       = PillDetectionService()
    private let trayDetector   = TrayDetectionService.shared
    private let gloveDetector  = GloveDetectionService()

    /// Reject a "tray" whose bbox covers at least this fraction of the frame — a
    /// background surface (e.g. the table) fills the frame, whereas a real tray is
    /// a bounded object inside it. Matches Android TRAY_MAX_FRAME_COVERAGE = 0.75.
    private static let trayMaxFrameCoverage: CGFloat = 0.75

    /// Number of recent frames whose pill counts are kept for median smoothing.
    /// The raw per-frame count jitters ±1–2 even on a static scene; reporting the
    /// median over this window steadies the displayed number. Markers (dots) still
    /// come from the live frame, so they stay responsive. Matches Android
    /// PILL_COUNT_SMOOTH_WINDOW = 5.
    private static let countSmoothWindow: Int = 5

    /// Rolling buffer of recent per-frame counts, oldest first. Median → stableCount.
    private var recentCounts: [Int] = []

    /// Number of consecutive empty frames (gate closed OR model found 0 pills) the
    /// last non-zero count is held before it is allowed to drain toward zero. The
    /// median over countSmoothWindow only tolerates ±1–2 jitter — it flips to 0 as
    /// soon as a short burst of empty frames (a momentary segmentation/gate flicker
    /// or a blurred frame) fills the window with zeros, which is the "count suddenly
    /// drops to 0 even though pills are still there" symptom. While we are inside the
    /// hold the empty frame is NOT pushed into the median, so stableCount stays put.
    /// Once empties persist past the hold the zeros flow in normally, so the count
    /// still falls to 0 when the tray is genuinely emptied or removed.
    private static let countHoldFrames: Int = 5

    /// Consecutive empty-frame counter feeding the countHoldFrames hold.
    private var emptyCountFrames: Int = 0

    /// Number of consecutive frames the last-good tray/chute detections are held
    /// after a momentary segmentation miss, so the overlay + pill gate don't blink
    /// on an otherwise-steady scene. Matches Android TRAY_HOLD_FRAMES = 1: kept
    /// short so the tray (and the pill markers gated by it) clear almost immediately
    /// when the camera moves away — a longer hold leaves a visible ghost of the old
    /// box. The COUNT is separately protected from a single dropped frame by the
    /// median over countSmoothWindow, so a 1-frame hold is enough.
    private static let trayHoldFrames: Int = 1

    /// Last-good tray/chute detections (with masks) and the miss counter, used to
    /// bridge a single dropped segmentation frame. Mirrors Android
    /// heldTrayDetections / trayMissFrames. Reset on counting pause/resume.
    private var heldTrayDetections: [TrayResult] = []
    private var trayMissFrames: Int = 0

    /// True once AE/AF/AWB have been locked for the current counting session.
    /// The `.hd1280x720` preset already steadies the stream, but residual 3A
    /// micro-adjustments still wobble borderline pills, and — critically — a hand
    /// reaching into the tray retriggers auto-exposure for the WHOLE scene, which
    /// shifts every pill's confidence at once and makes the count chaotic during
    /// occlusion. Locking exposure/focus/white-balance once the tray is acquired
    /// freezes the imaging so only real pill changes move the count. Reset on
    /// counting pause/resume so a new scene re-meters before locking again.
    private var is3ALocked = false

    private let ciContext = CIContext()
    private(set) var lastPixelBuffer: CVPixelBuffer?

    /// Target inference rate. The camera delivers frames at the device default
    /// (~30 fps), but the three-model pipeline (glove + tray-seg + pill-detect)
    /// can't keep up, so excess frames are wasted motion-blurred work. We throttle
    /// inference to this rate in captureOutput; frames arriving sooner are dropped.
    private static let targetInferenceFPS: Double = 30
    private static let minInferenceInterval: TimeInterval = 1.0 / targetInferenceFPS

    /// Presentation timestamp (in seconds) of the last frame we ran inference on.
    /// Uses the buffer's own clock so the throttle is independent of wall-clock.
    private var lastInferenceTimestamp: TimeInterval = -1

    // MARK: - TIMER
    private var inactivityTimer: DispatchSourceTimer?

    // MARK: - PREVIEW
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    @Published private(set) var isSessionPaused = false

    // MARK: - STATE
    @Published var stableCount: Int = 0
    @Published var detections: [DetectionResult] = []
    @Published var trayDetections: [TrayResult] = []

    /// Ids of the pills currently flagged as "excess near the chute" — the surplus
    /// over the dispense target, picked nearest-the-chute. Computed ONCE per frame
    /// in the pipeline (not in the SwiftUI body, which can run several times per
    /// frame and would corrupt the picker's temporal state). The overlay just reads
    /// this set. Empty when there is no target / no excess.
    @Published var excessPillIDs: Set<UUID> = []

    /// Dispense target for the current step. The view sets this; when > 0 the
    /// excess-near-chute highlight is active and the surplus (stableCount − target)
    /// pills closest to the chute are flagged. 0 disables the feature.
    var excessTargetQuantity: Int = 0 {
        didSet {
            // A new target redefines what "excess" means — restart the sticky
            // picker so it doesn't carry highlights chosen for the old target.
            guard excessTargetQuantity != oldValue else { return }
            chuteProximity.reset()
        }
    }

    /// Stateful, frame-persistent excess-pill picker (tracks + smoothed distance +
    /// margin-based steal). Lives here so it is driven once per frame by the
    /// pipeline rather than by SwiftUI re-renders.
    private let chuteProximity = ChuteProximity()

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
            // Use 1080p VIDEO preset for high-quality preview and inference.
            // Falls back to 720p or .photo if unsupported.
            if self.session.canSetSessionPreset(.hd1920x1080) {
                self.session.sessionPreset = .hd1920x1080
            } else if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else {
                self.session.sessionPreset = .photo
            }

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

            if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
                let fps = min(max(30.0, range.minFrameRate), range.maxFrameRate)
                let duration = CMTimeMake(value: 1, timescale: Int32(fps.rounded()))
                do {
                    try device.lockForConfiguration()
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    device.unlockForConfiguration()
                } catch {
                    print("⚠️ [CAMERA] Could not lock 15 fps — \(error)")
                }
            }

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

            self.configureFrameRate(fps: 30)
        }
    }

    /// Clamps the capture device to a fixed frame rate. The requested fps is
    /// clamped to the active format's supported range, and the call is a no-op if
    /// the device or format can't honour it (zoom/exposure are untouched).
    private func configureFrameRate(fps: Double) {
        guard let device = captureDevice else { return }

        // The active format advertises the min/max frame-duration it supports.
        // Requesting a duration outside that range throws, so clamp into it.
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let range = ranges.first else { return }

        let targetFps = min(max(fps, range.minFrameRate), range.maxFrameRate)
        let duration = CMTime(value: 1, timescale: CMTimeScale(targetFps))

        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            // Intentionally silent — a failed fps cap must not break the camera.
        }
    }

    // MARK: - EXPOSURE / FOCUS LOCK

    /// Locks auto-exposure, auto-focus and auto-white-balance to their current
    /// settings so the imaging stops drifting once a stable scene (complete tray)
    /// is in view. Idempotent via `is3ALocked`; only locks the modes the device
    /// actually supports. Called from the frame delegate the first time the
    /// complete-product gate opens.
    private func lock3AIfNeeded() {
        guard !is3ALocked, let device = captureDevice else { return }

        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
            device.unlockForConfiguration()
            is3ALocked = true
        } catch {
            // Intentionally silent — a failed 3A lock must not break the camera.
        }
    }

    /// Restores continuous auto-exposure/focus/white-balance so the next counting
    /// session re-meters a fresh scene before locking again. Called on counting
    /// pause/resume (the operator may point at a different tray/lighting).
    private func unlock3A() {
        guard is3ALocked, let device = captureDevice else { is3ALocked = false; return }

        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            // Intentionally silent.
        }
        is3ALocked = false
    }

    // MARK: - BARCODE CONTROL

    func enableBarcodeScanning() {
        // Must run on sessionQueue so it executes AFTER configureSession() completes.
        // Setting the delegate before the output is added to the session silently fails.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.barcodeEnabled = true
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            // Boost to 30fps while barcode scanning is active. More frames per second
            // means more decode attempts, which is critical for low-quality or curved
            // labels (bottle, worn print) that the decoder only reads on a sharp frame.
            // The ML pipeline is NOT running during barcode scanning so the higher rate
            // does not increase CPU/ANE load.
            self.configureFrameRate(fps: 30)
            // Switch to continuous auto-focus so the camera tracks a label being moved
            // into frame. The 3A lock (used during pill counting) is NOT active here —
            // this call re-enables the continuous mode that gives the fastest sharp lock.
            self.activateBarcodeAutoFocus()
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
            self.configureFrameRate(fps: 30)
        }
    }

    /// Activates continuous auto-focus + auto-exposure for barcode scanning.
    /// Called on the session queue; safe to call even when the device is not locked.
    private func activateBarcodeAutoFocus() {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            // Interest-point focus at screen centre. For bottle / curved labels the
            // default continuous-AF tends to focus at infinity (background). Seeding the
            // focus point at (0.5, 0.5) nudges it toward the near object in frame so the
            // first sharp frame arrives faster. After the initial lock it stays continuous.
            if device.isFocusModeSupported(.continuousAutoFocus) {
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            // Intentionally silent — barcode scanning still works without focus assist.
        }
    }

    /// Triggers a one-shot auto-focus at the given point (normalised 0-1 coordinates,
    /// AVFoundation convention: top-left = (0,0)). Call from the UI when the operator
    /// taps the screen while the barcode scanner is showing, so the camera can lock
    /// focus on a curved or worn label in that area.
    func focusForBarcode(at point: CGPoint) {
        guard let device = captureDevice else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported,
                   device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // Intentionally silent.
            }
        }
    }

    func resetBarcodeScanState() {
        // Clears published values so the view's onChange does not re-fire with a
        // stale value. lockedBarcodeValue is NOT cleared here — the physical barcode
        // may still be in frame. Clearing it would re-fire the scan event on the
        // very next metadata callback. The lock releases only after the barcode has
        // been absent for barcodeLockMissThreshold consecutive frames.
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
            // Release the 3A lock before stopping so the next start() re-meters the
            // scene from scratch (lighting/tray may differ after a long pause).
            self.unlock3A()
            self.session.stopRunning()
            // Session is fully stopped — no barcodes are visible. Clear the lock
            // so the next start() begins fresh rather than blocking on a stale value.
            self.lockedBarcodeValue = nil
            self.barcodeLockMissFrames = 0
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
            self.excessPillIDs    = []
            self.recentCounts.removeAll()   // start the next session's median fresh
            self.emptyCountFrames = 0
        }
        // Restart the sticky excess picker so the next session doesn't inherit
        // highlights chosen against a stale tray/target.
        chuteProximity.reset()
        // Drop the held tray/chute detections so the next session re-acquires them
        // from scratch rather than counting against a stale tray that may no longer
        // be in frame.
        heldTrayDetections.removeAll()
        trayMissFrames = 0

        // Release the AE/AF/AWB lock on the session queue so the next counting
        // session re-meters a fresh scene (possibly a different tray/lighting)
        // before locking again.
        sessionQueue.async { [weak self] in self?.unlock3A() }
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

    /// Clears only the tray-colour sampling memory so the NEXT complete-tray frame
    /// re-publishes its colour even if the tray is physically unchanged. Tray colour
    /// is published only on CHANGE, so without this a new transaction on the same tray
    /// (continuous dispense) never re-emits — and the hazardous-tray check/marking for
    /// that transaction never runs. Call when the current transaction changes.
    func resetTrayColorSampling() {
        DispatchQueue.main.async {
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

        // ── Inference throttle: cap the pipeline to targetInferenceFPS ────────
        // The camera runs at ~30 fps but the three-model pipeline can't process
        // every frame, so we skip frames that arrive sooner than minInferenceInterval
        // after the last processed one. Uses the buffer's presentation timestamp
        // (its own clock) rather than wall-clock. lastPixelBuffer is updated above
        // regardless, so snapshots still use the freshest frame.
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if lastInferenceTimestamp >= 0,
           ts - lastInferenceTimestamp < Self.minInferenceInterval {
            return
        }
        lastInferenceTimestamp = ts

        // ── Model 1: Glove safety detection (YOLOX-Nano 320×320) ──────────────
        // Only runs when the current drug is hazardous (isGloveDetectionEnabled) AND
        // gloves haven't been confirmed yet for this session (glovesConfirmed).
        // GloveDetectionService applies its own 400 ms rate limiter internally;
        // the call returns [] immediately when the throttle is active.
        let gloves: [GloveDetectionResult] = (isGloveDetectionEnabled && !glovesConfirmed)
            ? gloveDetector.detect(pixelBuffer: pixelBuffer)
            : []

        // ── Model 2: Tray / chute segmentation (MobileNetV2-UNet 384×384) ────
        // Returns .tray and .chute regions, each carrying a per-pixel mask. Pills
        // are tested against the masks (not bounding boxes) — 1:1 with Android.
        var allTrays = trayDetector.detect(pixelBuffer: pixelBuffer)

        // ── Tray temporal hold (anti-flicker) ────────────────────────────────
        // Bridge a single dropped tray-seg frame so the overlay + pill gate don't
        // blink on a steady scene. Clears after trayHoldFrames consecutive misses
        // so the tray still disappears when you move away. Mirrors Android.
        if !allTrays.isEmpty {
            heldTrayDetections = allTrays
            trayMissFrames = 0
        } else if trayMissFrames < Self.trayHoldFrames {
            trayMissFrames += 1
            allTrays = heldTrayDetections
        } else {
            heldTrayDetections = []
        }

        // ── "Complete product" gate (mirrors Android TrayGate) ───────────────
        // A valid scene requires BOTH a tray AND a chute, and the largest tray must
        // NOT fill the frame (that would be the background surface, not a tray).
        // When closed: no pill count, no tray/chute overlay.
        let trayDets  = allTrays.filter { $0.trayClass == .tray }
        let chuteDets = allTrays.filter { $0.trayClass == .chute }

        let frameSz = pixelBuffer.size
        let frameArea = max(1, frameSz.width * frameSz.height)
        let trayCoverage = trayDets
            .map { ($0.rect.width * $0.rect.height) / frameArea }
            .max() ?? 0
        let trayFillsFrame = trayCoverage >= Self.trayMaxFrameCoverage
        let isCompleteTray = !trayDets.isEmpty && !chuteDets.isEmpty && !trayFillsFrame

        let gateOpen = isCompleteTray

        // Once a complete, stable scene (tray AND chute) is acquired, lock
        // AE/AF/AWB so the imaging stops drifting and a hand reaching in can't
        // retrigger a whole-scene re-exposure. Idempotent — only fires once per
        // session; released on counting pause/resume.
        if isCompleteTray { lock3AIfNeeded() }

        // Overlay shows tray/chute only when the scene is a complete product.
        let displayTrays = isCompleteTray ? allTrays : []

        // Tray/chute detections (with masks) used by the pill filter below.
        let effectiveTrayDets  = trayDets
        let effectiveChuteDets = chuteDets

        // First tray rect for tray-colour sampling (display/feature only).
        let trayRects = trayDets.map { $0.rect }

        // ── Tray colour sampling (hazardous-tray feature) ────────────────────
        // Continuously classify the visible tray's generic colour and publish it
        // only when the colour CHANGES (not every frame). This lets the flow react
        // to the operator swapping trays mid-session. Gated by
        // isTrayColorDetectionEnabled so it runs ONLY while the pill-count sheet is
        // showing in the dispense / stock-scan-pills flows. Runs regardless of
        // isGloveDetectionEnabled because the non-hazardous flow also needs it.
        //
        // Sample ONLY on a complete-product frame (tray AND chute detected, same gate
        // as counting/overlay). Without this, continuous dispense samples an early
        // tray-only frame — before the chute is acquired — and pins lastSampledTrayColor
        // to it. Because the colour is published only on CHANGE, the real complete-tray
        // colour then never re-emits, so the hazardous-tray capture popup is missed on
        // first entry and only reappears later when the colour happens to change again.
        if isTrayColorDetectionEnabled, isCompleteTray, let firstTrayRect = trayRects.first,
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

            // Counting GATE (mirrors Android): only count when the scene is a
            // complete product (tray AND chute, tray not filling frame). Then keep a
            // pill only if its CENTRE lands on the actual TRAY mask AND not on the
            // CHUTE mask. Using the per-pixel masks (not bounding boxes) is what
            // makes counting correct at any angle/height and keeps chute pills out —
            // the bbox of an angled tray covers non-tray area including the chute,
            // but the mask does not.
            let filtered: [DetectionResult]
            if !gateOpen {
                filtered = []
            } else {
                filtered = allPills.filter { pill in
                    let cx = pill.center.x
                    let cy = pill.center.y
                    let inTray = effectiveTrayDets.contains { $0.containsPoint(cx, cy) }
                    guard inTray else { return false }
                    let inChute = effectiveChuteDets.contains { $0.containsPoint(cx, cy) }
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
                //
                // Empty-frame hold: a momentary gate/segmentation flicker or a blurred
                // frame yields 0 pills for a frame or two even though the tray is still
                // full. Feeding those zeros straight into the median collapses it to 0
                // (the "count drops to zero" symptom). So while we have a non-zero
                // count and only a short burst of empties has elapsed, DON'T record the
                // zero — hold the median window. Once empties persist past the hold the
                // zeros flow in normally, so the count still drains to 0 when the tray
                // is genuinely emptied or removed.
                let frameCount = filtered.count
                let holdingEmpty: Bool
                if frameCount == 0 {
                    self.emptyCountFrames += 1
                    holdingEmpty = self.stableCount > 0
                        && self.emptyCountFrames <= Self.countHoldFrames
                } else {
                    self.emptyCountFrames = 0
                    holdingEmpty = false
                }

                // While holding, leave recentCounts/stableCount untouched so a brief
                // burst of empty frames can't collapse the median to 0; other overlay
                // state below still updates normally.
                if !holdingEmpty {
                    self.recentCounts.append(frameCount)
                    if self.recentCounts.count > Self.countSmoothWindow {
                        self.recentCounts.removeFirst()
                    }
                    let sortedCounts = self.recentCounts.sorted()
                    self.stableCount = sortedCounts[sortedCounts.count / 2]
                }

                self.trayDetections   = displayTrays

                // ── Excess-near-chute highlight (computed ONCE per frame) ──────
                // Number of pills to mark uses the SMOOTHED stableCount (steady);
                // WHICH pills are picked is the persistent-track picker (sticky,
                // distance-smoothed, margin-based steal) so packed pills don't
                // ping-pong. Chute/tray geometry is this frame's segmentation.
                // Disabled (empty) when no real target is set.
                if self.excessTargetQuantity > 0 {
                    let excess = max(0, self.stableCount - self.excessTargetQuantity)
                    let chute = displayTrays.first { $0.trayClass == .chute }
                    let tray  = displayTrays.first { $0.trayClass == .tray }
                    self.excessPillIDs = self.chuteProximity.nearChuteIDs(
                        pills: filtered, chute: chute, tray: tray, excess: excess)
                } else if !self.excessPillIDs.isEmpty {
                    self.excessPillIDs = []
                }

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

            // Draw badges at transformed positions. Badge size is fixed (relative to
            // image width) so every pill marker is the same size regardless of the
            // detected box, instead of scaling per-pill.
            let badgeSize = imageSize.width * 0.04
            transformedDetections.enumerated().forEach { index, detection in
                drawBadge(context: context, index: index, rect: detection.rect, badgeSize: badgeSize)
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
        rect: CGRect,
        badgeSize: CGFloat
    ) {
        let circleSize = badgeSize
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

        // Release the lock only after the locked barcode has been absent for
        // barcodeLockMissThreshold consecutive frames. A single-frame absence caused
        // by camera shake does NOT release the lock — the miss counter must reach the
        // threshold first. A different barcode appearing immediately clears the lock
        // so the new code fires without waiting.
        if let locked = lockedBarcodeValue {
            if visibleValues.contains(locked) {
                // Barcode still visible — reset miss counter, keep lock.
                barcodeLockMissFrames = 0
            } else if visibleValues.isEmpty {
                // Barcode absent this frame (possible shake dropout) — count the miss.
                barcodeLockMissFrames += 1
                if barcodeLockMissFrames >= Self.barcodeLockMissThreshold {
                    // Absent long enough — barcode was genuinely removed.
                    lockedBarcodeValue = nil
                    barcodeLockMissFrames = 0
                }
                // Lock not yet released — don't fire for any new barcode this frame.
                return
            } else {
                // A DIFFERENT barcode is now in frame — release lock immediately so
                // the new code fires right away. Same-barcode re-scan after genuine
                // removal also reaches here (locked != nil, visible has a new value).
                lockedBarcodeValue = nil
                barcodeLockMissFrames = 0
            }
        }

        // Fire a scan event only when:
        //   • there is no locked barcode (we are ready for a new scan), AND
        //   • a barcode is actually present in the current frame.
        guard lockedBarcodeValue == nil,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }

        lockedBarcodeValue = value
        barcodeLockMissFrames = 0
        // Clear first so SwiftUI's onChange fires even when the same barcode value
        // re-enters the frame after a genuine removal (onChange only fires on change).
        scannedCode = ""
        scannedCode = value
        scannedCodeType = object.type.rawValue
    }
}
