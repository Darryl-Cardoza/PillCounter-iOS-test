//
//  CameraService.swift
//  PillCounter
//
//  Optimized for performance, safety, and maintainability
//

import AVFoundation
import SwiftUI

/// Minimal lock-protected value box for the handful of CameraService fields
/// now written and read from two different serial queues (`sessionQueue` and
/// `barcodeFocusQueue`). Not a general-purpose primitive — just enough to
/// avoid a data race on plain `Bool`/`Int` flags without a full actor rewrite.
private final class SynchronizedBox<T> {
    private let lock = NSLock()
    private var storage: T

    init(_ initial: T) { storage = initial }

    var value: T {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

final class CameraService: NSObject, ObservableObject {

    // MARK: - CONSTANTS
    private let inactivityTimeout: TimeInterval = 100
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    /// Higher-priority queue for barcode metadata decode and all focus/exposure
    /// device configuration. Kept separate from `sessionQueue` (which runs the
    /// 3-model ML pipeline) so a slow ML pass on weaker hardware (iPad) never
    /// delays a metadata callback or an AF point-of-interest nudge behind it —
    /// see CameraFocusController and `captureOutput`'s [DEBUG-ipadperf] data,
    /// which showed isAdjustingFocus=true frames landing mid-100ms+ ML passes
    /// on iPad before this queue existed.
    private let barcodeFocusQueue = DispatchQueue(label: "camera.barcodeFocus.queue", qos: .userInteractive)
    /// Serializes `device.lockForConfiguration()` 3A changes between
    /// `sessionQueue` (lock3AIfNeeded/unlock3A) and `barcodeFocusQueue`
    /// (activateBarcodeAutoFocus) — `is3ALocked`'s own SynchronizedBox only
    /// protects the flag's memory, not the device call + flag write together,
    /// so without this the two queues could interleave their device
    /// configuration and leave is3ALocked disagreeing with the device's
    /// actual AF/AE mode.
    private let device3ALock = NSLock()

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
    /// Written from `barcodeFocusQueue` (enable/disable calls, metadata delegate)
    /// and read from `sessionQueue` (`captureOutput`'s ML-skip/glove-exclude
    /// checks) — lock-protected since it now crosses queues.
    private let barcodeEnabledBox = SynchronizedBox(false)
    private var barcodeEnabled: Bool {
        get { barcodeEnabledBox.value }
        set { barcodeEnabledBox.value = newValue }
    }

    // Same-barcode re-scan gate — see `BarcodeScanLock`. Presence tracking
    // (`processFrame`) runs on every metadata frame regardless of
    // `barcodeEnabled` so a barcode removed while scanning is momentarily
    // disabled (e.g. a previous scan still being processed) is never missed.
    // iPad's decoder flickers present/absent for more consecutive frames than
    // iPhone's before settling, so the default missThreshold releases the lock
    // too early there — bumped to 6 for iPad, unchanged (2) for iPhone.
    private let barcodeLock = BarcodeScanLock(
        missThreshold: UIDevice.current.userInterfaceIdiom == .pad ? 6 : 2
    )

    // MARK: - BOTTLE RESCAN (multi-bottle dispense tracking)
    // A second, independent barcode-metadata listener that stays live during
    // dispense counting (unlike `barcodeEnabled`, which is mutually exclusive
    // with `isCountingEnabled`). Publishes to its own property so a mid-count
    // rescan never collides with the primary NDC-scan path (`scannedCode`),
    // which would otherwise wrongly restart the NDC-verify flow.
    @Published var bottleRescanCode: String = ""
    /// Same cross-queue concern as `barcodeEnabled` above.
    private let bottleRescanEnabledBox = SynchronizedBox(false)
    private var bottleRescanEnabled: Bool {
        get { bottleRescanEnabledBox.value }
        set { bottleRescanEnabledBox.value = newValue }
    }
    private let bottleRescanLock = BarcodeScanLock(
        missThreshold: UIDevice.current.userInterfaceIdiom == .pad ? 6 : 2
    )

    // MARK: - IMAGE PROCESSING
    // Three-model inference pipeline running on every captured camera frame:
    //   1. GloveDetectionService  — YOLOX-Nano 320×320 (rate-limited to 400 ms after first hit)
    //   2. TrayDetectionService   — MobileNetV2-UNet segmentation 384×384 (every frame)
    //                               argmax → 384×384 label map → bounding boxes for TRAY / CHUTE
    //   3. PillDetectionService   — PP-YOLOE+s 640×640 (every frame, filtered by tray rects)
    private let detector       = PillDetectionService()
    private let trayDetector   = TrayDetectionService.shared
    private let gloveDetector  = GloveDetectionService()

    // See CameraFocusController.swift — smooth-AF disable, adjusting-focus
    // frame gate, and periodic re-arm during barcode scanning. Re-arm timer
    // runs on barcodeFocusQueue (not sessionQueue) so its 1.5s cadence never
    // depends on how long the current ML pass takes.
    private lazy var focusController = CameraFocusController(reArmQueue: barcodeFocusQueue)

    /// Reject a "tray" whose bbox covers at least this fraction of the frame — a
    /// background surface (e.g. the table) fills the frame, whereas a real tray is
    /// a bounded object inside it. Matches Android TRAY_MAX_FRAME_COVERAGE = 0.75.
    private static let trayMaxFrameCoverage: CGFloat = 0.75

    // ── Tray gate hysteresis (mirrors Android PillAnalyzer) ──────────────────
    /// The overlay box is held for at most this many incomplete frames so it
    /// clears almost immediately when the camera moves away (a longer hold left a
    /// visible ghost box).
    private static let trayHoldFrames: Int = 1

    /// The pill GATE is held longer: the segmenter drops the chute (or the tray)
    /// for a frame or two on a steady scene, and every such drop used to zero the
    /// pill result — the on-screen flicker. The gate opens on the first complete
    /// frame (tray AND chute) and closes only after this many consecutive
    /// incomplete ones; while held, the last complete tray set keeps driving the
    /// crop and the mask filter.
    private static let gateCloseFrames: Int = 6

    /// Same hold idea as gateCloseFrames, but for a pure pill-tracker miss: gate
    /// stays open (tray/chute still fine) yet the tracker reports zero confirmed
    /// pills for a frame or two (e.g. a hand transiently occludes all pills).
    /// Feeding that zero straight into CountStabilizer's median can flip the
    /// displayed count to 0 sooner than the old countHoldFrames-based hold did.
    /// While the tray last had pills and only a short burst of empties has
    /// elapsed, skip feeding the zero so the stabilizer's window isn't polluted.
    private static let pillMissHoldFrames: Int = 5

    /// Last COMPLETE tray set (tray + chute, with masks) and how many consecutive
    /// frames have failed to reproduce it. Session-queue state.
    private var heldTrayDetections: [TrayResult] = []
    private var incompleteFrames: Int = 0
    private var emptyPillFrames: Int = 0


    /// Auto-focus-on-detect presence edges (session-queue state) — see
    /// `firePulseIfNewlyVisible`. Barcode presence is read from `barcodeLock`
    /// directly at the call site rather than tracked here.
    private var lastTrayVisible = false
    private var lastChuteVisible = false

    /// True while a code object has been seen recently enough to count as
    /// "visible" — written from `barcodeFocusQueue` (metadata delegate) and
    /// read from `sessionQueue` (`captureOutput`'s ML-skip/priority-window
    /// check), so it is lock-protected. This is also the barcode ML-priority
    /// window flag: see `metadataOutput(_:didOutput:from:)`.
    private let lastBarcodeVisibleBox = SynchronizedBox(false)
    private var lastBarcodeVisible: Bool {
        get { lastBarcodeVisibleBox.value }
        set { lastBarcodeVisibleBox.value = newValue }
    }

    /// Cumulative consecutive-absent frames for the barcode presence edge fed to
    /// firePulseIfNewlyVisible, mirroring BarcodeScanLock's own flicker tolerance
    /// (its doc: "the decoder flickers present/absent almost every other frame
    /// even while the barcode sits still in view"). Without this, every flicker
    /// re-triggers a fresh one-shot focus hunt — a second "breathing" source
    /// independent of the periodic re-arm timer, and the dominant one while
    /// actively holding a barcode in frame. Only ever touched from
    /// `barcodeFocusQueue` (the metadata delegate), so it stays a plain var.
    private var barcodeAbsentFrames = 0
    private static let barcodeAbsentThreshold = 3

    // ── Tray crop for the pill model ─────────────────────────────────────────
    /// Margin added around the tray bbox per side, as a fraction of the bbox
    /// size, so a pill sitting on the rim (the deploy contract dilates the tray
    /// mask by half a pill) stays whole inside the crop.
    private static let trayCropMargin: CGFloat = 0.05
    /// A crop narrower than this (px) means the tray is too far away to count
    /// from; use the full frame rather than upscale noise.
    private static let trayCropMinSide: CGFloat = 64

    /// Deploy contract mask_dilate_pill_fraction: the tray mask is treated as
    /// dilated by this × the median pill side, so a pill whose centre sits on the
    /// segmented rim doesn't blink in and out as the boundary jitters.
    private static let maskDilatePillFraction: CGFloat = 0.5

    /// Median pill side from the previous frame's confirmed tracks, used as the
    /// floor for the crop margin so the crop (computed before this frame's
    /// pills are known) is never narrower than the mask dilation radius that
    /// will test them. 0 until pills have been seen at least once.
    private var lastMedianPillSide: CGFloat = 0

    /// Cross-frame pill state (deploy contract). The tracker decides which
    /// detections are real (enter/keep/exit); the stabilizer decides what number
    /// is displayed. Both live on the session queue.
    private let pillTracker = PillTracker()
    private let countStabilizer = CountStabilizer()

    /// Frame-to-frame camera motion, fed to the tracker so a hand-held pan does
    /// not break every pill's association at once.
    private let motionEstimator = CameraMotionEstimator()

    /// Frame counter for the throttled DEBUG pipeline log.
    private var pipelineFrameIndex: Int = 0

    /// True once AE/AF/AWB have been locked for the current counting session.
    /// The `.hd1280x720` preset already steadies the stream, but residual 3A
    /// micro-adjustments still wobble borderline pills, and — critically — a hand
    /// reaching into the tray retriggers auto-exposure for the WHOLE scene, which
    /// shifts every pill's confidence at once and makes the count chaotic during
    /// occlusion. Locking exposure/focus/white-balance once the tray is acquired
    /// freezes the imaging so only real pill changes move the count. Reset on
    /// counting pause/resume so a new scene re-meters before locking again.
    /// Written from `sessionQueue` (`lock3AIfNeeded`/`unlock3A`) and from
    /// `barcodeFocusQueue` (`activateBarcodeAutoFocus`), so lock-protected.
    private let is3ALockedBox = SynchronizedBox(false)
    private var is3ALocked: Bool {
        get { is3ALockedBox.value }
        set { is3ALockedBox.value = newValue }
    }

    private let ciContext = CIContext()
    private(set) var lastPixelBuffer: CVPixelBuffer?

    /// Target inference rate. The camera delivers frames at the device default
    /// (~30 fps), but the three-model pipeline (glove + tray-seg + pill-detect)
    /// can't keep up, so excess frames are wasted motion-blurred work. We throttle
    /// inference to this rate in captureOutput; frames arriving sooner are dropped.
    ///
    /// iPad (A14, 10th gen) measured [DEBUG-ipadperf]: tray ~50ms + pillDetect
    /// ~46-75ms + motion ~4-8ms = ~100-140ms/frame, i.e. it only ever sustains
    /// ~7-10fps regardless of what target is requested here. Asking it to chase
    /// 30fps means every single frame arrives "late" against the throttle, which
    /// buys nothing (frames never arrive faster than processing finishes anyway)
    /// and just means the gate/tracker hysteresis, tuned assuming a roughly
    /// 30fps cadence, is fed a much choppier one than it expects. Requesting a
    /// target close to what iPad can actually sustain gives the throttle/gate
    /// logic a realistic cadence to reason about instead of a permanently-missed
    /// one — this is a scheduling-target change only, NOT a cap that makes
    /// iPad artificially slower than its ~8-10fps ceiling.
    private static var targetInferenceFPS: Double {
        UIDevice.current.userInterfaceIdiom == .pad ? 12 : 30
    }
    private static var minInferenceInterval: TimeInterval { 1.0 / targetInferenceFPS }

    /// Presentation timestamp (in seconds) of the last frame we ran inference on.
    /// Uses the buffer's own clock so the throttle is independent of wall-clock.
    private var lastInferenceTimestamp: TimeInterval = -1

    // MARK: - TIMER
    private var inactivityTimer: DispatchSourceTimer?

    // MARK: - PREVIEW
    var previewLayer: AVCaptureVideoPreviewLayer?

    @Published private(set) var isSessionPaused = false

    #if DEBUG
    // MARK: - FOCUS INDICATOR (debug-only testing aid)
    /// Screen-space point of the last manual tap or auto-detect focus pulse, for
    /// UnifiedCameraView to draw a small square at. nil hides the indicator.
    @Published var focusIndicatorScreenPoint: CGPoint?
    /// True once isAdjustingFocus has gone false since the last pulse — the view
    /// uses this to flip the square from "focusing" to "focused" styling.
    @Published var isFocusIndicatorFocused = false
    /// Device-space point of the in-flight pulse, compared against
    /// isAdjustingFocus in captureOutput (sessionQueue) to know when to flip
    /// isFocusIndicatorFocused. nil once resolved. Written from
    /// barcodeFocusQueue (focusPulse) and read/cleared from sessionQueue
    /// (captureOutput), so lock-protected like the other cross-queue fields.
    private let pendingFocusIndicatorDevicePointBox = SynchronizedBox<CGPoint?>(nil)
    private var pendingFocusIndicatorDevicePoint: CGPoint? {
        get { pendingFocusIndicatorDevicePointBox.value }
        set { pendingFocusIndicatorDevicePointBox.value = newValue }
    }
    #endif

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
    /// Distinguishes "still checking" from "checked and denied" — both read isAuthorized == false.
    @Published var isPermissionCheckComplete = false
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
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            isPermissionCheckComplete = true
            if session.inputs.isEmpty { configureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    self?.isPermissionCheckComplete = true
                    if granted { self?.configureSession() }
                }
            }
        default:
            isAuthorized = false
            isPermissionCheckComplete = true
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

            do {
                try device.lockForConfiguration()
                self.focusController.applyFastFocusDefaults(on: device)
                device.unlockForConfiguration()
            } catch {
                // Intentionally silent — camera still works without this tweak.
            }
            self.reseedCenterFocusAndExposure(on: device)

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
        device3ALock.withLock {
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
                focusController.applyFastFocusDefaults(on: device)
                device.unlockForConfiguration()
                is3ALocked = true
            } catch {
                // Intentionally silent — a failed 3A lock must not break the camera.
            }
        }
    }

    /// Forces continuous AF/AE and re-seeds the point of interest to frame
    /// center. Called on every configureSession()/start(), not just once at
    /// app launch — the focus point can be left off-center by barcode re-arm
    /// nudges or a user's focusForBarcode(at:) tap, and unlock3A() restores
    /// continuous MODE but never resets the POINT. Without an unconditional
    /// reseed here, re-entering the camera screen inherits whatever point the
    /// previous session left behind, so the device sometimes settles on the
    /// wrong depth/background and stays blurry until something else nudges
    /// it back — the intermittent "sometimes blurry" behavior.
    private func reseedCenterFocusAndExposure(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            // Intentionally silent — camera still works without this tweak.
        }
    }

    /// Restores continuous auto-exposure/focus/white-balance so the next counting
    /// session re-meters a fresh scene before locking again. Called on counting
    /// pause/resume (the operator may point at a different tray/lighting).
    private func unlock3A() {
        device3ALock.withLock {
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
                focusController.applyFastFocusDefaults(on: device)
                device.unlockForConfiguration()
            } catch {
                // Intentionally silent.
            }
            is3ALocked = false
        }
    }

    // MARK: - BARCODE CONTROL

    func enableBarcodeScanning() {
        // sessionQueue first so this executes AFTER configureSession() completes —
        // setting the delegate before the output is added to the session silently
        // fails. The rest of the work (delegate queue, focus) is barcode-critical,
        // so it then hops onto barcodeFocusQueue.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.barcodeEnabled = true
            self.barcodeFocusQueue.async {
                // barcodeFocusQueue (not sessionQueue, not .main) so metadata
                // delivery and presence tracking are never delayed behind a slow
                // ML pass on the video queue — see the queue's doc comment.
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.barcodeFocusQueue)
                // Boost to 30fps while barcode scanning is active. More frames per second
                // means more decode attempts, which is critical for low-quality or curved
                // labels (bottle, worn print) that the decoder only reads on a sharp frame.
                self.configureFrameRate(fps: 30)
                // Switch to continuous auto-focus so the camera tracks a label being moved
                // into frame. The 3A lock (used during pill counting) is NOT active here —
                // this call re-enables the continuous mode that gives the fastest sharp lock.
                self.activateBarcodeAutoFocus()
            }
        }
    }

    func disableBarcodeScanning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.barcodeEnabled = false
            self.configureFrameRate(fps: 30)
        }
        barcodeFocusQueue.async { [weak self] in
            guard let self else { return }
            // Ref-counted: only actually stops once the rescan listener (if
            // active) also stops re-arming.
            self.focusController.stopReArming()
            // Intentionally preserve barcodeLock.lockedValue. If scanning is
            // re-enabled while the same physical barcode is still in frame, the
            // lock prevents it from immediately re-firing. The lock is only
            // released when the frame-presence check sees the barcode has left
            // the camera view.
            //
            // The metadata delegate is deliberately kept attached here (NOT
            // detached even when bottle-rescan listening is also off). Scanning
            // is disabled while the previous scan result is processed (DB/network
            // lookups), which can take long enough for the operator to remove and
            // re-present the same bottle. If the delegate detached here, that
            // removal would never be observed and the lock would never release —
            // the same physical barcode would then silently stop scanning until
            // force-released. Presence tracking (`barcodeLock.processFrame`) must
            // keep running across this gap; only the "fire a new scan" behavior
            // is gated by `barcodeEnabled`. The delegate is only ever detached in
            // `stop()`, when the session itself stops.
        }
    }

    /// Keeps barcode-metadata reading live during dispense counting, without
    /// touching `isCountingEnabled`/frame-rate state the ML pipeline depends on —
    /// unlike `enableBarcodeScanning()`/`disableBarcodeScanning()`, which are
    /// mutually exclusive with active pill counting. Publishes to
    /// `bottleRescanCode`, a channel independent from `scannedCode`.
    ///
    /// Dense 2D codes (GS1 DataMatrix/QR) need continuous AF/AE to get a sharp
    /// lock on a bottle label held at a different distance than the counting
    /// scene — the previous approach (leave the pill-count 3A lock in place and
    /// only pulse a one-shot autofocus once a second) too rarely landed a sharp
    /// frame for the decoder to catch. So while rescan listening is active we
    /// release the 3A lock and run continuous AF/AE, same as the primary
    /// barcode-scan path. This trades some pill-count imaging stability for a
    /// reliable rescan — acceptable because the operator physically pulls the
    /// tray out of frame to hold up the second bottle anyway.
    func enableBottleRescanListening() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.bottleRescanEnabled = true
            self.barcodeFocusQueue.async {
                // metadataOutput has a single delegate/queue for the whole
                // session — must always be barcodeFocusQueue (never
                // sessionQueue) so it agrees with enableBarcodeScanning()'s
                // registration regardless of which path set it last.
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: self.barcodeFocusQueue)
                self.activateBarcodeAutoFocus()
                print("📷 [CameraService] bottle rescan listening ENABLED")
            }
        }
    }

    func disableBottleRescanListening() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.bottleRescanEnabled = false
            print("📷 [CameraService] bottle rescan listening DISABLED")
            self.bottleRescanLock.forceRelease()
            // Re-lock 3A so the pill count settles back down once rescan listening ends.
            self.is3ALocked = false
            self.lock3AIfNeeded()
        }
        barcodeFocusQueue.async { [weak self] in
            guard let self else { return }
            // Ref-counted: only actually stops once the primary barcode scanner
            // (if active) also stops re-arming. Runs on barcodeFocusQueue since
            // the re-arm timer itself now lives there.
            self.focusController.stopReArming()
            // Metadata delegate intentionally left attached — see the comment in
            // `disableBarcodeScanning()`. It is only ever detached in `stop()`.
        }
    }

    /// Activates continuous auto-focus + auto-exposure for barcode scanning.
    /// Called on barcodeFocusQueue; safe to call even when the device is not locked.
    private func activateBarcodeAutoFocus() {
        guard let device = captureDevice else { return }
        device3ALock.withLock {
            // A prior counting session on this same CameraService instance may have
            // left is3ALocked=true. This call always puts the device back into
            // continuous mode below, so the flag must follow — otherwise the next
            // real complete-tray frame during actual counting sees is3ALocked still
            // true and lock3AIfNeeded() silently no-ops despite the device no longer
            // being locked.
            is3ALocked = false
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
                focusController.applyFastFocusDefaults(on: device)
                device.unlockForConfiguration()
            } catch {
                // Intentionally silent — barcode scanning still works without focus assist.
            }
        }

        // Continuous-AF alone can drift onto the background and stay there;
        // periodically re-center the focus point so it tracks whatever the
        // operator is actually holding up. See CameraFocusController.
        focusController.startReArming(device: device)
    }

    /// Triggers a one-shot auto-focus at the given point (normalised 0-1 coordinates,
    /// AVFoundation convention: top-left = (0,0)). Call from the UI when the operator
    /// taps the screen while the barcode scanner is showing, so the camera can lock
    /// focus on a curved or worn label in that area.
    func focusForBarcode(at point: CGPoint) {
        focusPulse(at: point)
    }

    /// One-shot autoFocus/autoExpose at a normalised device point (0-1, top-left
    /// origin). Shared by manual tap-to-focus and the auto-focus-on-detect nudge
    /// (see `firePulseIfNewlyVisible`) — both just need "point the lens here once,"
    /// the difference is only who calls it and with what point. Hops through
    /// sessionQueue before barcodeFocusQueue, same ordering as
    /// `enableBarcodeScanning()` — otherwise a tap landing at the same moment as
    /// enable can reach barcodeFocusQueue first and have its one-shot focus point
    /// immediately overwritten by `activateBarcodeAutoFocus()`'s continuous-AF reset.
    func focusPulse(at point: CGPoint) {
        guard let device = captureDevice else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.barcodeFocusQueue.async {
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
                #if DEBUG
                // Debug-only visual aid: show a small square at the tapped/pulsed
                // point, flipping to "focused" once isAdjustingFocus next reads
                // false in captureOutput. Testing tool only — never shown in release.
                self.pendingFocusIndicatorDevicePoint = point
                DispatchQueue.main.async {
                    self.focusIndicatorScreenPoint = self.previewLayer?
                        .layerPointConverted(fromCaptureDevicePoint: point)
                    self.isFocusIndicatorFocused = false
                }
                #endif
            }
        }
    }

    /// Fires one `focusPulse` on the none→visible edge of a detection type, at
    /// its own rect center (falls back to frame center if no rect given, e.g.
    /// barcode presence). Called every frame — from sessionQueue for tray/chute,
    /// from barcodeFocusQueue for barcode; `wasVisible` is updated in place so
    /// the caller's own state tracks the edge.
    private func firePulseIfNewlyVisible(_ wasVisible: inout Bool, isVisible: Bool,
                                          rect: CGRect?, frameSize: CGSize) {
        defer { wasVisible = isVisible }
        guard isVisible, !wasVisible else { return }

        let point: CGPoint
        if let rect, frameSize.width > 0, frameSize.height > 0 {
            point = CGPoint(x: rect.midX / frameSize.width, y: rect.midY / frameSize.height)
        } else {
            point = CGPoint(x: 0.5, y: 0.5)
        }
        focusPulse(at: point)
    }

    func resetBarcodeScanState() {
        // Clears published values so the view's onChange does not re-fire with a
        // stale value. barcodeLock is NOT cleared here — the physical barcode
        // may still be in frame. Clearing it would re-fire the scan event on the
        // very next metadata callback. The lock releases only once the barcode
        // has genuinely left the frame — see `BarcodeScanLock`.
        scannedCode = ""
        scannedCodeType = ""
    }

    /// Force-releases the same-barcode lock. Use when starting a new scan session where
    /// re-scanning the exact same physical barcode is expected and desired (e.g. entering
    /// open-pill mode right after scanning that NDC's sealed bottle) — otherwise the lock
    /// from the previous scan silently blocks the identical barcode from firing again
    /// until it physically leaves and re-enters the camera frame.
    func forceReleaseBarcodeLock() {
        // barcodeLock is also mutated from the metadata delegate callback on
        // barcodeFocusQueue — hop here too so forceRelease() can't race that write.
        barcodeFocusQueue.async { [weak self] in
            self?.barcodeLock.forceRelease()
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
            self.barcodeFocusQueue.async {
                // Session is fully stopped — no barcodes are visible. Clear both
                // locks so the next start() begins fresh rather than blocking on
                // a stale value, and detach the delegate + re-arm timer now that
                // frames have stopped. All barcode-focus-queue-owned state, so
                // torn down here rather than on sessionQueue.
                self.focusController.forceStopReArming()
                self.barcodeLock.forceRelease()
                self.bottleRescanLock.forceRelease()
                self.metadataOutput.setMetadataObjectsDelegate(nil, queue: .main)
            }
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
        }
        // Restart the sticky excess picker so the next session doesn't inherit
        // highlights chosen against a stale tray/target.
        chuteProximity.reset()

        // On the session queue (where the pipeline mutates them): drop the held
        // tray set, the tracks, the count latch and the motion reference so the
        // next session re-acquires everything from scratch, and release the
        // AE/AF/AWB lock so a fresh scene re-meters before locking again.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.heldTrayDetections.removeAll()
            self.incompleteFrames = 0
            self.emptyPillFrames = 0
            self.pillTracker.reset()
            self.countStabilizer.reset()
            self.lastMedianPillSide = 0
            self.motionEstimator.reset()
            self.unlock3A()
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
        resetInactivityTimer()
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

        #if DEBUG
        if pendingFocusIndicatorDevicePoint != nil,
           let device = captureDevice, !device.isAdjustingFocus {
            pendingFocusIndicatorDevicePoint = nil
            DispatchQueue.main.async { self.isFocusIndicatorFocused = true }
        }
        #endif

        // Skip ML inference on a frame captured while the device is still
        // hunting for focus/exposure — using it would feed the pipeline a
        // frame that's blurred mid-adjustment. lastPixelBuffer above is
        // still updated so snapshot capture isn't affected.
        if let device = captureDevice, !focusController.isFrameStable(for: device) {
            return
        }

        guard isCountingEnabled else { return }

        // Tray/pill overlay stays live on the barcode-scan screen at all times
        // (product requirement — used to showcase pill detection even without a
        // real barcode present), so ML is never skipped here based on barcode
        // visibility. Barcode's scheduling priority now comes from running
        // metadata decode + all focus/exposure device calls on the dedicated
        // barcodeFocusQueue (see its doc comment) instead of from starving ML
        // on this queue — that's what actually fixed the iPad contention, not
        // this per-frame skip.

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

        #if DEBUG
        // [DEBUG-ipadperf] temporary per-model timing for the iPad pipeline-latency
        // investigation. iPad-gated, DEBUG-only. Remove once root-caused.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let gloveStart = isPad ? CFAbsoluteTimeGetCurrent() : 0
        #endif

        // ── Model 1: Glove safety detection (YOLOX-Nano 320×320) ──────────────
        // Only runs when the current drug is hazardous (isGloveDetectionEnabled) AND
        // gloves haven't been confirmed yet for this session (glovesConfirmed) AND
        // barcode scanning is not active — glove safety-check has no relevance on
        // the barcode/rx-label scan screen, so it's excluded there regardless of
        // isGloveDetectionEnabled, freeing that time for tray/pill instead.
        // GloveDetectionService applies its own 400 ms rate limiter internally;
        // the call returns [] immediately when the throttle is active.
        let gloves: [GloveDetectionResult] = (isGloveDetectionEnabled && !glovesConfirmed && !barcodeEnabled)
            ? gloveDetector.detect(pixelBuffer: pixelBuffer)
            : []

        #if DEBUG
        let gloveMs = isPad ? (CFAbsoluteTimeGetCurrent() - gloveStart) * 1000 : 0
        let motionStart = isPad ? CFAbsoluteTimeGetCurrent() : 0
        #endif

        // ── Camera motion (frame-to-frame registration) ──────────────────────
        // Registers this frame against the previous one so the pill tracker can
        // move its tracks by the pan before matching (see PillTracker).
        let cameraMotion = motionEstimator.estimate(pixelBuffer)

        #if DEBUG
        let motionMs = isPad ? (CFAbsoluteTimeGetCurrent() - motionStart) * 1000 : 0
        let trayStart = isPad ? CFAbsoluteTimeGetCurrent() : 0
        #endif

        // ── Model 2: Tray / chute segmentation (MobileNetV2-UNet 384×384) ────
        // Returns .tray and .chute regions, each carrying a per-pixel mask. Pills
        // are tested against the masks (not bounding boxes) — 1:1 with Android.
        let allTrays = trayDetector.detect(pixelBuffer: pixelBuffer)

        #if DEBUG
        let trayMs = isPad ? (CFAbsoluteTimeGetCurrent() - trayStart) * 1000 : 0
        #endif

        // ── "Complete product" test (mirrors Android TrayGate) ───────────────
        // A valid scene requires BOTH a tray AND a chute, and the largest tray must
        // NOT fill the frame (that would be the background surface, not a tray).
        let trayDets  = allTrays.filter { $0.trayClass == .tray }
        let chuteDets = allTrays.filter { $0.trayClass == .chute }

        let frameSz = pixelBuffer.size
        let frameArea = max(1, frameSz.width * frameSz.height)
        let trayCoverage = trayDets
            .map { ($0.rect.width * $0.rect.height) / frameArea }
            .max() ?? 0
        let trayFillsFrame = trayCoverage >= Self.trayMaxFrameCoverage
        let isCompleteTray = !trayDets.isEmpty && !chuteDets.isEmpty && !trayFillsFrame

        // ── Gate hysteresis ──────────────────────────────────────────────────
        // Open on the first complete frame, close only after gateCloseFrames
        // consecutive incomplete ones. gateTrays drives the crop and the mask
        // filter — this frame's set when it is complete, otherwise the last
        // complete one. The overlay box is held for the shorter trayHoldFrames.
        if isCompleteTray {
            heldTrayDetections = allTrays
            incompleteFrames = 0
        } else {
            incompleteFrames += 1
        }
        let gateOpen = !heldTrayDetections.isEmpty && incompleteFrames <= Self.gateCloseFrames
        if !gateOpen { heldTrayDetections.removeAll() }
        let gateTrays     = heldTrayDetections
        let gateTrayDets  = gateTrays.filter { $0.trayClass == .tray }
        let gateChuteDets = gateTrays.filter { $0.trayClass == .chute }
        let displayTrays  = (gateOpen && incompleteFrames <= Self.trayHoldFrames) ? gateTrays : []

        // Auto-focus-on-detect: pulse once on the none→visible edge for tray/chute,
        // at that detection's own center — not every frame it stays visible, which
        // would spam lockForConfiguration. Keyed off the GATE's held sets (already
        // tolerant of a dropped segmentation frame via gateCloseFrames), not the
        // raw per-frame trayDets/chuteDets — the segmenter drops the chute for a
        // frame or two even on a steady scene (see gate hysteresis comment above),
        // and pulsing on every one of those flickers was a second source of the
        // camera "breathing" on an otherwise-static scene. Barcode's edge is
        // handled separately in the metadata delegate (it has its own presence
        // signal already).
        firePulseIfNewlyVisible(&lastTrayVisible, isVisible: !gateTrayDets.isEmpty,
                                 rect: gateTrayDets.first?.rect, frameSize: pixelBuffer.size)
        firePulseIfNewlyVisible(&lastChuteVisible, isVisible: !gateChuteDets.isEmpty,
                                 rect: gateChuteDets.first?.rect, frameSize: pixelBuffer.size)

        // Once a complete, stable scene (tray AND chute) is acquired, lock
        // AE/AF/AWB so the imaging stops drifting and a hand reaching in can't
        // retrigger a whole-scene re-exposure. Idempotent — only fires once per
        // session; released on counting pause/resume.
        //
        // NEVER while barcode scanning is live (barcodeEnabled/bottleRescanEnabled):
        // the ML pipeline can see a "complete tray" (tray+chute) even on the
        // rx_label/barcode screens where it runs for live detection, and locking
        // 3A there freezes focus at whatever depth it locked — the operator can
        // never get a sharp lock on a bottle/label held closer afterward. Barcode
        // screens rely on activateBarcodeAutoFocus()'s continuous AF instead.
        if isCompleteTray, !barcodeEnabled, !bottleRescanEnabled {
            lock3AIfNeeded()
        }

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

        // ── Model 3: Pill detection (PP-YOLOE+s 640×640) on the TRAY CROP ────
        // With the gate open only the tray's bounding box (plus a small margin)
        // goes to the pill model: the chute and everything else in the frame are
        // cropped away, and the pills fill the 640 canvas at the scale the model
        // was trained on (deploy contract: "feed the detector the tray crop, not
        // the whole frame"). Otherwise the full frame is used.
        let cropRect = gateOpen
            ? Self.trayCropRegion(gateTrayDets, frameSize: frameSz,
                                   minInset: Self.maskDilatePillFraction * lastMedianPillSide)
            : nil
        let cameraShift = cameraMotion.map { CGVector(dx: $0.dx, dy: $0.dy) }

        #if DEBUG
        let pillDetectStart = isPad ? CFAbsoluteTimeGetCurrent() : 0
        #endif

        detector.detect(pixelBuffer: pixelBuffer, cropRect: cropRect) { [weak self] afterNms, _ in
            guard let self else { return }

            #if DEBUG
            let pillDetectMs = isPad ? (CFAbsoluteTimeGetCurrent() - pillDetectStart) * 1000 : 0
            #endif

            // Tracker (deploy contract): enter 0.50 on two consecutive frames, keep
            // at 0.35, exit after three misses, one pill per track, camera motion
            // compensated. Runs every frame so pills confirm while the gate opens.
            let confirmed = self.pillTracker.update(afterNms, cameraShift: cameraShift)
            if !confirmed.isEmpty { self.lastMedianPillSide = Self.medianSide(confirmed) }

            // Counting GATE: only count while the (hysteretic) gate is open. Then
            // keep a pill only if its CENTRE lands on the TRAY mask dilated by half
            // a pill side, AND not on the CHUTE mask. Using the per-pixel masks (not
            // bounding boxes) is what makes counting correct at any angle/height
            // and keeps chute pills out.
            let filtered: [DetectionResult]
            var visibleOnTray = 0
            if !gateOpen {
                filtered = []
            } else {
                let dilate = Self.maskDilatePillFraction * Self.medianSide(confirmed)
                let onTray: (DetectionResult) -> Bool = { pill in
                    let c = pill.center
                    return gateTrayDets.contains { $0.containsPointWithin(c.x, c.y, radius: dilate) }
                        && !gateChuteDets.contains { $0.containsPoint(c.x, c.y) }
                }
                filtered = confirmed.filter(onTray)
                // For debug telemetry only: what the detector actually sees on the
                // tray this frame. Not used to cap the count — a track legitimately
                // coasting through occlusion has no detection under it by design.
                visibleOnTray = afterNms.filter { $0.confidence >= PillTracker.keepScore && onTray($0) }.count
            }

            // Displayed count is smoothed twice: median over the recent window,
            // then a latch requiring consecutive agreement. Per-frame count =
            // confirmed tracks on the tray. PillTracker already owns hysteresis
            // (enter/keep/exit), so a coasting track is trusted, not clamped down
            // to this frame's raw visible count.
            //
            // Hold a pure pill-miss (filtered.count == 0 while stableCount > 0)
            // for pillMissHoldFrames before letting the zero reach the median —
            // see pillMissHoldFrames doc comment.
            let holdingEmptyPills: Bool
            if filtered.isEmpty {
                self.emptyPillFrames += 1
                holdingEmptyPills = self.stableCount > 0
                    && self.emptyPillFrames <= Self.pillMissHoldFrames
            } else {
                self.emptyPillFrames = 0
                holdingEmptyPills = false
            }
            let counted = holdingEmptyPills
                ? self.stableCount
                : self.countStabilizer.update(rawCount: filtered.count)

            #if DEBUG
            self.pipelineFrameIndex += 1
            if self.pipelineFrameIndex % 10 == 0 {
                let crop = cropRect.map { "\(Int($0.width))x\(Int($0.height))" } ?? "full"
                let motion = cameraMotion.map { String(format: "%.1f,%.1f", $0.dx, $0.dy) } ?? "n/a"
                print("🧮 [PIPELINE] gateOpen=\(gateOpen) incomplete=\(self.incompleteFrames) "
                      + "pillInput=\(crop) afterNMS=\(afterNms.count) tracked=\(filtered.count) "
                      + "visible=\(visibleOnTray) counted=\(counted) motion=\(motion)")
            }
            if isPad {
                let af = self.captureDevice?.isAdjustingFocus ?? false
                let ae = self.captureDevice?.isAdjustingExposure ?? false
                print("⏱️ [DEBUG-ipadperf] glove=\(String(format: "%.1f", gloveMs))ms "
                      + "motion=\(String(format: "%.1f", motionMs))ms "
                      + "tray=\(String(format: "%.1f", trayMs))ms "
                      + "pillDetect=\(String(format: "%.1f", pillDetectMs))ms "
                      + "total=\(String(format: "%.1f", gloveMs + motionMs + trayMs + pillDetectMs))ms "
                      + "isAdjustingFocus=\(af) isAdjustingExposure=\(ae)")
            }
            #endif

            let hazardous        = gloves.contains { $0.isHazardous }
            // A glove box existing somewhere in frame isn't enough — a bare hand can
            // also trigger a spurious low-confidence glove box elsewhere (clutter,
            // background) while the hand itself is correctly flagged noGlove. Only
            // confirm safe when gloves are detected AND no bare-hand box is present
            // in the same frame.
            let glovesNowSafe    = !self.glovesConfirmed && !hazardous
                && gloves.contains { $0.gloveClass == .glove }

            DispatchQueue.main.async {
                guard self.isCountingEnabled else { return }

                // Markers (dots) are the confirmed tracks on the tray this frame.
                self.detections = filtered

                // The count is the tracker + stabilizer output computed above.
                self.stableCount = counted

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

// MARK: - PIPELINE GEOMETRY HELPERS
extension CameraService {

    /// The frame region handed to the pill model: the TRAY bounding box (the
    /// chute is a separate class and lies outside it), grown by `trayCropMargin`
    /// per side and clamped to the frame. Nil when there is no tray or the crop is
    /// too small to be worth upscaling.
    fileprivate static func trayCropRegion(_ trays: [TrayResult], frameSize: CGSize, minInset: CGFloat = 0) -> CGRect? {
        guard let tray = trays.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })
        else { return nil }
        // The mask test later dilates the tray by maskDilatePillFraction × pill
        // side, so the crop must reach at least as far or a rim pill is clipped
        // before the mask ever sees it — the percentage margin alone can't
        // guarantee that for a small tray with large pills.
        let mx = max(tray.rect.width * trayCropMargin, minInset)
        let my = max(tray.rect.height * trayCropMargin, minInset)
        let frame = CGRect(origin: .zero, size: frameSize)
        let region = tray.rect.insetBy(dx: -mx, dy: -my).integral.intersection(frame)
        guard !region.isNull, region.width >= trayCropMinSide, region.height >= trayCropMinSide
        else { return nil }
        return region
    }

    /// Median of sqrt(w·h) over `dets`; 0 when there are none.
    fileprivate static func medianSide(_ dets: [DetectionResult]) -> CGFloat {
        dets.map { ($0.rect.width * $0.rect.height).squareRoot() }.median()
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
                originalFrameSize: detection.originalFrameSize,
                isCoasting: detection.isCoasting
            )
        }

        // 3. Renderz
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { ctx in
            let context = ctx.cgContext

            // Draw oriented image (no flip needed — CIImage already handled it)
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: imageSize))

            // Badge size scales with each pill's own detected box so it never
            // covers pills bigger/smaller than average, clamped to stay legible.
            let minBadgeSize = imageSize.width * 0.012
            let maxBadgeSize = imageSize.width * 0.08
            transformedDetections.enumerated().forEach { index, detection in
                let pillDiameter = min(detection.rect.width, detection.rect.height)
                let badgeSize = min(max(pillDiameter * 0.55, minBadgeSize), maxBadgeSize)
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
        context.setLineWidth(max(1, circleSize * 0.08))
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
        // Collect all currently-visible barcode/QR objects this frame.
        let codeObjects = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        let visibleValues = codeObjects.compactMap { $0.stringValue }

        // Prefer a candidate that ISN'T the value already locked. With several
        // codes crowded into one frame (e.g. a shelf of bottles), always taking
        // metadataObjects.first would keep re-offering the same already-scanned
        // code and starve the others — the operator had to physically move the
        // camera to change what AVFoundation reports first. Skipping the locked
        // value lets the next unscanned code in frame become the candidate as
        // soon as the current one's scan finishes processing, no movement needed.
        let object = codeObjects.first { $0.stringValue != barcodeLock.lockedValue }
            ?? codeObjects.first
        let candidateValue = object?.stringValue

        // Presence tracking runs unconditionally — NOT gated by barcodeEnabled/
        // bottleRescanEnabled. If it paused while scanning is disabled (e.g. a
        // previous scan result still being processed), a barcode removed and
        // re-presented during that gap would never be observed and its lock
        // would never release. See `BarcodeScanLock`.
        let barcodeFired = barcodeLock.processFrame(visibleValues: visibleValues, candidateValue: candidateValue)
        let rescanFired = bottleRescanLock.processFrame(visibleValues: visibleValues, candidateValue: candidateValue)

        // Auto-focus-on-detect: pulse once on the none→visible edge, at the
        // code's own bounds center. AVMetadataMachineReadableCodeObject.bounds
        // is already normalised device coordinates, so no conversion needed.
        // Debounced against decoder flicker (see barcodeAbsentFrames doc) — a
        // single absent frame doesn't count as "gone" until barcodeAbsentThreshold
        // consecutive misses, so a steadily-held barcode doesn't re-trigger the
        // edge (and a fresh focus hunt) on every other flickered frame.
        if codeObjects.isEmpty {
            barcodeAbsentFrames += 1
        } else {
            barcodeAbsentFrames = 0
        }
        let debouncedBarcodeVisible = codeObjects.isEmpty
            ? barcodeAbsentFrames < Self.barcodeAbsentThreshold && lastBarcodeVisible
            : true
        firePulseIfNewlyVisible(&lastBarcodeVisible, isVisible: debouncedBarcodeVisible,
                                 rect: object?.bounds, frameSize: CGSize(width: 1, height: 1))

        // The delegate runs on barcodeFocusQueue (not sessionQueue, not .main)
        // so presence tracking above is never starved by a slow ML pass on the
        // video queue, nor by MainActor work — @Published writes still must
        // land on main. lastBarcodeVisible / barcodeEnabled reads elsewhere
        // (sessionQueue's captureOutput) go through the lock-protected boxes.
        if barcodeEnabled, let value = barcodeFired, let object {
            let codeType = object.type.rawValue
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Clear first so SwiftUI's onChange fires even when the same barcode value
                // re-enters the frame after a genuine removal (onChange only fires on change).
                self.scannedCode = ""
                self.scannedCode = value
                self.scannedCodeType = codeType
            }
        }
        if bottleRescanEnabled, let value = rescanFired {
            print("📷 [CameraService] bottle rescan metadata decoded: \(value)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.bottleRescanCode = ""
                self.bottleRescanCode = value
            }
        }
    }
}
