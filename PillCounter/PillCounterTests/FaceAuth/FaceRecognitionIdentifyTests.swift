//
//  FaceRecognitionIdentifyTests.swift
//  PillCounterTests
//
//  Exercises FaceRecognitionRepository.identify / loadActiveEnrollments —
//  the 1:N comparison + threshold logic (spec sections 6/7/10). Runs
//  against the real Core Data stores (matches the rest of the FaceAuth test
//  suite; no DI seam for Core Data in this project).
//

import Foundation
import Testing
@testable import PillCounter

@Suite(.serialized)
struct FaceRecognitionIdentifyTests {

    @Test func identifyReturnsBestScoringUserWhenAboveThreshold() {
        let repo = FaceRecognitionRepository.shared
        let config = FaceRecognitionConfig.shared
        let originalThreshold = config.acceptanceThreshold
        config.acceptanceThreshold = 0.7
        defer { config.acceptanceThreshold = originalThreshold }

        let target: [Float] = [1, 0, 0, 0]
        let other: [Float] = [0, 1, 0, 0]

        let users = [
            RegisteredUserEmbeddings(userId: "userA", userName: "Alice", embeddings: [target]),
            RegisteredUserEmbeddings(userId: "userB", userName: "Bob", embeddings: [other]),
        ]

        let result = repo.identify(embedding: target, among: users)

        #expect(result.userId == "userA")
    }

    @Test func identifyReturnsNilWhenBestScoreBelowThreshold() {
        let repo = FaceRecognitionRepository.shared
        let config = FaceRecognitionConfig.shared
        let originalThreshold = config.acceptanceThreshold
        config.acceptanceThreshold = 0.99
        defer { config.acceptanceThreshold = originalThreshold }

        // Similar but not identical — cosine similarity < 0.99.
        let live: [Float] = [1, 0.05, 0, 0]
        let stored: [Float] = [1, 0, 0, 0]

        let users = [RegisteredUserEmbeddings(userId: "userA", userName: "Alice", embeddings: [stored])]

        let result = repo.identify(embedding: live, among: users)

        #expect(result.userId == nil)
    }

    @Test func identifyNeverPicksClosestUserBelowThreshold() {
        // Spec section 10: Bhushan 0.41, John 0.39, David 0.35, threshold
        // 0.70 -> unknown user, NOT Bhushan just because he scored highest.
        let repo = FaceRecognitionRepository.shared
        let config = FaceRecognitionConfig.shared
        let originalThreshold = config.acceptanceThreshold
        config.acceptanceThreshold = 0.70
        defer { config.acceptanceThreshold = originalThreshold }

        let live: [Float] = [1, 0, 0, 0]
        // Construct vectors with known cosine similarities below threshold.
        func vectorWithSimilarity(_ similarity: Float) -> [Float] {
            let orthogonalComponent = (1 - similarity * similarity).squareRoot()
            return [similarity, orthogonalComponent, 0, 0]
        }

        let users = [
            RegisteredUserEmbeddings(userId: "bhushan", userName: "Bhushan", embeddings: [vectorWithSimilarity(0.41)]),
            RegisteredUserEmbeddings(userId: "john", userName: "John", embeddings: [vectorWithSimilarity(0.39)]),
            RegisteredUserEmbeddings(userId: "david", userName: "David", embeddings: [vectorWithSimilarity(0.35)]),
        ]

        let result = repo.identify(embedding: live, among: users)

        #expect(result.userId == nil)
    }

    @Test func identifyWithNoRegisteredUsersReturnsNil() {
        let repo = FaceRecognitionRepository.shared
        let result = repo.identify(embedding: [1, 0, 0, 0], among: [])
        #expect(result.userId == nil)
    }

    @Test func bestSimilarityStrategyUsesUsersHighestScoringEmbedding() {
        let repo = FaceRecognitionRepository.shared
        let config = FaceRecognitionConfig.shared
        let originalThreshold = config.acceptanceThreshold
        let originalStrategy = config.scoringStrategy
        config.acceptanceThreshold = 0.5
        config.scoringStrategy = .bestSimilarity
        defer {
            config.acceptanceThreshold = originalThreshold
            config.scoringStrategy = originalStrategy
        }

        let live: [Float] = [1, 0, 0, 0]
        // One bad embedding (low similarity), one great one — best-of should
        // still pick this user because one of their 5 embeddings is a strong match.
        let users = [
            RegisteredUserEmbeddings(
                userId: "userA", userName: "Alice",
                embeddings: [[0, 1, 0, 0], [0, 0, 1, 0], [1, 0.001, 0, 0]]
            )
        ]

        let result = repo.identify(embedding: live, among: users)

        #expect(result.userId == "userA")
    }

    @Test func loadActiveEnrollmentsSkipsUsersWithNoEmbeddings() {
        let repo = FaceRecognitionRepository.shared
        let userWithEmbeddings = repo.registerUser(
            firstName: "Has", lastName: "Embeddings \(UUID().uuidString.prefix(8))"
        )
        let userWithoutEmbeddings = repo.registerUser(
            firstName: "No", lastName: "Embeddings \(UUID().uuidString.prefix(8))"
        )
        guard let idWith = userWithEmbeddings.id, let idWithout = userWithoutEmbeddings.id else {
            Issue.record("expected user ids")
            return
        }
        defer {
            repo.deleteUser(id: idWith)
            repo.deleteUser(id: idWithout)
        }

        _ = repo.saveEnrollmentEmbeddings(userId: idWith, embeddings: [FaceEmbedding(vector: [1, 2, 3], qualityScore: 0.9)])

        let loaded = repo.loadActiveEnrollments()

        #expect(loaded.contains { $0.userId == idWith })
        #expect(!loaded.contains { $0.userId == idWithout })
    }
}
