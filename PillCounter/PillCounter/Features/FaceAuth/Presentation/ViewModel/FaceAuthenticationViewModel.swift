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
//  embed → identify → act on the very first frame that clears the
//  acceptance threshold. No multi-frame confirmation window — an earlier
//  version of this file added one, which is NOT present in either working
//  reference and was extra bug surface with no proven benefit. Do not
//  reintroduce it without first confirming the simple loop works end to end.
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

        let detections = detector.detect(pixelBuffer: pixelBuffer)
        Log("Authentication: frame — \(detections.count) face(s) detected")

        guard detections.count == 1 else {
            DispatchQueue.main.async {
                self.state = detections.isEmpty ? .detectingFace : .transientIssue(.multipleFaces)
            }
            return
        }

        DispatchQueue.main.async { self.state = .faceDetected }

        let quality = qualityChecker.check(detection: detections[0], pixelBuffer: pixelBuffer)
        guard quality.isAcceptable else {
            let reason = quality.reason ?? .lowConfidence
            DispatchQueue.main.async { self.state = .transientIssue(.poorQuality(reason)) }
            return
        }

        DispatchQueue.main.async { self.state = .generatingEmbedding }

        guard let embedding = repository.generateAuthenticationEmbedding(
            pixelBuffer: pixelBuffer, detection: detections[0]
        ) else {
            Log("Authentication: embedding generation failed for this frame")
            DispatchQueue.main.async { self.state = .detectingFace }
            return
        }

        DispatchQueue.main.async { self.state = .comparing }
        let identification = repository.identify(embedding: embedding.vector, among: registeredUsers)
        Log("Authentication: score=\(String(format: "%.3f", identification.score)) threshold=\(config.acceptanceThreshold) result=\(identification.userId != nil ? "PASS" : "no match")")

        guard let userId = identification.userId else {
            // No match on this frame — keep scanning, exactly like the
            // reference implementations (they never terminate on a single
            // no-match frame, only on an explicit Cancel).
            DispatchQueue.main.async { self.state = .detectingFace }
            return
        }

        authenticateAndStop(userId: userId)
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
    }

    private nonisolated static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - UI-facing instruction text (never reveals scores/candidates)

    var instructionText: String {
        switch state {
        case .idle: return L10n.FaceAuth.authIdle
        case .startingCamera: return L10n.FaceAuth.instructionPreparing
        case .detectingFace: return L10n.FaceAuth.authDetecting
        case .faceDetected: return L10n.FaceAuth.authFaceDetected
        case .qualityChecking: return L10n.FaceAuth.authChecking
        case .generatingEmbedding, .comparing, .candidateFound: return L10n.FaceAuth.authVerifying
        case .confirmingIdentity: return L10n.FaceAuth.authVerifying
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
