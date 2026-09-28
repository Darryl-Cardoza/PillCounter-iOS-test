//
//  FaceRecognitionRepository.swift
//  PillCounter
//
//  Repository layer between the enrollment ViewModel and the DAOs
//  (FaceUserStore / FaceEmbeddingStore). The ViewModel never touches Core
//  Data directly — everything routes through here (spec section 11).
//

import Foundation
import CoreVideo
import UIKit

/// One registered user's id/name plus their stored embedding vectors,
/// unpacked once and held for the lifetime of an authentication session
/// (spec section 2/5: load once, reuse across frames — never re-query the
/// database on every camera frame).
struct RegisteredUserEmbeddings {
    let userId: String
    let userName: String
    let embeddings: [[Float]]
}

/// A face that already belongs to somebody else. Carries the name as well as
/// the id because the only caller — enrollment's duplicate prompt — has to
/// tell the user WHO it matched, and `checkDuplicateFace`'s loop already holds
/// the row, so a separate name lookup would be a second fetch for data we just
/// had in hand.
struct DuplicateFaceMatch: Equatable {
    let userId: String
    /// May be empty for a row with no stored name — the caller supplies its
    /// own fallback copy rather than this layer reaching for L10n.
    let userName: String
}

protocol FaceRecognitionRepositoryProtocol {
    func isNameTaken(_ name: String) -> Bool
    func registerUser(firstName: String, lastName: String) -> FaceUserEntity
    func generateEnrollmentEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, qualityScore: Float
    ) -> FaceEmbedding?
    func saveEnrollmentEmbeddings(userId: String, embeddings: [FaceEmbedding]) -> Bool
    func checkDuplicateFace(against embeddings: [FaceEmbedding], excludingUserId: String?) -> DuplicateFaceMatch?
    func deleteUser(id: String)

    /// Stores the enrollment thumbnail and points the user row at it. Call
    /// only once the user's embeddings are durably persisted — an avatar for a
    /// rolled-back enrollment would outlive the user it belongs to.
    func saveAvatar(userId: String, image: UIImage)

    /// The stored enrollment thumbnail, or nil when the user has none (enrolled
    /// before avatars existed, capture failed, or the file went missing).
    func loadAvatar(userId: String) -> UIImage?

    /// Loads every active user's stored embeddings once, for reuse across
    /// an entire authentication session (spec section 2/5).
    func loadActiveEnrollments() -> [RegisteredUserEmbeddings]

    /// Generates a fresh embedding from a live camera frame during
    /// authentication. Identical pipeline to `generateEnrollmentEmbedding`
    /// (same aligner/SFace instances) — spec section 3/16 requires
    /// enrollment and authentication to never diverge in preprocessing.
    func generateAuthenticationEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult
    ) -> FaceEmbedding?

    /// 1:N identification of `embedding` against the already-loaded
    /// `registeredUsers` snapshot. Pure/offline — no database access, so it
    /// can run once per authentication frame without added I/O cost (spec
    /// section 6). Returns nil if no user's candidate score reaches
    /// `FaceRecognitionConfig.shared.acceptanceThreshold` (spec section 7/10
    /// — never returns "closest anyway").
    func identify(
        embedding: [Float], among registeredUsers: [RegisteredUserEmbeddings]
    ) -> FrameIdentification
}

final class FaceRecognitionRepository: FaceRecognitionRepositoryProtocol {

    static let shared = FaceRecognitionRepository()

    private let userStore: FaceUserStore
    private let embeddingStore: FaceEmbeddingStore
    private let avatarStore: FaceAvatarStore
    private let aligner: FaceAligner
    private let sface: SFaceEmbeddingService

    /// Optional-duplicate-check extension point (spec section 9): compare
    /// newly captured enrollment embeddings against every existing user's
    /// stored embeddings. Kept configurable rather than hardcoded — callers
    /// decide whether/when to invoke `checkDuplicateFace`. Not wired into
    /// `saveEnrollmentEmbeddings` automatically, so enrollment behavior is
    /// unchanged until a caller opts in.
    /// Same cosine range as FaceRecognitionConfig.acceptanceThreshold (0.38
    /// reference default) — was 0.75, which is unreachable for genuine SFace
    /// same-identity pairs and meant duplicate detection could never fire.
    var duplicateSimilarityThreshold: Float = 0.45

    init(
        userStore: FaceUserStore = .shared,
        embeddingStore: FaceEmbeddingStore = .shared,
        avatarStore: FaceAvatarStore = .shared,
        aligner: FaceAligner = .shared,
        sface: SFaceEmbeddingService = .shared
    ) {
        self.userStore = userStore
        self.embeddingStore = embeddingStore
        self.avatarStore = avatarStore
        self.aligner = aligner
        self.sface = sface
    }

    // MARK: - User registration

    func isNameTaken(_ name: String) -> Bool {
        userStore.isNameTaken(name)
    }

    func registerUser(firstName: String, lastName: String) -> FaceUserEntity {
        userStore.insertUser(id: UUID().uuidString, firstName: firstName, lastName: lastName)
    }

    func deleteUser(id: String) {
        embeddingStore.deleteEmbeddingsForUser(userId: id)
        // FaceUserStore.deleteUser removes the avatar file alongside the row,
        // so the image can never outlive the user regardless of caller.
        userStore.deleteUser(id: id)
    }

    // MARK: - Enrollment avatar

    func saveAvatar(userId: String, image: UIImage) {
        guard let filename = avatarStore.save(userId: userId, image: image) else {
            // Writing the image failed, so there is no filename worth storing —
            // the row keeps a nil photo_path and renders the placeholder.
            AppLogger.shared.warn("Repository: avatar write failed for user \(userId)")
            return
        }
        userStore.setPhotoPath(id: userId, filename: filename)
    }

    func loadAvatar(userId: String) -> UIImage? {
        guard let user = userStore.getUser(id: userId) else { return nil }
        return avatarStore.loadImage(filename: user.photo_path)
    }

    // MARK: - Embedding generation

    /// Aligns the detected face and runs SFace on it. Returns nil if
    /// alignment or embedding extraction fails — caller discards the sample
    /// and keeps capturing (spec section 15: "SFace failure → discard
    /// current sample and continue").
    func generateEnrollmentEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, qualityScore: Float
    ) -> FaceEmbedding? {
        guard let aligned = aligner.align(pixelBuffer: pixelBuffer, detection: detection) else { return nil }
        guard let embedding = sface.extractEmbedding(alignedFace: aligned) else { return nil }
        return FaceEmbedding(vector: embedding.vector, qualityScore: qualityScore)
    }

    // MARK: - Persistence

    /// Persists all collected embeddings for a user. Returns false (and
    /// persists nothing) if ANY embedding fails to write — enrollment must
    /// only report success once every required sample is durably stored
    /// (spec section 15/10).
    func saveEnrollmentEmbeddings(userId: String, embeddings: [FaceEmbedding]) -> Bool {
        guard !embeddings.isEmpty else { return false }
        guard userStore.getUser(id: userId) != nil else { return false }

        var inserted: [String] = []
        for embedding in embeddings {
            let base64 = embedding.packedBase64()
            let id = UUID().uuidString
            embeddingStore.insertEmbedding(
                id: id, userId: userId, embeddingBase64: base64, qualityScore: embedding.qualityScore
            )
            // insertEmbedding has no throwing path today (Core Data save
            // failures are logged, not surfaced) — verify the row landed
            // rather than trusting the call succeeded, so a silent Core
            // Data failure still fails enrollment instead of reporting
            // success with fewer rows than required.
            inserted.append(id)
        }

        let persisted = embeddingStore.getEmbeddingsForUser(userId: userId)
        guard persisted.count >= embeddings.count else {
            // Storage failure: roll back partial writes so a failed
            // enrollment doesn't leave an orphaned user with too few samples.
            embeddingStore.deleteEmbeddingsForUser(userId: userId)
            return false
        }
        return true
    }

    // MARK: - Authentication

    func loadActiveEnrollments() -> [RegisteredUserEmbeddings] {
        let allUsers = userStore.getAllUsers(activeOnly: true)
        AppLogger.shared.info("Repository: \(allUsers.count) active user row(s) in store")

        return allUsers.compactMap { user in
            guard let userId = user.id, let userName = user.name else {
                AppLogger.shared.warn("Repository: skipping user row with nil id/name")
                return nil
            }
            let stored = embeddingStore.getEmbeddingsForUser(userId: userId)
            // userId alone identifies the row for diagnostics — userName is PII
            // and doesn't need to be persisted to the log file.
            AppLogger.shared.debug("Repository: user \(userId) has \(stored.count) stored embedding row(s)")

            let vectors = stored.compactMap { entity -> [Float]? in
                guard let base64 = entity.embedding, !base64.isEmpty else {
                    // An empty string here is FieldEncryptionManager's fail-safe
                    // output when decrypt() couldn't open real ciphertext (see
                    // NSManagedObject+Encryption.decryptEncryptedFieldsInPlace) —
                    // it is NOT a valid zero-length embedding. unpack("") would
                    // otherwise happily return [] (empty Data decodes fine),
                    // which would sail through as a "valid" 0-dimension vector
                    // and silently score 0 against everything forever. Reject
                    // it explicitly instead.
                    AppLogger.shared.warn("Repository: embedding row for \(userId) has nil/empty payload — likely a decrypt failure, skipping")
                    return nil
                }
                guard let vector = FaceEmbedding.unpack(base64: base64), !vector.isEmpty else {
                    AppLogger.shared.warn("Repository: embedding row for \(userId) failed to unpack (base64 len=\(base64.count)) — corrupted or undecryptable")
                    return nil
                }
                return vector
            }
            AppLogger.shared.debug("Repository: user \(userId) — \(vectors.count)/\(stored.count) embeddings unpacked, dims: \(vectors.map(\.count))")

            guard !vectors.isEmpty else { return nil }
            return RegisteredUserEmbeddings(userId: userId, userName: userName, embeddings: vectors)
        }
    }

    func generateAuthenticationEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult
    ) -> FaceEmbedding? {
        guard let aligned = aligner.align(pixelBuffer: pixelBuffer, detection: detection) else { return nil }
        return sface.extractEmbedding(alignedFace: aligned)
    }

    func identify(
        embedding: [Float], among registeredUsers: [RegisteredUserEmbeddings]
    ) -> FrameIdentification {
        let config = FaceRecognitionConfig.shared
        var bestUserId: String?
        var bestScore: Float = -1

        // One gate, deliberately — see FaceRecognitionConfig.acceptanceThreshold.
        // The absolute floor and runner-up margin that used to sit here were
        // compensating for a 0.38 threshold; they also made it impossible for
        // two people who genuinely share a face to ever unlock, which
        // enrollment now explicitly permits.
        var allScores: [(userName: String, score: Float)] = []

        for user in registeredUsers {
            let score = candidateScore(for: embedding, storedEmbeddings: user.embeddings, strategy: config.scoringStrategy)
            allScores.append((user.userName, score))
            if score > bestScore {
                bestScore = score
                bestUserId = user.userId
            }
        }

        let sortedLine = allScores.sorted { $0.score > $1.score }
            .map { "\($0.userName)=\(String(format: "%.3f", $0.score))" }
            .joined(separator: ", ")
        AppLogger.shared.debug("Repository: identify — scores [\(sortedLine)] threshold=\(config.acceptanceThreshold)")

        guard let bestUserId, bestScore >= config.acceptanceThreshold else {
            // Highest score doesn't clear the threshold — report "no match",
            // never the closest-anyway user (spec section 7/10).
            AppLogger.shared.debug("Repository: identify — best=\(String(format: "%.3f", bestScore)) — rejected")
            return FrameIdentification(userId: nil, score: bestScore)
        }
        return FrameIdentification(userId: bestUserId, score: bestScore)
    }

    /// Isolated so the strategy can change to an aggregate score later
    /// without touching `identify` (spec section 6).
    private func candidateScore(
        for embedding: [Float], storedEmbeddings: [[Float]], strategy: CandidateScoringStrategy
    ) -> Float {
        guard !storedEmbeddings.isEmpty else { return -1 }
        let similarities = storedEmbeddings.map { FaceEmbedding.cosineSimilarity(embedding, $0) }

        switch strategy {
        case .bestSimilarity:
            return similarities.max() ?? -1
        case .averageSimilarity:
            return similarities.reduce(0, +) / Float(similarities.count)
        }
    }

    // MARK: - Optional duplicate check (extension point)

    /// Compares `embeddings` (typically the just-captured enrollment set)
    /// against every OTHER user's stored embeddings — active or
    /// deactivated. Returns the matching user if any pairwise cosine
    /// similarity meets `duplicateSimilarityThreshold`, else nil.
    /// Deliberately includes deactivated users: deactivation is a soft
    /// pause, not a release of that face for re-enrollment (see
    /// `FaceUserStore.isNameTaken`'s comment for the same rationale).
    ///
    /// Not called by `saveEnrollmentEmbeddings` itself — FaceEnrollmentViewModel
    /// calls this mid-capture, after `.center`, and gates enrollment on the
    /// result: a match pauses the pipeline behind a user-facing duplicate
    /// prompt (`runDuplicateCheck`/`duplicateMatch`) before persisting.
    ///
    /// Core Data here is `viewContext`-backed, so this must be called on the
    /// main actor — see the note in FaceEnrollmentViewModel.runDuplicateCheck.
    func checkDuplicateFace(against embeddings: [FaceEmbedding], excludingUserId: String?) -> DuplicateFaceMatch? {
        guard !embeddings.isEmpty else { return nil }
        // This now runs mid-capture, in front of a modal the user is waiting
        // on, so the real device cost matters — log it rather than guess.
        let startedAt = ProcessInfo.processInfo.systemUptime
        let candidates = userStore.getAllUsers(activeOnly: false).filter { $0.id != excludingUserId }
        defer {
            let elapsedMs = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            AppLogger.shared.info("Repository: duplicate check scanned \(candidates.count) user(s) in \(String(format: "%.0f", elapsedMs))ms")
        }

        for user in candidates {
            guard let userId = user.id else { continue }
            let stored = embeddingStore.getEmbeddingsForUser(userId: userId)
            for storedEntity in stored {
                guard let base64 = storedEntity.embedding,
                      let storedVector = FaceEmbedding.unpack(base64: base64) else { continue }
                for candidate in embeddings {
                    if FaceEmbedding.cosineSimilarity(candidate.vector, storedVector) >= duplicateSimilarityThreshold {
                        return DuplicateFaceMatch(userId: userId, userName: user.name ?? "")
                    }
                }
            }
        }
        return nil
    }
}
