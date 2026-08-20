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

    // MARK: - Capture-pipeline state (camera-queue-only, see header)

    private nonisolated(unsafe) var isProcessing = false
    private nonisolated(unsafe) var isCapturingFrames = false
    private nonisolated(unsafe) var pendingUserId: String?
    private nonisolated(unsafe) var collectedEmbeddings: [FaceEmbedding] = []

    private nonisolated(unsafe) var currentStepIndex = 0
    private nonisolated(unsafe) var poseHoldFrames = 0
    private nonisolated(unsafe) var stepStartedAt: TimeInterval = 0
    private nonisolated(unsafe) var enrollmentStartedAt: TimeInterval = 0
    private nonisolated(unsafe) var relaxedThisStep = false
    /// Best candidate seen so far in the current step's window (frame +
    /// detection + quality), replaced whenever a higher-scoring one arrives.
    private nonisolated(unsafe) var bestCandidate: (pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, quality: FaceQualityResult)?
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
        currentStepIndex = 0
        poseHoldFrames = 0
        bestCandidate = nil
        frontalAvatar = nil
        relaxedThisStep = false
        pendingUserId = nil
        resetQualityThresholds()
        hasLiveFace = false
        liveYawDegrees = 0
        livePitchDegrees = 0
        state = .preparing

        let user = repository.registerUser(firstName: trimmedFirstName, lastName: trimmedLastName)
        guard let userId = user.id else {
            state = .failed(.storageError)
            return
        }
        pendingUserId = userId

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
        if let userId = pendingUserId, collectedEmbeddings.count < poseSteps.count {
            repository.deleteUser(id: userId)
            Log("Enrollment: cancelled for user \(userId), had \(collectedEmbeddings.count) embedding(s) — deleted partial user")
        }
        pendingUserId = nil
        collectedEmbeddings = []
        bestCandidate = nil
        frontalAvatar = nil
        hasLiveFace = false
        state = .idle
    }

    func retry() {
        // The failed attempt's partial user record is still in the store —
        // startEnrollment() re-registers the same name, so it must be
        // deleted first or validateNameBeforeStarting() rejects it as a
        // duplicate and re-fails immediately without ever reopening the
        // camera.
        if let userId = pendingUserId {
            repository.deleteUser(id: userId)
            pendingUserId = nil
        }
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
        bestCandidate = nil
        frontalAvatar = nil
        hasLiveFace = false
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
            DispatchQueue.main.async { self.hasLiveFace = false }
            evaluateStepDeadlines(sawUsableFrame: false)
            return
        }

        let quality = qualityChecker.check(detection: detections[0], pixelBuffer: pixelBuffer)
        guard quality.isAcceptable else {
            DispatchQueue.main.async { self.hasLiveFace = false }
            evaluateStepDeadlines(sawUsableFrame: false)
            return
        }

        // Strict completeness gate — runs after the existing box/sharpness
        // check, before this frame is eligible as a capture candidate. See
        // FaceCaptureValidator.swift for what this catches and why.
        guard FaceCaptureValidator.isFaceCaptureValid(face: detections[0], frame: pixelBuffer) == nil else {
            DispatchQueue.main.async { self.hasLiveFace = false }
            evaluateStepDeadlines(sawUsableFrame: false)
            return
        }

        let step = poseSteps[currentStepIndex]
        let poseMatches = isPoseInRange(step: step, quality: quality)

        DispatchQueue.main.async {
            self.liveYawDegrees = quality.yawDegrees
            self.livePitchDegrees = quality.pitchDegrees
            self.hasLiveFace = true
        }

        if poseMatches {
            poseHoldFrames += 1
        } else {
            poseHoldFrames = 0
        }

        // Track the best-scoring candidate seen this window regardless of
        // exact pose match — guarantees the window always has *something*
        // to fall back on when the deadline hits.
        if bestCandidate == nil || quality.qualityScore > bestCandidate!.quality.qualityScore {
            bestCandidate = (pixelBuffer, detections[0], quality)
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

    /// True if the quality result's yaw/pitch estimate falls inside the
    /// current step's target range. Steps with no strict target (nil range)
    /// are satisfied by any acceptable-quality frame.
    private nonisolated func isPoseInRange(step: EnrollmentPoseStep, quality: FaceQualityResult) -> Bool {
        if let yawRange = step.targetYawDegrees, !yawRange.contains(quality.yawDegrees) {
            return false
        }
        if let pitchRange = step.targetPitchDegrees, !pitchRange.contains(quality.pitchDegrees) {
            return false
        }
        return true
    }

    /// Applies the progressive-relaxation / best-of-window / hard-timeout
    /// rules described in the header, called once per rejected-or-pending frame.
    private nonisolated func evaluateStepDeadlines(sawUsableFrame: Bool) {
        let elapsed = Self.monotonicNow() - stepStartedAt

        if !relaxedThisStep && elapsed >= relaxAfterSeconds {
            relaxedThisStep = true
            relaxQualityThresholds()
        }

        if elapsed >= stepWindowSeconds, let candidate = bestCandidate {
            captureStep(using: candidate)
            return
        }

        if elapsed >= stepHardTimeoutSeconds {
            if let candidate = bestCandidate {
                captureStep(using: candidate)
            } else {
                // Nothing usable at all for this whole step — fail the step
                // explicitly rather than spinning forever.
                DispatchQueue.main.async {
                    self.state = .failed(.poorQuality(.lowConfidence))
                }
                isCapturingFrames = false
                cameraService.stop()
                cameraService.onFrame = nil
            }
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
            bestCandidate = nil
            return
        }

        collectedEmbeddings.append(embedding)

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
        }

        Log("Enrollment: step \(currentStepIndex) (\(step)) captured — \(collectedEmbeddings.count)/\(poseSteps.count) embeddings, quality=\(String(format: "%.2f", candidate.quality.qualityScore))")
        advanceToNextStep()
    }

    private nonisolated func advanceToNextStep() {
        bestCandidate = nil
        poseHoldFrames = 0
        relaxedThisStep = false
        resetQualityThresholds()

        currentStepIndex += 1
        stepStartedAt = Self.monotonicNow()

        guard currentStepIndex < poseSteps.count else {
            isCapturingFrames = false
            cameraService.stop()
            cameraService.onFrame = nil
            finishEnrollment()
            return
        }

        DispatchQueue.main.async { self.publishAwaitingPose() }
    }

    private nonisolated func finishEnrollment() {
        guard let userId = pendingUserId else {
            DispatchQueue.main.async { self.state = .failed(.storageError) }
            return
        }

        let embeddings = collectedEmbeddings
        guard embeddings.count >= minimumUsableSamples else {
            DispatchQueue.main.async {
                self.repository.deleteUser(id: userId)
                self.state = .failed(.timedOut)
            }
            return
        }

        let success = repository.saveEnrollmentEmbeddings(userId: userId, embeddings: embeddings)
        Log("Enrollment: finishing for user \(userId) — \(embeddings.count) embeddings, persisted=\(success)")

        if success {
            // Only after the embeddings are durably stored — a rolled-back
            // enrollment must not leave an avatar file behind.
            if let avatar = frontalAvatar {
                repository.saveAvatar(userId: userId, image: avatar)
            }
        }

        DispatchQueue.main.async {
            if success {
                self.state = .enrollmentComplete
            } else {
                self.repository.deleteUser(id: userId)
                self.state = .failed(.storageError)
            }
        }
    }

    // MARK: - Threshold relaxation

    private nonisolated func resetQualityThresholds() {
        qualityChecker.minFaceWidthPx = 240
        qualityChecker.maxFaceWidthRatio = 0.85
    }

    private nonisolated func relaxQualityThresholds() {
        qualityChecker.minFaceWidthPx = 180
        qualityChecker.maxFaceWidthRatio = 0.9
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
        case .awaitingPose(let step, _, _): return step.instructionKey
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
        case .duplicateFace: return L10n.FaceAuth.failureDuplicate
        case .timedOut: return L10n.FaceAuth.failureTimedOut
        }
    }
}
