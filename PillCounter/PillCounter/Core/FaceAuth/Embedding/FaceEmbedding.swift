//
//  FaceEmbedding.swift
//  PillCounter
//
//  The SFace output vector plus the packing helpers used to persist it.
//  Packing format (Float32 little-endian, contiguous) is shared by
//  enrollment and (later) authentication so a stored embedding can always
//  be compared against a freshly extracted one.
//

import Foundation

struct FaceEmbedding {
    /// Raw 128-d SFace feature vector. Never log this — treat as biometric PII.
    let vector: [Float]

    /// Quality score of the sample this embedding was extracted from, carried
    /// through for storage (FaceEmbeddingEntity.quality_score).
    let qualityScore: Float

    /// Packs the vector as contiguous little-endian Float32 bytes, base64-encoded.
    /// This is the exact string handed to FaceEmbeddingStore.insertEmbedding —
    /// FieldEncryptionManager encrypts it transparently via the Core Data
    /// willSave hook, so callers never deal with ciphertext directly.
    func packedBase64() -> String {
        var floats = vector
        let data = floats.withUnsafeMutableBufferPointer { buf in
            Data(buffer: buf)
        }
        return data.base64EncodedString()
    }

    /// Inverse of `packedBase64()`. Returns nil if the payload isn't a valid
    /// packed Float32 buffer (wrong length, corrupted data).
    static func unpack(base64: String) -> [Float]? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        var floats = [Float](repeating: 0, count: count)
        _ = floats.withUnsafeMutableBytes { dest in
            data.copyBytes(to: dest)
        }
        return floats
    }

    /// Cosine similarity between two embedding vectors, in [-1, 1]. Used by
    /// the (optional, not yet wired) duplicate-face check and by future
    /// authentication matching. Returns 0 if the vectors have mismatched
    /// dimensionality or either is zero-length.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = (normA.squareRoot() * normB.squareRoot())
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
