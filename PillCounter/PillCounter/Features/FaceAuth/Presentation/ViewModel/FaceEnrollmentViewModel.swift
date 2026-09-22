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
//  hard-rejecting every imperfect frame, thresholds relax progressively if a
//  step is slow, and a global timeout guarantees the flow always resolves to
//  either EnrollmentComplete or an explicit failure — never an endless loop.
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

    /// Best-of-window duration per pose step before accepting the best
    /// candidate seen so far, even if it isn't a perfect frame.
    private let stepWindowSeconds: TimeInterval = 3.0
    /// After this long on one step with zero usable candidates, relax the
    /// quality checker's hard gates once.
    private let relaxAfterSeconds: TimeInterval = 5.0
    /// Hard per-step ceiling — beyond this, accept the best candidate even
    /// if the window logic above hasn't already, or fail the step.
    private let stepHardTimeoutSeconds: TimeInterval = 12.0
    /// Global enrollment budget. On expiry: complete with whatever usable
    /// samples exist if there are enough for a workable enrollment,
    /// otherwise fail explicitly. Never loop past this.
    private let globalTimeoutSeconds: TimeInterval = 60.0
    /// Minimum samples required to consider enrollment usable at all.
    private let minimumUsableSamples = 3
    /// Consecutive frames a pose must be held in-range before it "counts"
    /// as achieved — smooths per-frame yaw/pitch noise (~0.5s @ 15fps).
    private let poseHoldFrameThreshold = 6
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
    /// Consecutive no-face frames tolerated before losing the track — grace
    /// for a hand briefly passing in front of the lens, or the user briefly
    /// stepping out/repositioning, without treating that the same as a
    /// person swap. ~3s at this pipeline's documented reference rate (see
    /// poseHoldFrameThreshold: 6 frames ≈ 0.5s @ 15fps) — was 3 frames
    /// (~0.5s), which failed genuine users for a momentary lapse.
    private let trackGraceFrames = 45
    /// Consecutive anchor-mismatch frames tolerated before failing — absorbs
    /// one noisy/blurry/motion-glitch frame without failing the same person,
    /// while a genuinely different face keeps mismatching frame after frame
    /// and still gets caught quickly. Deliberately much smaller than
    /// trackGraceFrames: a face IS present here, just not matching, which is
    /// a stronger signal than mere absence and shouldn't get the same long
    /// grace.
    private let anchorMismatchGraceFrames = 3

    // MARK: - Capture-pipeline state (camera-queue-only, see header)

    private nonisolated(unsafe) var isProcessing = false
    // `isCapturingFrames`, `pendingUserId`, `duplicatePausedAt` and
    // `enrollmentStartedAt` are internal rather than private so the duplicate-
    // prompt tests can drive runDuplicateCheck/continueAfterDuplicate without a
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
    /// Consecutive frames with no usable detection — distinct from a person
    /// swap (box jumps) so a brief occlusion doesn't restart the capture.
    private nonisolated(unsafe) var consecutiveNoFaceFrames = 0
    /// Consecutive frames where a face IS present but doesn't match
    /// centerAnchorBox — see anchorMismatchGraceFrames's declaration.
    private nonisolated(unsafe) var consecutiveAnchorMismatchFrames = 0
    private var backgroundObserver: NSObjectProtocol?

    /// Monotonic instant capture was paused for the duplicate prompt, nil when
    /// not paused. Doubles as the re-entrancy guard for the check itself. On
    /// resume both budget origins are shifted forward by the elapsed pause, so
    /// reading a modal the user can't dismiss quickly never burns the 60s
    /// global budget. Internal for tests — see the note above `isCapturingFrames`.
    nonisolated(unsafe) var duplicatePausedAt: TimeInterval?

    private nonisolated(unsafe) var currentStepIndex = 0
    private nonisolated(unsafe) var poseHoldFrames = 0
    private nonisolated(unsafe) var stepStartedAt: TimeInterval = 0
    nonisolated(unsafe) var enrollmentStartedAt: TimeInterval = 0
    private nonisolated(unsafe) var relaxedThisStep = false
    /// EMA-smoothed yaw/pitch, compared against the step's target range
    /// instead of the raw per-frame estimate — FaceQualityChecker's yaw/pitch
    /// proxies are explicitly documented as noisy single-frame readings, and
    /// poseHoldFrames resets to 0 on any single miss, so unsmoothed jitter
    /// was breaking the 6-consecutive-frame streak independent of how fast
    /// or slow the user actually turned. nil until the first usable frame of
    /// a step, so that frame seeds the average instead of blending against 0.
    private nonisolated(unsafe) var smoothedYawDegrees: Float?
    private nonisolated(unsafe) var smoothedPitchDegrees: Float?
    /// Weight given to each new frame in the EMA above — low enough to
    /// absorb per-frame landmark jitter, high enough to still track a
    /// deliberate head turn within the step's time budget.
    private let poseSmoothingAlpha: Float = 0.3
    /// Best candidate seen so far THAT ALSO SATISFIED the step's pose range.
    /// Captured at the soft window deadline; if the hard timeout arrives with
    /// this still nil, the step is skipped rather than recording a
    /// mismatched-pose embedding (e.g. a centered frame for "turn left").
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
        poseHoldFrames = 0
        bestPoseMatchedCandidate = nil
        frontalAvatar = nil
        relaxedThisStep = false
        smoothedYawDegrees = nil
        smoothedPitchDegrees = nil
        centerAnchorBox = nil
        consecutiveNoFaceFrames = 0
        consecutiveAnchorMismatchFrames = 0
        duplicateMatch = nil
        duplicatePausedAt = nil
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

        let now = Self.monotonicNow()
        enrollmentStartedAt = now
        stepStartedAt = now

        cameraService.onFrame = { [weak self] pixelBuffer in
            self?.handleFrame(pixelBuffer)
        }
        isCapturingFrames = true
        cameraService.start()
        publishAwaitingPose()
        Log("Enrollment: started for user \(userId), \(poseSteps.count) pose steps")
    }

    func cancelEnrollment() {
        isCapturingFrames = false
        cameraService.stop()
        cameraService.onFrame = nil
        // No DB cleanup needed — nothing is persisted until finishEnrollment()
        // succeeds, so an in-progress attempt never has a row to delete.
        Log("Enrollment: cancelled, had \(collectedEmbeddings.count) embedding(s) — nothing persisted")
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

        checkGlobalTimeout()
        guard isCapturingFrames else { return } // may have just been resolved by the timeout check

        let detections = detector.detect(pixelBuffer: pixelBuffer)

        guard detections.count == 1 else {
            Log("Enrollment: frame skipped — \(detections.count) face(s) detected")
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = nil
            }
            handleNoUsableFaceFrame()
            return
        }

        let step = poseSteps[currentStepIndex]

        // Track continuity — same physical face as the one that captured
        // .center? Runs before the quality/pose gates, since a person swap
        // is an identity problem, not a quality problem: a swapped-in face
        // can easily be well-lit, sharp, and correctly posed, and none of
        // the checks below would ever catch it. No-op until .center is
        // captured (centerAnchorBox nil) — nothing to anchor against yet.
        consecutiveNoFaceFrames = 0
        let box = detections[0].boundingBox
        if let anchor = centerAnchorBox, !boxMatchesAnchor(box, anchor: anchor, frameSize: detections[0].frameSize) {
            consecutiveAnchorMismatchFrames += 1
            if consecutiveAnchorMismatchFrames > anchorMismatchGraceFrames {
                Log("Enrollment: track lost — box mismatched the center-step anchor for \(consecutiveAnchorMismatchFrames) frames")
                failTrackContinuity()
                return
            }
            // Within grace — discard this frame like any other rejected-but-
            // not-fatal one rather than treating it as a good capture
            // candidate.
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = nil
            }
            evaluateStepDeadlines(sawUsableFrame: false)
            return
        }
        consecutiveAnchorMismatchFrames = 0

        let quality = qualityChecker.check(detection: detections[0], pixelBuffer: pixelBuffer)
        guard quality.isAcceptable else {
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = quality.reason
            }
            evaluateStepDeadlines(sawUsableFrame: false)
            return
        }

        // Strict completeness gate — runs after the existing box/sharpness
        // check, before this frame is eligible as a capture candidate. See
        // FaceCaptureValidator.swift for what this catches and why. `step`
        // lets it skip the yaw-ratio check for turnLeft/turnRight, which
        // deliberately need an off-frontal pose that check would otherwise
        // fight.
        let captureRejection = FaceCaptureValidator.isFaceCaptureValid(face: detections[0], frame: pixelBuffer, step: step)
        // TEMP DEBUG — remove once turnLeft/turnRight/chinUp reliably capture.
        Log("DEBUG captureGate: step=\(step) rejection=\(String(describing: captureRejection))")
        guard captureRejection == nil else {
            DispatchQueue.main.async {
                self.hasLiveFace = false
                self.liveRejectionReason = nil
            }
            evaluateStepDeadlines(sawUsableFrame: false)
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
        // TEMP DEBUG — remove once turnLeft/turnRight/chinUp reliably capture.
        Log("DEBUG poseGate: step=\(step) rawYaw=\(String(format: "%.1f", quality.yawDegrees)) smoothedYaw=\(String(format: "%.1f", yaw)) rawPitch=\(String(format: "%.1f", quality.pitchDegrees)) smoothedPitch=\(String(format: "%.1f", pitch)) targetYaw=\(String(describing: step.targetYawDegrees)) targetPitch=\(String(describing: step.targetPitchDegrees)) poseMatches=\(poseMatches) holdFrames=\(poseHoldFrames)")

        DispatchQueue.main.async {
            self.liveYawDegrees = quality.yawDegrees
            self.livePitchDegrees = quality.pitchDegrees
            self.hasLiveFace = true
            self.liveRejectionReason = nil
        }

        if poseMatches {
            poseHoldFrames += 1
        } else {
            poseHoldFrames = 0
        }

        if poseMatches, bestPoseMatchedCandidate == nil || quality.qualityScore > bestPoseMatchedCandidate!.quality.qualityScore {
            bestPoseMatchedCandidate = (pixelBuffer, detections[0], quality)
        }

        if poseHoldFrames >= poseHoldFrameThreshold {
            DispatchQueue.main.async {
                self.state = .poseHeld(step: step, stepIndex: self.currentStepIndex, stepCount: self.poseSteps.count)
            }
            captureStep(using: (pixelBuffer, detections[0], quality))
            return
        }

        evaluateStepDeadlines(sawUsableFrame: true)
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

    /// A frame with no single usable detection (none, or more than one) —
    /// counts toward the track-continuity grace period as well as the
    /// existing per-step deadline logic. Exceeding the grace fails
    /// enrollment the same way an anchor mismatch does: from the pipeline's
    /// perspective, "the face has been gone too long" and "a different face
    /// is here now" are both a loss of identity continuity, and both should
    /// surface the same explicit failure rather than one being silent.
    private nonisolated func handleNoUsableFaceFrame() {
        consecutiveNoFaceFrames += 1
        if consecutiveNoFaceFrames > trackGraceFrames {
            Log("Enrollment: track lost — no usable face for \(consecutiveNoFaceFrames) frames")
            failTrackContinuity()
            return
        }
        evaluateStepDeadlines(sawUsableFrame: false)
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

        // TEMP DEBUG — remove once real-device numbers confirm the right
        // thresholds. Currently failing turnLeft/turnRight/chinUp on real
        // enrollment attempts with only small head movement.
        Log("DEBUG trackAnchor: widthRatio=\(String(format: "%.2f", widthRatio)) (pass=\(widthPass)) dx=\(String(format: "%.2f", dx)) dy=\(String(format: "%.2f", dy)) (driftPass=\(driftPass)) anchor=\(anchor) box=\(box)")

        guard widthPass else { return false }
        return driftPass
    }

    /// Track continuity broke (person swap, or the face was gone too long)
    /// — a terminal, explicit failure the user has to acknowledge and
    /// retry from, rather than a silent auto-restart. An earlier version
    /// silently reset back to `.center` here, which from the user's
    /// perspective looked like the scan randomly restarting for no visible
    /// reason. Nothing to delete — per the class header, nothing is
    /// persisted until `finishEnrollment()` succeeds — so this only stops
    /// the camera and publishes the failure; `retry()` (already a pure
    /// in-memory reset) is what actually restarts capture, on an explicit
    /// user tap.
    private nonisolated func failTrackContinuity() {
        isCapturingFrames = false
        cameraService.stop()
        cameraService.onFrame = nil
        DispatchQueue.main.async {
            self.state = .failed(.differentFaceDetected)
        }
    }

    /// Applies the progressive-relaxation / best-of-window / hard-timeout
    /// rules described in the header, called once per rejected-or-pending frame.
    private nonisolated func evaluateStepDeadlines(sawUsableFrame: Bool) {
        let elapsed = Self.monotonicNow() - stepStartedAt
        let step = poseSteps[currentStepIndex]

        if !relaxedThisStep && elapsed >= relaxAfterSeconds {
            relaxedThisStep = true
            relaxQualityThresholds(step: step)
        }

        if elapsed >= stepWindowSeconds, let candidate = bestPoseMatchedCandidate {
            captureStep(using: candidate)
            return
        }

        if elapsed >= stepHardTimeoutSeconds {
            // The center pose is the mandatory anchor sample (it's what
            // finishEnrollment() now requires and what frontalAvatar renders
            // from) — QA saw enrollment complete having silently skipped a
            // straight-face capture because this branch used to advance
            // unconditionally on timeout. For .center only, keep retrying
            // (relaxQualityThresholds already ran above once, same as any
            // other step) instead of advancing; the global 60s budget in
            // checkGlobalTimeout is still what bounds this from running
            // forever.
            guard step != .center else {
                stepStartedAt = Self.monotonicNow()
                relaxedThisStep = true
                return
            }
            // No pose-matched candidate for the whole step budget — skip it
            // rather than recording a mismatched-pose embedding (e.g. a
            // centered frame for the "turn left" step); minimumUsableSamples
            // is the floor that keeps overall enrollment viable.
            advanceToNextStep()
        }
    }

    private nonisolated func checkGlobalTimeout() {
        guard Self.monotonicNow() - enrollmentStartedAt >= globalTimeoutSeconds else { return }
        guard isCapturingFrames else { return }

        isCapturingFrames = false
        cameraService.stop()
        cameraService.onFrame = nil

        if collectedEmbeddings.count >= minimumUsableSamples {
            finishEnrollment()
        } else {
            DispatchQueue.main.async { self.state = .failed(.timedOut) }
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
            // SFace/alignment failure — discard this step's candidate and
            // let the window keep running; evaluateStepDeadlines will retry
            // or eventually hard-timeout the step.
            Log("Enrollment: step \(currentStepIndex) (\(step)) — embedding generation failed, retrying")
            bestPoseMatchedCandidate = nil
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
                Log("Enrollment: frontal avatar render failed — user will show the placeholder")
            }
            // The fixed reference every later frame's box is checked
            // against for track continuity (see centerAnchorBox's
            // declaration comment) — set once here, never updated again.
            centerAnchorBox = candidate.detection.boundingBox
        }

        Log("Enrollment: step \(currentStepIndex) (\(step)) captured — \(collectedEmbeddings.count)/\(poseSteps.count) embeddings, quality=\(String(format: "%.2f", candidate.quality.qualityScore))")

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
            // the top of handleFrame — which also freezes checkGlobalTimeout.
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

        Log("Enrollment: .center matches existing user \(match.userId) — prompting")
        duplicateMatch = match // pipeline stays paused until the user answers
    }

    /// The user chose to enroll this face anyway, knowing it may leave both
    /// people unable to unlock (see the dialog copy). Resumes from exactly
    /// where `.center` paused — the remaining four poses run normally.
    func continueAfterDuplicate() {
        guard let match = duplicateMatch else { return }
        Log("Enrollment: continuing despite duplicate of \(match.userId)")
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
            // Shift both budget origins forward rather than tracking paused
            // time separately, so every existing `now - origin` comparison
            // stays correct without knowing a pause ever happened.
            let paused = Self.monotonicNow() - pausedAt
            enrollmentStartedAt += paused
            stepStartedAt += paused
            duplicatePausedAt = nil
        }
        advanceToNextStep()
        isCapturingFrames = true
    }

    private nonisolated func advanceToNextStep() {
        bestPoseMatchedCandidate = nil
        poseHoldFrames = 0
        relaxedThisStep = false
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
        guard let userId = pendingUserId else {
            DispatchQueue.main.async { self.state = .failed(.storageError) }
            return
        }

        let embeddings = collectedEmbeddings
        // Defense in depth alongside the .center timeout-skip removed above:
        // even if some future code path reached here without a center
        // sample, refuse to complete rather than accept a total count with
        // no straight-face embedding among it.
        guard embeddings.count >= minimumUsableSamples, collectedSteps.contains(.center) else {
            DispatchQueue.main.async { self.state = .failed(.timedOut) }
            return
        }

        // No duplicate check here any more — it runs at the `.center` capture
        // instead, as a prompt the user can answer rather than a rejection
        // they only discover after the whole flow. See captureStep.

        // Nothing is persisted until this point (see class header) — the
        // user row and its embeddings are created together, so a row can
        // never exist without embeddings.
        let user = repository.registerUser(firstName: pendingFirstName, lastName: pendingLastName)
        guard let registeredUserId = user.id else {
            DispatchQueue.main.async { self.state = .failed(.storageError) }
            return
        }

        let success = repository.saveEnrollmentEmbeddings(userId: registeredUserId, embeddings: embeddings)
        Log("Enrollment: finishing for user \(registeredUserId) — \(embeddings.count) embeddings, persisted=\(success)")

        if success {
            // Only after the embeddings are durably stored — a rolled-back
            // enrollment must not leave an avatar file behind.
            if let avatar = frontalAvatar {
                repository.saveAvatar(userId: registeredUserId, image: avatar)
            }
        }

        DispatchQueue.main.async {
            if success {
                self.pendingUserId = registeredUserId
                self.state = .enrollmentComplete
            } else {
                self.repository.deleteUser(id: registeredUserId)
                self.state = .failed(.storageError)
            }
        }
    }

    // MARK: - Threshold relaxation

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

    private nonisolated func relaxQualityThresholds(step: EnrollmentPoseStep) {
        qualityChecker.minFaceWidthPx = isOffCenterStep(step) ? 160 : 180
        qualityChecker.maxFaceWidthRatio = 0.9
        // Without relaxing this too, a user stuck slightly off-center could
        // burn the entire step window with no escape hatch — width/ratio
        // relaxation alone doesn't help them.
        qualityChecker.maxCenterOffsetXRatio = 0.40
        qualityChecker.maxCenterOffsetYRatio = 0.40
    }

    private nonisolated static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - UI-facing state

    private func publishAwaitingPose() {
        let step = poseSteps[currentStepIndex]
        state = .awaitingPose(step: step, stepIndex: currentStepIndex, stepCount: poseSteps.count)
    }

    var instructionText: String {
        switch state {
        case .idle: return L10n.FaceAuth.instructionIdle
        case .preparing: return L10n.FaceAuth.instructionPreparing
        case .awaitingPose(let step, _, _):
            if liveRejectionReason == .faceCropIncomplete { return L10n.FaceAuth.faceOffCenter }
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
