//
//  FaceAuthenticationViewModel.swift
//  PillCounter
//
//  Drives AuthenticationState. Loads active registered users' embeddings
//  ONCE per session (spec section 2/5) and reuses that snapshot for every
//  frame — no per-frame database access.
//
//  Deliberately a SIMPLE per-frame loop, matching this app's proven-working
//  Android (FaceAuthViewModel.runVerify) and Python (standalone_face_tf.py
//  cmd_verify) reference implementations exactly: detect → quality gate →
//  embed → identify, with a minimal 2-consecutive-frame agreement check
//  before accepting.
//
//  That confirmation window was previously removed for being unproven bug
//  surface absent from both references. It is back deliberately, with
//  evidence this time: an unenrolled person was measured false-accepting at
//  cosine 0.391 against a single enrolled user (who scores 0.715), so a lone
//  frame is demonstrably not trustworthy on its own. Kept as small as
//  possible — a count and a userId, reset on any disagreement, no timers or
//  score accumulation — since the earlier version's problem was complexity,
//  not the idea. The absolute-score floor in FaceRecognitionConfig is the
//  primary gate; this only removes single-lucky-frame accepts.
//
//  The hot per-frame path (`handleFrame` and everything it calls) runs
//  `nonisolated` on the camera session queue and only hops to the main actor
//  to publish `state`.
//

import Foundation
import CoreVideo
import Combine

@MainActor
final class FaceAuthenticationViewModel: ObservableObject {

    @Published var state: AuthenticationState = .idle

    private let repository: FaceRecognitionRepositoryProtocol
    private let detector: YuNetDetectorService
    private let qualityChecker: FaceQualityChecker
    private let config: FaceRecognitionConfig
    let cameraService: FaceCameraService
    /// Keeps the nested camera service's @Published changes flowing out of
    /// this view model — see the note in `init`.
    private var cameraServiceSubscription: AnyCancellable?

    /// Called once, on the main actor, when authentication succeeds.
    var onAuthenticated: ((String, String) -> Void)?

    // MARK: - Session-cached data (spec section 2/5)

    private nonisolated(unsafe) var registeredUsers: [RegisteredUserEmbeddings] = []

    // MARK: - Per-frame pipeline state (camera-queue-only)

    private nonisolated(unsafe) var isProcessing = false
    private nonisolated(unsafe) var isRunning = false
    private nonisolated(unsafe) var lastProcessedAt: TimeInterval = 0

    /// Consecutive frames that have identified `pendingMatchUserId`. Accept
    /// only once this reaches `requiredConsecutiveMatches`; any no-match or a
    /// different user resets both.
    private let requiredConsecutiveMatches = 2
    private nonisolated(unsafe) var pendingMatchUserId: String?
    private nonisolated(unsafe) var consecutiveMatchCount = 0

    /// Total budget for one scan attempt. Without it an unrecognized person
    /// scans forever with no outcome — they must be told, not left guessing.
    /// One continuous budget from scan start, deliberately NOT reset when a
    /// face leaves and re-enters, so stepping in and out of frame can't extend
    /// the attempt indefinitely.
    private let scanBudgetSeconds: TimeInterval = 7.0
    private nonisolated(unsafe) var scanStartedAt: TimeInterval = 0

    /// Minimum time a guidance message stays on screen before another may
    /// replace it. Detection can flicker between adjacent frames, and without
    /// a floor the guidance copy strobes against the steady scanning copy.
    private let minimumMessageDisplaySeconds: TimeInterval = 0.8
    private nonisolated(unsafe) var guidanceShownAt: TimeInterval = 0

    init(
        repository: FaceRecognitionRepositoryProtocol = FaceRecognitionRepository.shared,
        detector: YuNetDetectorService = .shared,
        qualityChecker: FaceQualityChecker = .shared,
        config: FaceRecognitionConfig = .shared,
        cameraService: FaceCameraService = FaceCameraService()
    ) {
        self.repository = repository
        self.detector = detector
        self.qualityChecker = qualityChecker
        self.config = config
        self.cameraService = cameraService

        // A nested ObservableObject does not propagate its own changes, so the
        // view (which now reads the camera through this view model rather than
        // observing it directly) would not re-render when `cameraPosition` or
        // `currentCameraOrientation` changes — leaving the preview's connection
        // un-rotated after a flip. Forward them explicitly.
        cameraServiceSubscription = cameraService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - Lifecycle

    func startAuthentication() {
        state = .startingCamera
        lastProcessedAt = 0
        pendingMatchUserId = nil
        consecutiveMatchCount = 0
        scanStartedAt = Self.monotonicNow()
        guidanceShownAt = 0
        resetQualityThresholds()

        let loaded = repository.loadActiveEnrollments()
        registeredUsers = loaded
        Log("Authentication: loaded \(loaded.count) registered user(s), \(loaded.reduce(0) { $0 + $1.embeddings.count }) total embeddings")
        guard !loaded.isEmpty else {
            state = .failed(.noRegisteredUsers)
            Log("Authentication: no registered users — aborting")
            return
        }

        cameraService.onFrame = { [weak self] pixelBuffer in
            self?.handleFrame(pixelBuffer)
        }
        isRunning = true
        cameraService.start()
        state = .detectingFace
        Log("Authentication: camera started")
    }

    func stopAuthentication() {
        isRunning = false
        cameraService.stop()
        cameraService.onFrame = nil
        Log("Authentication: stopped")
    }

    func retry() {
        startAuthentication()
    }

    // MARK: - Frame pipeline (spec section 3/13)

    private nonisolated func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRunning, !isProcessing else { return }

        // Rate-limit independent of camera FPS — never run concurrent
        // inference (spec section 13). 150ms matches the Android reference's
        // AUTO_VERIFY_FRAME_INTERVAL_MS exactly.
        let now = Self.monotonicNow()
        guard now - lastProcessedAt >= config.minInferenceIntervalSeconds else { return }
        lastProcessedAt = now

        isProcessing = true
        defer { isProcessing = false }

        guard now - scanStartedAt < scanBudgetSeconds else {
            failScanAsUnrecognized()
            return
        }

        let detections = detector.detect(pixelBuffer: pixelBuffer)
        Log("Authentication: frame — \(detections.count) face(s) detected")

        guard detections.count == 1 else {
            publishGuidance(
                detections.isEmpty ? .detectingFace : .transientIssue(.multipleFaces), at: now
            )
            return
        }

        let quality = qualityChecker.check(detection: detections[0], pixelBuffer: pixelBuffer)
        guard quality.isAcceptable else {
            let reason = quality.reason ?? .lowConfidence
            publishGuidance(.transientIssue(.poorQuality(reason)), at: now)
            return
        }

        // Published only once the frame is actually usable, so it can't
        // overwrite a guidance message that is still inside its display floor.
        DispatchQueue.main.async { self.state = .faceDetected }

        DispatchQueue.main.async { self.state = .generatingEmbedding }

        guard let embedding = repository.generateAuthenticationEmbedding(
            pixelBuffer: pixelBuffer, detection: detections[0]
        ) else {
            // Stay on the scanning copy — this is an internal per-frame
            // failure, not something the user can act on.
            Log("Authentication: embedding generation failed for this frame")
            return
        }

        DispatchQueue.main.async { self.state = .comparing }
        let identification = repository.identify(embedding: embedding.vector, among: registeredUsers)
        Log("Authentication: score=\(String(format: "%.3f", identification.score)) threshold=\(config.acceptanceThreshold) result=\(identification.userId != nil ? "PASS" : "no match")")

        guard let userId = identification.userId else {
            // No match on this frame — keep scanning until the scan budget
            // expires. Deliberately does NOT publish a state change: a face
            // is present and being processed, so the scanning copy stays put.
            // Bouncing back to `.detectingFace` here is what made an
            // unrecognized user's text strobe several times a second.
            pendingMatchUserId = nil
            consecutiveMatchCount = 0
            return
        }

        if pendingMatchUserId == userId {
            consecutiveMatchCount += 1
        } else {
            pendingMatchUserId = userId
            consecutiveMatchCount = 1
        }

        guard consecutiveMatchCount >= requiredConsecutiveMatches else {
            Log("Authentication: match on \(userId) awaiting confirmation (\(consecutiveMatchCount)/\(requiredConsecutiveMatches))")
            let passCount = consecutiveMatchCount
            let required = requiredConsecutiveMatches
            DispatchQueue.main.async {
                self.state = .confirmingIdentity(passCount: passCount, required: required)
            }
            return
        }

        authenticateAndStop(userId: userId)
    }

    /// Publishes an actionable guidance state, but not sooner than
    /// `minimumMessageDisplaySeconds` after the previous one — detection can
    /// flicker frame to frame, and without this floor the guidance copy
    /// strobes against the steady scanning copy.
    private nonisolated func publishGuidance(_ next: AuthenticationState, at now: TimeInterval) {
        guard now - guidanceShownAt >= minimumMessageDisplaySeconds else { return }
        guidanceShownAt = now
        DispatchQueue.main.async { self.state = next }
    }

    /// Ends the attempt once the scan budget is spent. An unrecognized person
    /// gets a definite outcome with Try Again / Cancel instead of an endless
    /// scanning screen.
    private nonisolated func failScanAsUnrecognized() {
        isRunning = false
        cameraService.stop()
        cameraService.onFrame = nil

        Log("Authentication: scan budget of \(scanBudgetSeconds)s expired — no match")
        DispatchQueue.main.async { self.state = .failed(.unknownUser) }
    }

    private nonisolated func authenticateAndStop(userId: String) {
        guard let user = registeredUsers.first(where: { $0.userId == userId }) else {
            DispatchQueue.main.async { self.state = .failed(.unknownUser) }
            return
        }

        // Stop recognition immediately on success (spec section 13/14).
        isRunning = false
        cameraService.stop()
        cameraService.onFrame = nil

        Log("Authentication: SUCCESS for user \(user.userId)")
        DispatchQueue.main.async {
            self.state = .authenticated(userName: user.userName)
            self.onAuthenticated?(user.userId, user.userName)
        }
    }

    private nonisolated func resetQualityThresholds() {
        qualityChecker.minFaceWidthPx = 240
        qualityChecker.maxFaceWidthRatio = 0.85
        // Center-offset gate is enrollment-only — disable it here since
        // FaceQualityChecker.shared is a singleton shared with enrollment.
        qualityChecker.maxCenterOffsetXRatio = 1.0
        qualityChecker.maxCenterOffsetYRatio = 1.0
    }

    private nonisolated static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - UI-facing instruction text (never reveals scores/candidates)

    /// Copy for the current state. Every stage of an in-progress scan
    /// deliberately maps to the SAME string: the pipeline publishes 4-5 state
    /// changes per processed frame at ~6.7 frames/sec, so mapping each stage to
    /// its own copy made the text strobe — worst for an unrecognized person,
    /// who loops detect -> compare -> no match indefinitely. Internal stages
    /// are for logs and tests, not for the user to read.
    var instructionText: String {
        switch state {
        case .idle: return L10n.FaceAuth.authIdle
        case .startingCamera: return L10n.FaceAuth.instructionPreparing
        case .detectingFace: return L10n.FaceAuth.authDetecting
        case .faceDetected, .qualityChecking, .generatingEmbedding,
             .comparing, .candidateFound, .confirmingIdentity:
            return L10n.FaceAuth.authVerifying
        case .authenticated(let name): return String(format: L10n.FaceAuth.authWelcome, name)
        case .transientIssue(let reason): return failureText(reason)
        case .failed(let reason): return failureText(reason)
        }
    }

    private func failureText(_ reason: AuthenticationFailureReason) -> String {
        switch reason {
        case .noFace: return L10n.FaceAuth.authNoFace
        case .multipleFaces: return L10n.FaceAuth.authMultipleFaces
        case .poorQuality: return L10n.FaceAuth.authPoorQuality
        case .unknownUser: return L10n.FaceAuth.authUnknownUser
        case .embeddingGenerationFailed: return L10n.FaceAuth.failureEmbedding
        case .cameraError: return L10n.FaceAuth.failureCamera
        case .noRegisteredUsers: return L10n.FaceAuth.authNoRegisteredUsers
        }
    }
}
