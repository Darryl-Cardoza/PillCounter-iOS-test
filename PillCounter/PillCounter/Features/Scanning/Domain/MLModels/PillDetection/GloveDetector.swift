// GloveDetector.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// MODEL:  gloves_detector_fp32.mlpackage
// ARCH:   YOLOX-Nano with LeakyReLU activations
// INPUT:  MLMultiArray — shape [1, 3, 320, 320], Float32
//         • Raw pixel values in the range [0, 255] — NO normalization.
//         • YOLOX was trained on raw pixels; the first layer performs
//           its own internal scaling. Do NOT subtract mean or divide by std.
//         • Channel order: RGB (red in channel 0, green in channel 1, blue in channel 2).
//         • The input must be letterboxed to exactly 320×320 before packing
//           into the MLMultiArray; padding value = 114.0 (YOLOX standard).
// WEIGHTS: Float32 (~3.5 MB) — kept at full precision because the model is small
//          and FP16 quantisation of YOLOX-Nano degrades accuracy noticeably at
//          the sigmoid / exp decode steps.
// COMPUTE: .cpuAndGPU — the small model fits entirely in GPU L2; Neural Engine
//          can silently cast to FP16 and reduce accuracy on this model.
// ─────────────────────────────────────────────────────────────────────────────

import CoreML

final class GloveDetector {

    // Shared instance — loaded once at app launch or on first camera open.
    // Pre-warming happens in PillCounterApp via `_ = GloveDetector.shared`.
    static let shared = GloveDetector()

    /// The loaded CoreML model.  nil only if model file is missing or corrupted.
    private(set) var model: gloves_detector_fp16?

    private init() {
        loadModel()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndGPU

            model = try gloves_detector_fp16(configuration: config)

            print("✅ [GLOVE MODEL] Model loaded and ready")
        } catch {
            print("❌ [GLOVE MODEL] Failed to load — \(error)")
        }
    }
}
