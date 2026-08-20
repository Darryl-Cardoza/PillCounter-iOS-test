//
//  FaceEmbeddingStoreTests.swift
//  PillCounterTests
//

import Foundation
import Testing
@testable import PillCounter

@Suite(.serialized)
struct FaceEmbeddingStoreTests {

    @Test func insertEmbeddingPersistsAndFetchesForUser() {
        let userId = UUID().uuidString
        defer {
            FaceEmbeddingStore.shared.deleteEmbeddingsForUser(userId: userId)
            FaceUserStore.shared.deleteUser(id: userId)
        }
        FaceUserStore.shared.insertUser(id: userId, firstName: "Embedding", lastName: "Owner")

        let embedding = FaceEmbedding(vector: [0.1, 0.2, 0.3], qualityScore: 0.9)
        FaceEmbeddingStore.shared.insertEmbedding(
            id: UUID().uuidString, userId: userId,
            embeddingBase64: embedding.packedBase64(), qualityScore: embedding.qualityScore
        )

        let stored = FaceEmbeddingStore.shared.getEmbeddingsForUser(userId: userId)
        #expect(stored.count == 1)
        #expect(stored.first?.quality_score == 0.9)
    }

    @Test func multipleEmbeddingsAccumulateForSameUser() {
        let userId = UUID().uuidString
        defer {
            FaceEmbeddingStore.shared.deleteEmbeddingsForUser(userId: userId)
            FaceUserStore.shared.deleteUser(id: userId)
        }
        FaceUserStore.shared.insertUser(id: userId, firstName: "Multi", lastName: "Embedding Owner")

        for i in 0..<5 {
            let embedding = FaceEmbedding(vector: [Float(i), Float(i) + 1], qualityScore: Float(i) / 5)
            FaceEmbeddingStore.shared.insertEmbedding(
                id: UUID().uuidString, userId: userId,
                embeddingBase64: embedding.packedBase64(), qualityScore: embedding.qualityScore
            )
        }

        #expect(FaceEmbeddingStore.shared.getEmbeddingsForUser(userId: userId).count == 5)
    }

    @Test func deleteEmbeddingsForUserRemovesOnlyThatUsersRows() {
        let userA = UUID().uuidString
        let userB = UUID().uuidString
        defer {
            FaceEmbeddingStore.shared.deleteEmbeddingsForUser(userId: userA)
            FaceEmbeddingStore.shared.deleteEmbeddingsForUser(userId: userB)
            FaceUserStore.shared.deleteUser(id: userA)
            FaceUserStore.shared.deleteUser(id: userB)
        }
        FaceUserStore.shared.insertUser(id: userA, firstName: "A", lastName: "User")
        FaceUserStore.shared.insertUser(id: userB, firstName: "B", lastName: "User")

        let embedding = FaceEmbedding(vector: [1, 2, 3], qualityScore: 1)
        FaceEmbeddingStore.shared.insertEmbedding(
            id: UUID().uuidString, userId: userA, embeddingBase64: embedding.packedBase64(), qualityScore: 1
        )
        FaceEmbeddingStore.shared.insertEmbedding(
            id: UUID().uuidString, userId: userB, embeddingBase64: embedding.packedBase64(), qualityScore: 1
        )

        FaceEmbeddingStore.shared.deleteEmbeddingsForUser(userId: userA)

        #expect(FaceEmbeddingStore.shared.getEmbeddingsForUser(userId: userA).isEmpty)
        #expect(FaceEmbeddingStore.shared.getEmbeddingsForUser(userId: userB).count == 1)
    }
}
