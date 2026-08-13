//
//  FaceEmbeddingTests.swift
//  PillCounterTests
//

import Testing
@testable import PillCounter

struct FaceEmbeddingTests {

    @Test func packAndUnpackRoundTrips() {
        let vector: [Float] = [0.1, -0.5, 1.0, 3.14159, -2.71828]
        let embedding = FaceEmbedding(vector: vector, qualityScore: 0.8)

        let base64 = embedding.packedBase64()
        let unpacked = FaceEmbedding.unpack(base64: base64)

        #expect(unpacked?.count == vector.count)
        for (a, b) in zip(unpacked ?? [], vector) {
            #expect(abs(a - b) < 0.0001)
        }
    }

    @Test func unpackRejectsInvalidBase64() {
        #expect(FaceEmbedding.unpack(base64: "not-base64!!!") == nil)
    }

    @Test func unpackRejectsWrongByteLength() {
        // 3 bytes is not a multiple of Float32's 4 bytes.
        let data = Data([0x01, 0x02, 0x03])
        #expect(FaceEmbedding.unpack(base64: data.base64EncodedString()) == nil)
    }

    @Test func cosineSimilarityOfIdenticalVectorsIsOne() {
        let vector: [Float] = [1, 2, 3, 4]
        let similarity = FaceEmbedding.cosineSimilarity(vector, vector)
        #expect(abs(similarity - 1.0) < 0.0001)
    }

    @Test func cosineSimilarityOfOrthogonalVectorsIsZero() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        #expect(FaceEmbedding.cosineSimilarity(a, b) == 0)
    }

    @Test func cosineSimilarityMismatchedLengthReturnsZero() {
        #expect(FaceEmbedding.cosineSimilarity([1, 2], [1, 2, 3]) == 0)
    }
}
