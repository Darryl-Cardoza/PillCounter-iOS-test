//
//  FaceRecognitionRepositoryTests.swift
//  PillCounterTests
//
//  Repository behavior around persistence guarantees — "only report success
//  once every embedding is durably stored" — exercised against the real
//  FaceUserStore/FaceEmbeddingStore (matches the rest of the Stores test
//  suite; no DI seam for Core Data in this project, see SQLiteCoreDataStack).
//

import Testing
@testable import PillCounter

@Suite(.serialized)
struct FaceRecognitionRepositoryTests {

    @Test func registerUserCreatesActiveUser() {
        let repo = FaceRecognitionRepository.shared
        let name = "Repo Register \(UUID().uuidString.prefix(8))"
        let user = repo.registerUser(name: name)
        defer { repo.deleteUser(id: user.id ?? "") }

        #expect(user.name == name)
        #expect(user.is_active == true)
    }

    @Test func isNameTakenReflectsRegisteredUsers() {
        let repo = FaceRecognitionRepository.shared
        let name = "Repo Dup \(UUID().uuidString.prefix(8))"
        #expect(repo.isNameTaken(name) == false)

        let user = repo.registerUser(name: name)
        defer { repo.deleteUser(id: user.id ?? "") }

        #expect(repo.isNameTaken(name) == true)
    }

    @Test func saveEnrollmentEmbeddingsPersistsAllSamples() {
        let repo = FaceRecognitionRepository.shared
        let user = repo.registerUser(name: "Repo Save \(UUID().uuidString.prefix(8))")
        guard let userId = user.id else {
            Issue.record("expected user id")
            return
        }
        defer { repo.deleteUser(id: userId) }

        let embeddings = (0..<5).map { i in
            FaceEmbedding(vector: [Float(i), Float(i) + 1, Float(i) + 2], qualityScore: 0.8)
        }

        let success = repo.saveEnrollmentEmbeddings(userId: userId, embeddings: embeddings)

        #expect(success == true)
        #expect(FaceEmbeddingStore.shared.getEmbeddingsForUser(userId: userId).count == 5)
    }

    @Test func saveEnrollmentEmbeddingsFailsForUnknownUser() {
        let repo = FaceRecognitionRepository.shared
        let embeddings = [FaceEmbedding(vector: [1, 2, 3], qualityScore: 0.5)]

        let success = repo.saveEnrollmentEmbeddings(userId: "does-not-exist", embeddings: embeddings)

        #expect(success == false)
    }

    @Test func saveEnrollmentEmbeddingsFailsForEmptyList() {
        let repo = FaceRecognitionRepository.shared
        let user = repo.registerUser(name: "Repo Empty \(UUID().uuidString.prefix(8))")
        guard let userId = user.id else {
            Issue.record("expected user id")
            return
        }
        defer { repo.deleteUser(id: userId) }

        let success = repo.saveEnrollmentEmbeddings(userId: userId, embeddings: [])

        #expect(success == false)
    }

    @Test func checkDuplicateFaceFindsHighSimilarityMatch() {
        let repo = FaceRecognitionRepository.shared
        repo.duplicateSimilarityThreshold = 0.99

        let existingUser = repo.registerUser(name: "Repo Existing \(UUID().uuidString.prefix(8))")
        guard let existingId = existingUser.id else {
            Issue.record("expected user id")
            return
        }
        defer { repo.deleteUser(id: existingId) }

        let vector: [Float] = [1, 0, 0, 0]
        let stored = FaceEmbedding(vector: vector, qualityScore: 0.9)
        _ = repo.saveEnrollmentEmbeddings(userId: existingId, embeddings: [stored])

        let candidate = FaceEmbedding(vector: vector, qualityScore: 0.9)
        let match = repo.checkDuplicateFace(against: [candidate], excludingUserId: nil)

        #expect(match == existingId)
    }

    @Test func checkDuplicateFaceReturnsNilWhenNoMatch() {
        let repo = FaceRecognitionRepository.shared
        repo.duplicateSimilarityThreshold = 0.75

        let existingUser = repo.registerUser(name: "Repo NoMatch \(UUID().uuidString.prefix(8))")
        guard let existingId = existingUser.id else {
            Issue.record("expected user id")
            return
        }
        defer { repo.deleteUser(id: existingId) }

        let stored = FaceEmbedding(vector: [1, 0, 0, 0], qualityScore: 0.9)
        _ = repo.saveEnrollmentEmbeddings(userId: existingId, embeddings: [stored])

        let candidate = FaceEmbedding(vector: [0, 1, 0, 0], qualityScore: 0.9)
        let match = repo.checkDuplicateFace(against: [candidate], excludingUserId: nil)

        #expect(match == nil)
    }
}
