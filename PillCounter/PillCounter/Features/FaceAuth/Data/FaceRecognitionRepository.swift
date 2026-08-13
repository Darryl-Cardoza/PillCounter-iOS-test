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

/// One registered user's id/name plus their stored embedding vectors,
/// unpacked once and held for the lifetime of an authentication session
/// (spec section 2/5: load once, reuse across frames — never re-query the
/// database on every camera frame).
struct RegisteredUserEmbeddings {
    let userId: String
    let userName: String
    let embeddings: [[Float]]
}

protocol FaceRecognitionRepositoryProtocol {
    func isNameTaken(_ name: String) -> Bool
    func registerUser(name: String) -> FaceUserEntity
    func generateEnrollmentEmbedding(
        pixelBuffer: CVPixelBuffer, detection: FaceDetectionResult, qualityScore: Float
    ) -> FaceEmbedding?
    func saveEnrollmentEmbeddings(userId: String, embeddings: [FaceEmbedding]) -> Bool
    func checkDuplicateFace(against embeddings: [FaceEmbedding], excludingUserId: String?) -> String?
    func deleteUser(id: String)

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
        aligner: FaceAligner = .shared,
        sface: SFaceEmbeddingService = .shared
    ) {
        self.userStore = userStore
        self.embeddingStore = embeddingStore
        self.aligner = aligner
        self.sface = sface
    }

    // MARK: - User registration

    func isNameTaken(_ name: String) -> Bool {
        userStore.isNameTaken(name)
    }

    func registerUser(name: String) -> FaceUserEntity {
        userStore.insertUser(id: UUID().uuidString, name: name)
    }

    func deleteUser(id: String) {
        embeddingStore.deleteEmbeddingsForUser(userId: id)
        userStore.deleteUser(id: id)
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
        Log("Repository: \(allUsers.count) active user row(s) in store")

        return allUsers.compactMap { user in
            guard let userId = user.id, let userName = user.name else {
                Log("Repository: skipping user row with nil id/name")
                return nil
            }
            let stored = embeddingStore.getEmbeddingsForUser(userId: userId)
            Log("Repository: user \(userId) (\(userName)) has \(stored.count) stored embedding row(s)")

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
                    Log("Repository: embedding row for \(userId) has nil/empty payload — likely a decrypt failure, skipping")
                    return nil
                }
                guard let vector = FaceEmbedding.unpack(base64: base64), !vector.isEmpty else {
                    Log("Repository: embedding row for \(userId) failed to unpack (base64 len=\(base64.count)) — corrupted or undecryptable")
                    return nil
                }
                return vector
            }
            Log("Repository: user \(userId) — \(vectors.count)/\(stored.count) embeddings unpacked, dims: \(vectors.map(\.count))")

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
        var runnerUpScore: Float = -1

        Log("Repository: identify — live embedding dim=\(embedding.count), comparing against \(registeredUsers.count) user(s)")

        // TEMP DEBUG — every user's score, unsorted collection first.
        var allScores: [(userId: String, userName: String, score: Float)] = []

        for user in registeredUsers {
            let score = candidateScore(for: embedding, storedEmbeddings: user.embeddings, strategy: config.scoringStrategy)
            Log("Repository: user \(user.userId) — \(user.embeddings.count) stored embedding(s), dims=\(user.embeddings.map(\.count)), score=\(String(format: "%.3f", score))")
            allScores.append((user.userId, user.userName, score))
            if score > bestScore {
                // Previous best is now a different user's runner-up score.
                runnerUpScore = bestScore
                bestScore = score
                bestUserId = user.userId
            } else if score > runnerUpScore {
                runnerUpScore = score
            }
        }

        // TEMP DEBUG — full sorted distribution, remove after root-causing
        // bug 1/bug 2. Look at the gap between #1 and #2 here, and whether
        // #1 clears acceptanceThreshold at all.
        let sorted = allScores.sorted { $0.score > $1.score }
        let sortedLine = sorted.map { "\($0.userName)=\(String(format: "%.3f", $0.score))" }.joined(separator: ", ")
        Log("DEBUG allScores (sorted): [\(sortedLine)]")

        let margin = bestScore - max(runnerUpScore, 0)
        let thresholdPass = bestScore >= config.acceptanceThreshold
        let marginPass = margin >= config.minMarginOverRunnerUp
        Log("DEBUG gate: threshold=\(config.acceptanceThreshold) thresholdPass=\(thresholdPass) marginRequired=\(config.minMarginOverRunnerUp) marginActual=\(String(format: "%.3f", margin)) marginPass=\(marginPass)")

        guard let bestUserId, thresholdPass, marginPass else {
            // Highest score doesn't clear the threshold, or it isn't clearly
            // ahead of the next-best DIFFERENT user — report "no match",
            // never the closest-anyway user (spec section 7/10).
            Log("Repository: identify — best=\(String(format: "%.3f", bestScore)) runnerUp=\(String(format: "%.3f", runnerUpScore)) margin=\(String(format: "%.3f", margin)) — rejected")
            Log("DEBUG return: userId=nil (gate failed)")
            return FrameIdentification(userId: nil, score: bestScore)
        }
        Log("DEBUG return: userId=\(bestUserId) (gate passed)")
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
    /// against every OTHER active user's stored embeddings. Returns the
    /// matching user's id if any pairwise cosine similarity meets
    /// `duplicateSimilarityThreshold`, else nil.
    ///
    /// Not called automatically by `saveEnrollmentEmbeddings` — the caller
    /// (ViewModel) decides whether to run this before persisting, so this
    /// first implementation can ship without gating enrollment on it.
    func checkDuplicateFace(against embeddings: [FaceEmbedding], excludingUserId: String?) -> String? {
        guard !embeddings.isEmpty else { return nil }
        let candidates = userStore.getAllUsers().filter { $0.id != excludingUserId }

        for user in candidates {
            guard let userId = user.id else { continue }
            let stored = embeddingStore.getEmbeddingsForUser(userId: userId)
            for storedEntity in stored {
                guard let base64 = storedEntity.embedding,
                      let storedVector = FaceEmbedding.unpack(base64: base64) else { continue }
                for candidate in embeddings {
                    if FaceEmbedding.cosineSimilarity(candidate.vector, storedVector) >= duplicateSimilarityThreshold {
                        return userId
                    }
                }
            }
        }
        return nil
    }
}
