//
//  FaceEnrollmentViewModel.swift
//  PillCounter
//
//  Guided-pose enrollment: 5 steps (center, turn left, turn right, chin up,
//  center again — see EnrollmentPoseStep). Owns no Core Data access directly
//  — all persistence goes through FaceRecognitionRepository (spec section 11).
//
//  Structural fixes for the "enrollment never completes" failure mode
//  (see research notes): each step runs a best-of-window capture instead of
//  hard-rejecting every imperfect frame. There is no global or per-step
//  timeout — a step with no pose-matched candidate yet waits indefinitely
//  rather than skipping, so a mismatched-pose embedding can never be stored.
//  The only exits from a stuck step are Cancel or backgrounding.
//
//  The hot per-frame path (`handleFrame` and everything it calls) runs
//  `nonisolated` on the camera session queue and only hops to the main actor
//  to publish `state`, so ML inference never blocks SwiftUI and no two
//  frames are ever processed concurrently (spec section 14).
//
//  No FaceUserEntity row is created until enrollment actually succeeds —
//  `finishEnrollment()` is the only place that persists one. Before that,
//  `pendingUserId` is a purely local identifier. This closes a stuck-lock
//  bug: previously the row was created at the very start of enrollment, so
//  backgrounding mid-capture (which SwiftUI's `onDisappear` does NOT fire
//  for) left a durable, embedding-less "enrolled" user that satisfied
//  FaceSessionManager's lock gate but could never be matched to unlock.
//

import Foundation
import CoreVideo
import Combine
import UIKit

@MainActor
final class FaceEnrollmentViewModel: ObservableObject {

    // MARK: - Published UI state

    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var state: EnrollmentState = .idle
    /// Coarse yaw estimate of the current best candidate, drives the
    /// on-screen oval nudge (e.g. "turn a bit more").
    @Published private(set) var liveYawDegrees: Float = 0
    /// Companion to `liveYawDegrees` — together they drive the directional
    /// arrow in EnrollmentPoseGuidance.
    @Published private(set) var livePitchDegrees: Float = 0
    /// Whether the current frame yielded a usable face. False leaves every
    /// arrow unlit rather than pointing from a stale pose estimate — the row
    /// itself stays on screen either way.
    @Published private(set) var hasLiveFace: Bool = false
    /// Reason the most recent frame was rejected by FaceQualityChecker, nil
    /// when the last frame was acceptable or had no usable face. Drives an
    /// override of the step's default instruction text (e.g. "center your
    /// face") for reasons the user can act on.
    @Published private(set) var liveRejectionReason: FaceQualityRejectionReason?
    /// Steps whose sample has already been captured — once a direction lands
    /// here, EnrollmentPoseGuidance freezes that arrow to a done mark instead
    /// of following live pose. Session-scoped; reset on every new attempt.
    @Published private(set) var completedSteps: Set<EnrollmentPoseStep> = []
    /// Non-nil while the "this face is already enrolled" confirmation is on
    /// screen. The capture pipeline is paused for exactly as long as this is
    /// non-nil — answering the prompt is the only thing that resumes it.
    @Published private(set) var duplicateMatch: DuplicateFaceMatch?
    /// True while the "keep the same person in frame" notice is being held
    /// after a continuity restart. `instructionText` prefers it while set.
    @Published private(set) var isShowingTrackBrokenNotice = false
    /// Supersession token so a second break during a hold cancels the first
    /// one's pending clear rather than cutting the new notice short.
    private var trackBrokenNoticeToken: UInt64 = 0

    private let poseSteps = EnrollmentPoseStep.allCases

    // MARK: - Dependencies

    private let repository: FaceRecognitionRepositoryProtocol
    private let detector: YuNetDetectorService
    private let qualityChecker: FaceQualityChecker
    let cameraService: FaceCameraService
    /// Keeps the nested camera service's @Published changes flowing out of
    /// this view model — see the note in `init`.
    private var cameraServiceSubscription: AnyCancellable?

    // MARK: - Tuning (see research notes — grounded, not guessed, defaults)

    /// Minimum spacing between processed frames — keeps this off the full
    /// camera frame rate, and is what makes every frame-count constant below
    /// mean a stable amount of time. Matches Android's
    /// AutoCaptureController.MIN_FRAME_INTERVAL_MS and the auth path's
    /// FaceRecognitionConfig.minInferenceIntervalSeconds.
    private let minFrameIntervalSeconds: TimeInterval = 0.15
    /// How long to keep sampling for a better frame AFTER the first usable
    /// candidate, before committing the best one. Each improvement pushes the
    /// deadline out again. Android's AutoCaptureController.SETTLE_WINDOW_MS.
    ///
    /// Note this is measured from the first candidate, not from the start of
    /// the step: a step with no candidate yet has no deadline at all and
    /// simply keeps sampling. That is what guarantees no pose is ever skipped.
    private let settleWindowSeconds: TimeInterval = 0.9
    /// How long a user may struggle with one pose before the hint gets firmer.
    /// Android's AutoCaptureController.ESCALATE_AFTER_MS.
    private let escalateAfterSeconds: TimeInterval = 8.0
    /// How long the "keep the same person in frame" notice is held before the
    /// restarted step's own copy may replace it — without this the restarted
    /// `.center` guidance lands ~150ms later and overwrites it before anyone
    /// could read or hear it. Android's TRACK_BROKEN_NOTICE_MS.
    private let trackBrokenNoticeSeconds: TimeInterval = 2.0
    /// Acceptable face-box width range relative to the `.center` step's
    /// anchor box — same person at the same distance from the camera keeps
    /// a roughly stable box size. Deliberately wide: a turned head's box
    /// does narrow somewhat as a side profile, and that's a normal pose
    /// change, not a person swap.
    private let anchorBoxWidthRatio: ClosedRange<Float> = 0.7...1.4
    /// Max fraction of frame width/height the box's center may drift from
    /// the anchor's — catches a face that appeared somewhere else entirely
    /// (a genuine swap-in) while tolerating the sideways drift a normal
    /// turn produces. An earlier version compared frame-to-frame box IoU
    /// instead, which broke on every legitimate head turn — turning IS a
    /// box jump, so IoU couldn't tell "moved" from "different person."
    /// Anchoring to one fixed reference (center's box) and checking
    /// size+position tolerance instead of overlap fixes that.
    private let anchorBoxCenterDriftRatio: Float = 0.35
    /// Consecutive anchor-mismatch frames tolerated before failing — absorbs
    /// one noisy/blurry/motion-glitch frame without failing the same person,
    /// while a genuinely different face keeps mismatching frame after frame
    /// and still gets caught quickly. Deliberately much smaller than
    /// the continuity gate's absence grace: a face IS present here, just not matching, which is
    /// a stronger signal than mere absence and shouldn't get the same long
    /// grace.
    private let anchorMismatchGraceFrames = 3

    // MARK: - Capture-pipeline state (camera-queue-only, see header)

    private nonisolated(unsafe) var isProcessing = false
    // `isCapturingFrames`, `pendingUserId`, `duplicatePausedAt` and
    // `stepStartedAt` are internal rather than private so the duplicate-prompt
    // tests can drive runDuplicateCheck/continueAfterDuplicate without a
    // camera — a real `.center` capture needs a device. Nothing outside the
    // test target touches them.
    nonisolated(unsafe) var isCapturingFrames = false
    /// Local identifier for the in-progress attempt only — no FaceUserEntity
    /// row exists under this id until `finishEnrollment()` persists one.
    /// Deferring persistence to success is what makes an orphaned,
    /// embedding-less user row structurally impossible (see class header).
    nonisolated(unsafe) var pendingUserId: String?
    private nonisolated(unsafe) var collectedEmbeddings: [FaceEmbedding] = []
    private nonisolated(unsafe) var collectedSteps: [EnrollmentPoseStep] = []
    /// Snapshot of the trimmed name taken at `startEnrollment()` — the hot
    /// path is `nonisolated` and can't read the `@MainActor` `firstName`/
    /// `lastName` published properties directly from `finishEnrollment()`.
    private nonisolated(unsafe) var pendingFirstName = ""
    private nonisolated(unsafe) var pendingLastName = ""
    /// Bounding box captured once, at the moment `.center` succeeds — the
    /// fixed reference every later frame's box is checked against (size +
    /// position tolerance, not frame-to-frame overlap). nil until `.center`
    /// is captured, during which every frame passes the check
    /// unconditionally (nothing to anchor against yet). Persists ACROSS
    /// pose steps deliberately — identity continuity must hold for the
    /// whole enrollment, not reset per step like the pose state below does.
    private nonisolated(unsafe) var centerAnchorBox: CGRect?
    /// Consecutive frames where a face IS present but doesn't match
    /// centerAnchorBox — see anchorMismatchGraceFrames's declaration.
    private nonisolated(unsafe) var consecutiveAnchorMismatchFrames = 0
    private var backgroundObserver: NSObjectProtocol?

    /// Rolling frame-to-frame identity check. Second layer alongside
    /// `centerAnchorBox`: the anchor bounds total drift from where the centre
    /// pose was taken, this catches the jump-cut of a different person taking
    /// over. Armed at the `.center` commit.
    private nonisolated(unsafe) var trackGate = FaceTrackContinuityGate()
    /// Consecutive-passing-frame counter for the current step's pose.
    private nonisolated(unsafe) var poseStability = PoseStabilityTracker()

    /// Monotonic instant capture was paused for the duplicate prompt, nil when
    /// not paused. Doubles as the re-entrancy guard for the check itself. On
    /// resume the step clock is shifted forward by the elapsed pause, so
    /// reading a modal the user can't dismiss quickly doesn't count against
    /// the hint-escalation timer. Internal for tests — see the note above
    /// `isCapturingFrames`.
    nonisolated(unsafe) var duplicatePausedAt: TimeInterval?

    private nonisolated(unsafe) var currentStepIndex = 0
    /// When the current step began — drives hint escalation only, now that
    /// there is no step timeout. Internal for tests, see the note above
    /// `isCapturingFrames`.
    nonisolated(unsafe) var stepStartedAt: TimeInterval = 0
    private nonisolated(unsafe) var lastProcessedAt: TimeInterval = 0
    /// When the current step must commit its best candidate — set the moment a
    /// first candidate exists, pushed out by each better one. nil means no
    /// candidate yet, and therefore no deadline: the step waits indefinitely
    /// rather than skipping, which is what guarantees every pose is captured.
    private nonisolated(unsafe) var settleDeadline: TimeInterval?
    /// EMA-smoothed yaw/pitch, compared against the step's target range
    /// instead of the raw per-frame estimate — FaceQualityChecker's yaw/pitch
    /// proxies are explicitly documented as noisy single-frame readings, and
    /// the stability streak resets to 0 on any single miss, so unsmoothed
    /// jitter was breaking it independent of how fast or slow the user
    /// actually turned. nil until the first usable frame of a step, so that
    /// frame seeds the average instead of blending against 0.
    private nonisolated(unsafe) var smoothedYawDegrees: Float?
    private nonisolated(unsafe) var smoothedPitchDegrees: Float?
    /// Weight given to each new frame in the EMA above — low enough to
    /// absorb per-frame landmark jitter, high enough to still track a
    /// deliberate head turn within the step's time budget.
    private let poseSmoothingAlpha: Float = 0.3
    /// Best candidate seen so far THAT ALSO SATISFIED the step's pose range
    /// and held it for `PoseStabilityTracker.requiredStableFrames`. Committed
    /// at `settleDeadline`. A step with none of these simply keeps sampling —
    /// it is never skipped, so a mismatched-pose embedding (e.g. a centred
    /// frame recorded for "turn left") can never be stored.
    private nonisolated(unsafe) var bestPoseMatchedCandidate: (pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, quality: FaceQualityResult)?
    /// Thumbnail rendered from the `.center` step's accepted frame, persisted
    /// once enrollment succeeds and shown in the Quick Access Users row. Held
    /// as a rendered UIImage rather than the raw CVPixelBuffer because the
    /// buffer belongs to the capture session's pool and is recycled as soon as
    /// the frame callback returns.
    private nonisolated(unsafe) var frontalAvatar: UIImage?

    init(
        repository: FaceRecognitionRepositoryProtocol = FaceRecognitionRepository.shared,
        detector: YuNetDetectorService = .shared,
        qualityChecker: FaceQualityChecker = .shared,
        cameraService: FaceCameraService = FaceCameraService()
    ) {
        self.repository = repository
        self.detector = detector
        self.qualityChecker = qualityChecker
        self.cameraService = cameraService

        // A nested ObservableObject does not propagate its own changes, so the
        // view (which reads the camera through this view model rather than
        // observing it directly) would not re-render when `cameraPosition` or
        // `currentCameraOrientation` changes — leaving the preview's connection
        // un-rotated after a flip. Forward them explicitly.
        cameraServiceSubscription = cameraService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }

        // SwiftUI's `onDisappear` (the view's other cancel path) does NOT
        // fire when the app is merely backgrounded — the enrollment screen
        // stays mounted underneath the lock overlay window. Without this,
        // an in-progress capture kept running (and, before this fix's
        // deferred-persist change, left a durable orphan user row) every
        // time QA backgrounded the app mid-enrollment.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancelEnrollment() }
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    // MARK: - Name validation (spec section 1)

    var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedName: String {
        "\(trimmedFirstName) \(trimmedLastName)"
    }

    var isNameValid: Bool {
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty
    }

    func validateNameBeforeStarting() -> Bool {
        guard isNameValid else { return false }
        return !repository.isNameTaken(trimmedName)
    }

    // MARK: - Lifecycle

    func startEnrollment() {
        guard isNameValid else { return }
        guard validateNameBeforeStarting() else {
            state = .failed(.storageError)
            return
        }

        collectedEmbeddings = []
        collectedSteps = []
        currentStepIndex = 0
        bestPoseMatchedCandidate = nil
        settleDeadline = nil
        frontalAvatar = nil
        smoothedYawDegrees = nil
        smoothedPitchDegrees = nil
        centerAnchorBox = nil
        consecutiveAnchorMismatchFrames = 0
        lastProcessedAt = 0
        poseStability.reset()
        trackGate.reset()
        duplicateMatch = nil
        duplicatePausedAt = nil
        isShowingTrackBrokenNotice = false
        resetQualityThresholds(step: .center)
        hasLiveFace = false
        liveYawDegrees = 0
        livePitchDegrees = 0
        liveRejectionReason = nil
        completedSteps = []
        state = .preparing

        // Not yet persisted — see class header. registerUser() only runs in
        // finishEnrollment() once capture actually succeeds.
        let userId = UUID().uuidString
        pendingUserId = userId
        pendingFirstName = trimmedFirstName
        pendingLastName = trimmedLastName

        stepStartedAt = Self.monotonicNow()

        cameraService.onFrame = { [weak self] pixelBuffer in
            self?.handleFrame(pixelBuffer)
        }
        isCapturingFrames = true
        cameraService.start()
        publishAwaitingPose()
        AppLogger.shared.info("Enrollment: started for user \(userId), \(poseSteps.count) pose steps")
    }

    func cancelEnrollment() {
        isCapturingFrames = false
        cameraService.stop()
        cameraService.onFrame = nil
        // No DB cleanup needed — nothing is persisted until finishEnrollment()
        // succeeds, so an in-progress attempt never has a row to delete.
        AppLogger.shared.info("Enrollment: cancelled, had \(collectedEmbeddings.count) embedding(s) — nothing persisted")
        pendingUserId = nil
        collectedEmbeddings = []
        collectedSteps = []
        bestPoseMatchedCandidate = nil
        frontalAvatar = nil
        hasLiveFace = false
        liveRejectionReason = nil
        completedSteps = []
        duplicateMatch = nil
        duplicatePausedAt = nil
        isShowingTrackBrokenNotice = false
        settleDeadline = nil
        trackGate.reset()
        poseStability.reset()
        state = .idle
    }

    func retry() {
        // Nothing was ever persisted for the failed attempt (see class
        // header) — startEnrollment() re-registering the same name can't
        // collide with a leftover row, so retry is a pure in-memory reset.
        startEnrollment()
    }

    /// Resets to a clean `.idle` after a *successful* enrollment so the UI can
    /// run the flow again for a different person. Unlike `cancelEnrollment`
    /// this must not delete the user just enrolled — the samples are already
    /// persisted and `pendingUserId` still points at them.
    func prepareForNextUser() {
        isCapturingFrames = false
        cameraService.stop()
        cameraService.onFrame = nil
        pendingUserId = nil
        collectedEmbeddings = []
        collectedSteps = []
        bestPoseMatchedCandidate = nil
        frontalAvatar = nil
        hasLiveFace = false
        liveRejectionReason = nil
        completedSteps = []
        duplicateMatch = nil
        duplicatePausedAt = nil
        isShowingTrackBrokenNotice = false
        settleDeadline = nil
        trackGate.reset()
        poseStability.reset()
        firstName = ""
        lastName = ""
        state = .idle
    }

    // MARK: - Frame pipeline

    private nonisolated func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        guard !isProcessing else { return }
        guard isCapturingFrames else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Rate-limit independent of camera FPS. Everything below counts frames
        // (pose stability, track gap) and those counts only mean a stable
        // amount of time because of this.
        let now = Self.monotonicNow()
        guard now - lastProcessedAt >= minFrameIntervalSeconds else { return }
        lastProcessedAt = now

        let detections = detector.detect(pixelBuffer: pixelBuffer)
        let detectedBox: CGRect? = detections.count == 1 ? detections[0].boundingBox : nil

        // Track continuity, on detection alone and BEFORE every quality gate —
        // a blurry face is still the same face, and failing quality must not
        // look like a person swap. Getting this order wrong is what made an
        // earlier iOS attempt at frame-to-frame IoU "break on every legitimate
        // head turn": a turn is exactly when quality fails most, so the
        // reference box went stale and the overlap collapsed.
        trackGate.observe(detectedBox)
        if trackGate.isBroken {
            AppLogger.shared.warn("Enrollment: track lost — restarting the scan from .center")
            restartForBrokenTrack()
            return
        }

        guard detections.count == 1 else {
            AppLogger.shared.debug("Enrollment: frame skipped — \(detections.count) face(s) detected")
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = nil
            }
            poseStability.record(posePassed: false)
            evaluateStepDeadlines(at: now)
            return
        }

        let step = poseSteps[currentStepIndex]

        // Second identity layer, alongside the rolling gate above: the anchor
        // bounds total drift from where `.center` was taken, which a rolling
        // frame-to-frame comparison permits without limit. No-op until
        // `.center` is captured — nothing to anchor against yet.
        let box = detections[0].boundingBox
        if let anchor = centerAnchorBox, !boxMatchesAnchor(box, anchor: anchor, frameSize: detections[0].frameSize) {
            consecutiveAnchorMismatchFrames += 1
            if consecutiveAnchorMismatchFrames > anchorMismatchGraceFrames {
                AppLogger.shared.warn("Enrollment: track lost — box mismatched the center-step anchor for \(consecutiveAnchorMismatchFrames) frames")
                restartForBrokenTrack()
                return
            }
            // Within grace — discard this frame like any other rejected-but-
            // not-fatal one rather than treating it as a good capture
            // candidate.
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = nil
            }
            poseStability.record(posePassed: false)
            evaluateStepDeadlines(at: now)
            return
        }
        consecutiveAnchorMismatchFrames = 0

        let quality = qualityChecker.check(detection: detections[0], pixelBuffer: pixelBuffer)
        guard quality.isAcceptable else {
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = quality.reason
            }
            poseStability.record(posePassed: false)
            evaluateStepDeadlines(at: now)
            return
        }

        // Strict completeness gate — runs after the existing box/sharpness
        // check, before this frame is eligible as a capture candidate. See
        // FaceCaptureValidator.swift for what this catches and why. `step`
        // lets it skip the yaw-ratio check for turnLeft/turnRight, which
        // deliberately need an off-frontal pose that check would otherwise
        // fight.
        let captureRejection = FaceCaptureValidator.isFaceCaptureValid(face: detections[0], frame: pixelBuffer, step: step)
        guard captureRejection == nil else {
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = nil
            }
            poseStability.record(posePassed: false)
            evaluateStepDeadlines(at: now)
            return
        }

        // Smoothed, not raw — see smoothedYawDegrees's declaration comment.
        // Only the pose-range comparison uses this; the live UI nudge below
        // still publishes the raw per-frame value for responsiveness.
        let yaw = smoothedYawDegrees.map { $0 * (1 - poseSmoothingAlpha) + quality.yawDegrees * poseSmoothingAlpha } ?? quality.yawDegrees
        let pitch = smoothedPitchDegrees.map { $0 * (1 - poseSmoothingAlpha) + quality.pitchDegrees * poseSmoothingAlpha } ?? quality.pitchDegrees
        smoothedYawDegrees = yaw
        smoothedPitchDegrees = pitch

        let poseMatches = isPoseInRange(step: step, yawDegrees: yaw, pitchDegrees: pitch)

        DispatchQueue.main.async {
            self.liveYawDegrees = quality.yawDegrees
            self.livePitchDegrees = quality.pitchDegrees
            self.hasLiveFace = true
            self.liveRejectionReason = nil
        }

        let poseHeld = poseStability.record(posePassed: poseMatches)

        guard poseMatches else {
            evaluateStepDeadlines(at: now)
            return
        }
        // The pose is right but hasn't held long enough yet — one stray frame
        // is not a pose. Say nothing and let the user keep still.
        guard poseHeld else { return }

        DispatchQueue.main.async {
            self.state = .poseHeld(step: step, stepIndex: self.currentStepIndex, stepCount: self.poseSteps.count)
        }

        // Keep the best held-pose frame and give a short settle window for a
        // better one to arrive; each improvement pushes the deadline out.
        if bestPoseMatchedCandidate == nil || quality.qualityScore > bestPoseMatchedCandidate!.quality.qualityScore {
            bestPoseMatchedCandidate = (pixelBuffer, detections[0], quality)
            settleDeadline = now + settleWindowSeconds
        }

        evaluateStepDeadlines(at: now)
    }

    /// True if the given yaw/pitch estimate falls inside the current step's
    /// target range. Steps with no strict target (nil range) are satisfied
    /// by any acceptable-quality frame. Takes smoothed values, not a raw
    /// FaceQualityResult — see the smoothedYawDegrees declaration comment.
    private nonisolated func isPoseInRange(step: EnrollmentPoseStep, yawDegrees: Float, pitchDegrees: Float) -> Bool {
        if let yawRange = step.targetYawDegrees, !yawRange.contains(yawDegrees) {
            return false
        }
        if let pitchRange = step.targetPitchDegrees, !pitchRange.contains(pitchDegrees) {
            return false
        }
        return true
    }

    /// True if `box` is still plausibly the same physical face as the one
    /// that captured `.center` (`anchor`) — size and position tolerance,
    /// not frame-to-frame overlap. An earlier version used IoU against the
    /// PREVIOUS frame, which broke on every legitimate head turn (turning
    /// the head to satisfy turnLeft/turnRight IS a box jump, so IoU
    /// couldn't tell "moved" from "different person"). Anchoring to one
    /// fixed reference and checking size+position tolerance instead solves
    /// that: a normal turn drifts the box somewhat but stays within these
    /// bounds, while a genuine swap-in (different distance from camera, or
    /// appearing somewhere else in frame) does not.
    private nonisolated func boxMatchesAnchor(_ box: CGRect, anchor: CGRect, frameSize: CGSize) -> Bool {
        guard anchor.width > 0 else { return true }
        let widthRatio = Float(box.width / anchor.width)
        let widthPass = anchorBoxWidthRatio.contains(widthRatio)

        var dx: Float = 0, dy: Float = 0, driftPass = true
        if frameSize.width > 0, frameSize.height > 0 {
            dx = Float(abs(box.midX - anchor.midX) / frameSize.width)
            dy = Float(abs(box.midY - anchor.midY) / frameSize.height)
            driftPass = dx <= anchorBoxCenterDriftRatio && dy <= anchorBoxCenterDriftRatio
        }

        guard widthPass else { return false }
        return driftPass
    }

    /// Track continuity broke — a different person is in frame, or the face
    /// was gone long enough that nothing downstream can still establish that
    /// whoever is there now is who captured `.center`. Restarting is the only
    /// honest response, so everything collected is discarded and the scan goes
    /// back to `.center`. The typed name survives.
    ///
    /// Not a terminal failure screen: a swap is recoverable by the right
    /// person simply stepping back in front of the camera, and an earlier
    /// version's silent reset only looked arbitrary because it said nothing —
    /// the held notice below is what fixes that, not stopping the flow.
    private nonisolated func restartForBrokenTrack() {
        collectedEmbeddings = []
        collectedSteps = []
        bestPoseMatchedCandidate = nil
        settleDeadline = nil
        frontalAvatar = nil
        centerAnchorBox = nil
        consecutiveAnchorMismatchFrames = 0
        currentStepIndex = 0
        smoothedYawDegrees = nil
        smoothedPitchDegrees = nil
        poseStability.reset()
        trackGate.reset()
        resetQualityThresholds(step: .center)

        stepStartedAt = Self.monotonicNow()

        DispatchQueue.main.async {
            self.completedSteps = []
            self.hasLiveFace = false
            self.liveRejectionReason = nil
            self.publishAwaitingPose()
            // Held: the restarted `.center` step's own copy lands one frame
            // interval later and would replace this before anyone could read
            // it, or hear it spoken. `instructionText` prefers this while set.
            self.showTrackBrokenNotice()
        }
    }

    /// Shows the "keep the same person in frame" notice and holds it for
    /// `trackBrokenNoticeSeconds`, speaking it on the same channel every pose
    /// step already uses.
    private func showTrackBrokenNotice() {
        trackBrokenNoticeToken &+= 1
        let token = trackBrokenNoticeToken
        let holdSeconds = trackBrokenNoticeSeconds
        isShowingTrackBrokenNotice = true
        SpeechManager.shared.speak(L10n.FaceAuth.samePersonRequired)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(holdSeconds * 1_000_000_000))
            // A second break during the hold supersedes this one.
            guard let self, self.trackBrokenNoticeToken == token else { return }
            self.isShowingTrackBrokenNotice = false
        }
    }

    /// Commits the step's best candidate once its settle window expires.
    /// Deliberately has no timeout branch: a step with no candidate yet has no
    /// deadline and simply keeps sampling, so a pose can never be skipped and
    /// enrollment can never finish with a missing embedding.
    private nonisolated func evaluateStepDeadlines(at now: TimeInterval) {
        if let deadline = settleDeadline, now >= deadline, let candidate = bestPoseMatchedCandidate {
            captureStep(using: candidate)
        }
    }

    // MARK: - Sample capture

    private nonisolated func captureStep(
        using candidate: (pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, quality: FaceQualityResult)
    ) {
        let step = poseSteps[currentStepIndex]
        DispatchQueue.main.async {
            self.state = .capturingSample(step: step, stepIndex: self.currentStepIndex, stepCount: self.poseSteps.count)
        }

        guard let embedding = repository.generateEnrollmentEmbedding(
            pixelBuffer: candidate.pixelBuffer, detection: candidate.detection, qualityScore: candidate.quality.qualityScore
        ) else {
            // SFace/alignment failure — discard this step's candidate and keep
            // sampling. The step has no deadline of its own, so this simply
            // retries until a frame embeds successfully.
            AppLogger.shared.warn("Enrollment: step \(currentStepIndex) (\(step)) — embedding generation failed, retrying")
            bestPoseMatchedCandidate = nil
            settleDeadline = nil
            poseStability.reset()
            return
        }

        collectedEmbeddings.append(embedding)
        collectedSteps.append(step)
        DispatchQueue.main.async { self.completedSteps.insert(step) }

        // Render the row thumbnail from the frontal step only — the turned and
        // chin-up poses make for a poor portrait. Done here rather than in
        // `finishEnrollment` because the candidate's pixel buffer is owned by
        // the capture session's pool and gets recycled once this returns.
        // A nil result just means no avatar; enrollment carries on regardless.
        if step == .center {
            frontalAvatar = FaceAvatarRenderer.makeAvatar(
                pixelBuffer: candidate.pixelBuffer, detection: candidate.detection
            )
            if frontalAvatar == nil {
                AppLogger.shared.warn("Enrollment: frontal avatar render failed — user will show the placeholder")
            }
            // The fixed reference every later frame's box is checked
            // against for track continuity (see centerAnchorBox's
            // declaration comment) — set once here, never updated again.
            centerAnchorBox = candidate.detection.boundingBox
        }

        AppLogger.shared.info("Enrollment: step \(currentStepIndex) (\(step)) captured — \(collectedEmbeddings.count)/\(poseSteps.count) embeddings, quality=\(String(format: "%.2f", candidate.quality.qualityScore))")

        // Duplicate check moved here from finishEnrollment: asking only after
        // all five poses meant an already-enrolled person spent the whole flow
        // before being told, and got a dead end rather than a choice. One
        // frontal embedding is enough to answer the question.
        //
        // Accepted trade: the old check compared all five embeddings, this one
        // only the frontal, and there is no end-of-flow safety net any more —
        // a duplicate whose frontal misses the threshold but whose turned pose
        // would have hit it is now missed. That is inherent to asking early.
        //
        // `.centerAgain` is a distinct step and deliberately does NOT re-ask.
        if step == .center, duplicatePausedAt == nil {
            // Gate first, on this (camera) queue: handleFrame is serial and
            // additionally guarded by isProcessing, so no frame can be
            // mid-flight when the flag flips, and every later one bounces at
            // the top of handleFrame.
            isCapturingFrames = false
            duplicatePausedAt = Self.monotonicNow()
            let attemptId = pendingUserId
            let candidates = collectedEmbeddings
            DispatchQueue.main.async {
                self.runDuplicateCheck(attemptId: attemptId, candidates: candidates)
            }
            return // advanceToNextStep happens on resume
        }

        advanceToNextStep()
    }

    /// Runs the duplicate check and either resumes silently or raises the
    /// prompt. On the main actor deliberately: both face stores read
    /// `CoreDataManager.shared.context`, which is `viewContext` and therefore
    /// main-queue confined — the old camera-queue call site was a latent
    /// threading violation this must not inherit.
    ///
    /// `internal` rather than `private` so tests can drive it without a camera.
    func runDuplicateCheck(attemptId: String?, candidates: [FaceEmbedding]) {
        // The attempt can be torn down (back button, backgrounding, dismiss)
        // between the camera queue scheduling this and it running, and again
        // across the synchronous fetch below. pendingUserId is the attempt
        // token — a stale result must not resurrect a prompt on a dead attempt.
        guard let attemptId, pendingUserId == attemptId else { return }

        let match = repository.checkDuplicateFace(against: candidates, excludingUserId: nil)
        guard pendingUserId == attemptId else { return }

        guard let match else {
            resumeCaptureAfterDuplicatePrompt()
            return
        }

        AppLogger.shared.warn("Enrollment: .center matches existing user \(match.userId) — prompting")
        duplicateMatch = match // pipeline stays paused until the user answers
    }

    /// The user chose to enroll this face anyway, knowing it may leave both
    /// people unable to unlock (see the dialog copy). Resumes from exactly
    /// where `.center` paused — the remaining four poses run normally.
    func continueAfterDuplicate() {
        guard let match = duplicateMatch else { return }
        AppLogger.shared.warn("Enrollment: continuing despite duplicate of \(match.userId)")
        duplicateMatch = nil
        resumeCaptureAfterDuplicatePrompt()
    }

    /// Called on main with the pipeline provably idle — `isCapturingFrames` is
    /// false, so the session queue is short-circuiting every frame at the top
    /// of `handleFrame`. This is the one place the class's camera-queue-only
    /// rule is deliberately crossed, and it is safe only because the flag is
    /// re-armed LAST: no frame can observe half-updated step state.
    private func resumeCaptureAfterDuplicatePrompt() {
        if let pausedAt = duplicatePausedAt {
            // Shift the origin forward rather than tracking paused time
            // separately, so `now - stepStartedAt` stays correct without
            // knowing a pause ever happened — otherwise reading the prompt
            // for a few seconds would escalate the next step's hint
            // immediately.
            stepStartedAt += Self.monotonicNow() - pausedAt
            duplicatePausedAt = nil
        }
        // Nothing observed the track while the prompt was up, so the box from
        // before the gap is no longer something the next frame can be judged
        // against — it would fail IoU instantly and read as a person swap.
        trackGate.dropLastReference()
        advanceToNextStep()
        isCapturingFrames = true
    }

    private nonisolated func advanceToNextStep() {
        bestPoseMatchedCandidate = nil
        settleDeadline = nil
        poseStability.reset()
        smoothedYawDegrees = nil
        smoothedPitchDegrees = nil

        currentStepIndex += 1
        stepStartedAt = Self.monotonicNow()

        guard currentStepIndex < poseSteps.count else {
            isCapturingFrames = false
            cameraService.stop()
            cameraService.onFrame = nil
            finishEnrollment()
            return
        }

        resetQualityThresholds(step: poseSteps[currentStepIndex])
        DispatchQueue.main.async { self.publishAwaitingPose() }
    }

    private nonisolated func finishEnrollment() {
        guard pendingUserId != nil else {
            DispatchQueue.main.async { self.state = .failed(.storageError) }
            return
        }

        let embeddings = collectedEmbeddings
        let avatar = frontalAvatar
        let firstName = pendingFirstName
        let lastName = pendingLastName
        // EVERY pose is required. There is no step-skip and no timeout left in
        // the capture loop, so the only way to reach here is by capturing all
        // of them — this is defense in depth against a future path that
        // doesn't. QA saw enrollment complete having silently skipped "turn
        // right" back when a step could time out and a 3-of-5 floor was
        // enough; a gallery missing an angle can't match that angle later.
        let missing = Set(poseSteps).subtracting(collectedSteps)
        guard missing.isEmpty else {
            AppLogger.shared.warn("Enrollment: refusing to finish — missing steps \(missing)")
            DispatchQueue.main.async { self.state = .failed(.timedOut) }
            return
        }

        // No duplicate check here any more — it runs at the `.center` capture
        // instead, as a prompt the user can answer rather than a rejection
        // they only discover after the whole flow. See captureStep.

        // Both stores read CoreDataManager.shared.context (viewContext,
        // main-queue confined) — hop before touching repository, same as
        // runDuplicateCheck above, instead of calling it from this
        // camera-queue function.
        DispatchQueue.main.async {
            // Nothing is persisted until this point (see class header) — the
            // user row and its embeddings are created together, so a row can
            // never exist without embeddings.
            let user = self.repository.registerUser(firstName: firstName, lastName: lastName)
            guard let registeredUserId = user.id else {
                self.state = .failed(.storageError)
                return
            }

            let success = self.repository.saveEnrollmentEmbeddings(userId: registeredUserId, embeddings: embeddings)
            AppLogger.shared.info("Enrollment: finishing for user \(registeredUserId) — \(embeddings.count) embeddings, persisted=\(success)")

            if success {
                self.pendingUserId = registeredUserId
                // Only after the embeddings are durably stored — a
                // rolled-back enrollment must not leave an avatar file
                // behind.
                if let avatar {
                    self.repository.saveAvatar(userId: registeredUserId, image: avatar)
                }
                self.state = .enrollmentComplete
            } else {
                self.repository.deleteUser(id: registeredUserId)
                self.state = .failed(.storageError)
            }
        }
    }

    // MARK: - Quality thresholds

    /// True for turnLeft/turnRight/chinUp — a deliberately off-frontal pose
    /// naturally reads a smaller apparent box width than a held-still
    /// frontal one (measured on real device logs: legitimate turned-face
    /// widths as low as 208-230px, well under the frontal floor below).
    /// Same rationale as FaceCaptureValidator's relaxed confidence/
    /// sharpness floors for these same steps.
    private nonisolated func isOffCenterStep(_ step: EnrollmentPoseStep) -> Bool {
        step == .turnLeft || step == .turnRight || step == .chinUp
    }

    private nonisolated func resetQualityThresholds(step: EnrollmentPoseStep) {
        qualityChecker.minFaceWidthPx = isOffCenterStep(step) ? 200 : 240
        qualityChecker.maxFaceWidthRatio = 0.85
        qualityChecker.maxCenterOffsetXRatio = 0.30
        qualityChecker.maxCenterOffsetYRatio = 0.30
    }

    private nonisolated static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - UI-facing state

    private func publishAwaitingPose() {
        let step = poseSteps[currentStepIndex]
        state = .awaitingPose(step: step, stepIndex: currentStepIndex, stepCount: poseSteps.count)
    }

    /// Whether the current pose has been unmet long enough to deserve firmer
    /// wording. Read during a render rather than published on a timer — the
    /// frame pipeline publishes often enough to refresh it, and a step with no
    /// frames arriving has nothing to re-word anyway.
    private var isStepEscalated: Bool {
        Self.monotonicNow() - stepStartedAt >= escalateAfterSeconds
    }

    var instructionText: String {
        // Outranks every step's own copy: a continuity restart has to be
        // readable, and the restarted step's guidance lands one frame interval
        // later. Cleared by showTrackBrokenNotice's hold.
        if isShowingTrackBrokenNotice { return L10n.FaceAuth.samePersonRequired }

        switch state {
        case .idle: return L10n.FaceAuth.instructionIdle
        case .preparing: return L10n.FaceAuth.instructionPreparing
        case .awaitingPose(let step, _, _):
            if liveRejectionReason == .faceCropIncomplete { return L10n.FaceAuth.faceOffCenter }
            // Firmer wording once the user has been stuck on this pose a
            // while — Android's ESCALATE_AFTER_MS.
            if isStepEscalated, let escalated = step.escalatedInstructionKey { return escalated }
            return step.instructionKey
        case .poseHeld: return L10n.FaceAuth.poseHoldStill
        case .capturingSample: return L10n.FaceAuth.poseCaptured
        case .enrollmentComplete: return L10n.FaceAuth.instructionComplete
        case .failed(let reason): return failureText(reason)
        }
    }

    /// Which way the user must move for the current step, or nil when there
    /// is nothing to nudge (no usable face in frame, or not mid-capture).
    /// Derived live from the published yaw/pitch, so the arrow tracks the
    /// actual head pose rather than a timed script.
    var poseNudge: PoseNudge? {
        guard hasLiveFace else { return nil }
        switch state {
        case .awaitingPose(let step, _, _), .poseHeld(let step, _, _):
            return PoseNudge.from(step: step, yawDegrees: liveYawDegrees, pitchDegrees: livePitchDegrees)
        case .capturingSample:
            return .onTarget
        default:
            return nil
        }
    }

    /// Spinner state for the shared scan screen — EnrollmentState doesn't map
    /// onto AuthenticationState, so the screen takes this as an override.
    var isBusy: Bool {
        switch state {
        case .preparing, .poseHeld, .capturingSample: return true
        default: return false
        }
    }

    /// (stepIndex, stepCount) for the progress-dots UI, nil when not
    /// actively capturing a step.
    var stepProgress: (index: Int, count: Int)? {
        switch state {
        case .awaitingPose(_, let index, let count),
             .poseHeld(_, let index, let count),
             .capturingSample(_, let index, let count):
            return (index, count)
        default:
            return nil
        }
    }

    private func failureText(_ reason: EnrollmentFailureReason) -> String {
        switch reason {
        case .noFace: return L10n.FaceAuth.failureNoFace
        case .multipleFaces: return L10n.FaceAuth.failureMultipleFaces
        case .poorQuality: return L10n.FaceAuth.failurePoorQuality
        case .embeddingGenerationFailed: return L10n.FaceAuth.failureEmbedding
        case .cameraError: return L10n.FaceAuth.failureCamera
        case .storageError: return L10n.FaceAuth.failureStorage
        case .timedOut: return L10n.FaceAuth.failureTimedOut
        case .differentFaceDetected: return L10n.FaceAuth.failureDifferentFace
        }
    }
}
