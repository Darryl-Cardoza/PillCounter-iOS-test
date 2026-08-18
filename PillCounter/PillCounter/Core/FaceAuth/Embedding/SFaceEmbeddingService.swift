//
//  SFaceEmbeddingService.swift
//  PillCounter
//
//  Runs the PRE-TRAINED SFace model (sface_112x112_float16.mlpackage) on an
//  already-aligned 112×112 face and returns the 128-d embedding. This is the
//  ONLY place SFace is invoked from — enrollment and (later) authentication
//  both call `extractEmbedding(alignedFace:)` so preprocessing/normalization
//  never diverges between the two flows (spec section 16).
//
//  MODEL I/O (inspected directly from the .mlpackage spec):
//    • Input:  "data" — MLMultiArray Float16 [1, 112, 112, 3], NHWC, BGR.
//    • Output: "Identity" — MLMultiArray Float16 [1, 128], the embedding.
//

import CoreML
import CoreVideo

final class SFaceEmbeddingService {

    static let shared = SFaceEmbeddingService()

    private let inputSize: Int = 112
    private var model: sface_112x112_float16?

    private init() { loadModel() }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            model = try sface_112x112_float16(configuration: cfg)
            Log("SFace: model loaded and ready")
        } catch {
            Log("SFace: failed to load — \(error)")
        }
    }

    /// Extracts a 128-d embedding from an already-aligned 112×112 BGRA face
    /// (output of FaceAligner.align). Returns nil on any failure — the model
    /// isn't loaded, input conversion fails, or inference throws. Never
    /// throws itself so callers can treat "no embedding" as one outcome.
    /// Never logs the embedding vector itself — only success/failure.
    func extractEmbedding(alignedFace: CVPixelBuffer) -> FaceEmbedding? {
        guard let model else {
            Log("SFace: model not loaded")
            return nil
        }
        guard let input = pixelBufferToNHWCFloat16(alignedFace) else {
            Log("SFace: input conversion failed")
            return nil
        }
        guard let output = try? model.prediction(data: input) else {
            Log("SFace: model.prediction threw")
            return nil
        }

        let embeddingArray = output.Identity
        guard embeddingArray.shape.count == 2 else { return nil }
        let dim = embeddingArray.shape[1].intValue

        var vector = [Float](repeating: 0, count: dim)
        let elem = embeddingArray.dataType == .float16 ? 2 : 4
        let raw = embeddingArray.dataPointer
        let stride = embeddingArray.strides[1].intValue

        for i in 0..<dim {
            let offset = i * stride
            if elem == 2 {
                let bits = raw.load(fromByteOffset: offset * 2, as: UInt16.self)
                vector[i] = Float(Float16(bitPattern: bits))
            } else {
                vector[i] = raw.load(fromByteOffset: offset * 4, as: Float.self)
            }
        }

        // TEMP DEBUG — L2 norm of raw (pre-normalization) embedding. Remove
        // after root-causing bug 1/bug 2. A near-zero norm means the model
        // input was degenerate (blank/occluded crop); a norm wildly
        // different from other captures on the same device flags a
        // preprocessing mismatch, not a matching-logic bug.
        let l2Norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        Log("DEBUG embedding: dim=\(dim) L2norm=\(String(format: "%.4f", l2Norm))")
        Log("SFace: embedding extracted (dim=\(dim))")
        // qualityScore is filled in by the caller (FaceQualityChecker already
        // ran before extraction) — 0 here is just a placeholder default.
        return FaceEmbedding(vector: vector, qualityScore: 0)
    }

    /// Converts a 112×112 BGRA pixel buffer into the [1,112,112,3] Float16
    /// NHWC array SFace expects.
    ///
    /// Channel order: BGR, not RGB — see YuNetDetectorService's identical
    /// helper for why. Same fix applies here: our BGRA buffer's first 3
    /// bytes are already B,G,R in the order the proven-working reference
    /// pipeline feeds SFace; copy them as-is.
    private func pixelBufferToNHWCFloat16(_ buffer: CVPixelBuffer) -> MLMultiArray? {
        guard let array = try? MLMultiArray(
            shape: [1, NSNumber(value: inputSize), NSNumber(value: inputSize), 3],
            dataType: .float16
        ) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let dst = array.dataPointer.assumingMemoryBound(to: UInt16.self)

        for y in 0..<inputSize {
            let row = ptr + y * bytesPerRow
            for x in 0..<inputSize {
                let px = row + x * 4 // BGRA
                let base = (y * inputSize + x) * 3
                dst[base + 0] = Float16(Float(px[0])).bitPattern // B
                dst[base + 1] = Float16(Float(px[1])).bitPattern // G
                dst[base + 2] = Float16(Float(px[2])).bitPattern // R
            }
        }
        return array
    }
}
