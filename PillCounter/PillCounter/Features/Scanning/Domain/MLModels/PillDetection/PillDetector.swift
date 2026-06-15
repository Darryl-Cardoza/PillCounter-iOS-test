// PillDetector.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// MODEL:  pills_detector_fp16.mlpackage
// ARCH:   PP-YOLOE+s (anchor-free FPN with DFL box regression)
//         Trained on a single class: "pill"
// INPUT:  ImageType — 640×640 RGB
//         CoreML accepts the CVPixelBuffer directly (any colour format — BGRA,
//         RGB, etc.) and converts it internally to match the model's RGB
//         expectation before running inference. No manual colour conversion
//         is required in Swift; just letterbox to 640×640 and hand it over.
//         ImageNet-style normalization (mean subtraction / std division) is
//         baked into the model's first operation, so raw pixel values are passed.
// WEIGHTS: Float16 (~14 MB) — halved from the ~28 MB FP32 baseline with
//         minimal accuracy loss; Neural Engine handles FP16 natively.
// COMPUTE: .cpuAndNeuralEngine — the 640×640 FPN backbone benefits from
//         Neural Engine throughput; FP16 weights run without any downcasting.
//         NOTE: iPhones older than iPhone 11 crash on .cpuAndNeuralEngine for
//         larger models — .cpuOnly is the safe fallback for those devices.
// ─────────────────────────────────────────────────────────────────────────────

import CoreML

final class PillDetector {

    // Shared instance — created once at launch or first camera open.
    // Pre-warm by writing `_ = PillDetector.shared` in PillCounterApp.
    static let shared = PillDetector()

    /// The loaded CoreML model.  nil only if the mlpackage is missing or
    /// the device cannot satisfy the requested compute units.
    private(set) var model: pills_detector_fp16?

    private init() {
        loadModel()
    }

    private func loadModel() {
        print("""
        ┌─────────────────────────────────────────────
        │  [PILL MODEL] Loading pills_detector_fp16
        │  Architecture : PP-YOLOE+s (anchor-free FPN)
        │  Weights      : Float16 (~14 MB)
        │  Compute      : CPU + Neural Engine
        │  Input        : image — 640×640 RGB (ImageType)
        │  Outputs      : Identity … Identity_5 (channel-last [1,H,W,C])
        └─────────────────────────────────────────────
        """)

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            model = try pills_detector_fp16(configuration: config)

            print("✅ [PILL MODEL] Model loaded and ready")
        } catch {
            print("❌ [PILL MODEL] Failed to load — \(error)")
        }
    }
}
