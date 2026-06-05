// PillDetectionService.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Runs the PP-YOLOE+s pill detector on every camera frame and returns a
// stable, temporally-smoothed set of bounding boxes plus a pill count.
//
// ─────────────────────────────────────────────────────────────────────────────
// MODEL ARCHITECTURE — pills_detector_fp16.mlpackage
// ─────────────────────────────────────────────────────────────────────────────
// PP-YOLOE+s is an anchor-free single-class detector built on:
//   • PAN-FPN backbone — features extracted at three strides (8 / 16 / 32)
//   • HardSwish activations throughout the backbone
//   • DFL (Distribution Focal Loss) box head — instead of directly regressing
//     (l, t, r, b) distances, the head outputs a DISTRIBUTION over reg_max
//     discrete integer distances.  A soft-argmax (weighted sum after softmax)
//     recovers the continuous distance.
//
// ─────────────────────────────────────────────────────────────────────────────
// INPUT — image, 640×640 RGB (ImageFeatureType)
// ─────────────────────────────────────────────────────────────────────────────
//   • Call Letterbox.preprocess(_:targetSize:640) to scale + pad the camera frame.
//   • Pass the resulting CVPixelBuffer directly — CoreML reads BGRA buffers and
//     converts to RGB internally; no manual channel rearrangement needed.
//   • ImageNet normalization (mean / std) is baked into the model's first layer.
//
// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS — 6 MLMultiArrays (CHANNEL-LAST layout: [1, H, W, C])
// ─────────────────────────────────────────────────────────────────────────────
//   Identity   → [1, 80, 80,  1] — stride-8  cls score   (POST-SIGMOID, already [0,1])
//   Identity_1 → [1, 40, 40,  1] — stride-16 cls score   (post-sigmoid)
//   Identity_2 → [1, 20, 20,  1] — stride-32 cls score   (post-sigmoid)
//   Identity_3 → [1, 80, 80, 68] — stride-8  DFL box distribution (raw logits, needs softmax)
//   Identity_4 → [1, 40, 40, 68] — stride-16 DFL box distribution
//   Identity_5 → [1, 20, 20, 68] — stride-32 DFL box distribution
//
//   reg_max = 17  (68 / 4 = 17 distribution bins per box side)
//
//   ⚠️ cls outputs are POST-SIGMOID (baked into the model's final layer, per iOS spec).
//   Do NOT apply sigmoid() in Swift — that double-compresses scores and makes every
//   background cell score ≥ 0.5, causing all 8400 anchors to pass any threshold.
//   Compare the raw [0,1] values directly against the score thresholds.
//
//   reg outputs are RAW logits — apply softmax then weighted sum (DFL decode) as normal.
//
//   Outputs are CHANNEL-LAST [batch, H, W, C].  Indexing:
//     value at (row, col, channel) = array[row * W * C + col * C + channel]
//
// ─────────────────────────────────────────────────────────────────────────────
// DFL BOX DECODE (per anchor)
// ─────────────────────────────────────────────────────────────────────────────
//   The 68 box channels are split into 4 groups of 17, one per side: l, t, r, b.
//   For each group:
//     1. Apply softmax across the 17 values.
//     2. Compute weighted sum: dist = Σ (i × softmax_i) for i = 0 … 16
//        (this is the soft-argmax that recovers the continuous distance).
//     3. Multiply by stride to convert from stride units to pixel units:
//        dist_px = dist × stride
//
//   Anchor center (half-pixel aligned to grid cell center):
//     cx = (col + 0.5) × stride
//     cy = (row + 0.5) × stride
//
//   Final box corners in 640×640 letterbox space:
//     x1 = cx − l_px,  y1 = cy − t_px
//     x2 = cx + r_px,  y2 = cy + b_px
//
//   Un-letterbox to original camera-frame space using Letterbox.currentScaleInfo.
//
// ─────────────────────────────────────────────────────────────────────────────
// CONFIDENCE HYSTERESIS (replaces CountStabilizer median window)
// ─────────────────────────────────────────────────────────────────────────────
//   The old YOLO model with built-in NMS was stable enough for a simple median
//   window.  PP-YOLOE+s raw outputs are noisier frame-to-frame, so we use a
//   two-threshold hysteresis scheme instead:
//
//   ENTER threshold (enterConf = 0.55)
//     A NEW detection (no overlap with any box from the previous frame) must
//     exceed this stricter threshold to be admitted.
//
//   STAY threshold (stayConf = 0.45)
//     A detection that OVERLAPS (IoU ≥ overlapIoU = 0.45) with a detection
//     from the previous frame is kept as long as confidence stays above this
//     lower threshold.  This avoids flickering when the model wavers between
//     0.48 and 0.52 on a detection it clearly saw in the prior frame.
//
//   The hysteresis set is updated every frame:
//     active ← NMS( ENTER candidates ∪ STAY candidates )
//
// ─────────────────────────────────────────────────────────────────────────────

import CoreML
import CoreGraphics
import Foundation
import QuartzCore   // CACurrentMediaTime()

// MARK: - DetectionResult

/// A single pill bounding box returned by PillDetectionService.
///
/// rect is in original (un-letterboxed) camera-frame pixel coordinates.
/// Overlays convert it to screen space using originalFrameSize and
/// AVCaptureVideoPreviewLayer.layerRectConverted.
struct DetectionResult: Identifiable, Equatable {
    let id = UUID()
    let rect: CGRect
    let confidence: Float
    let originalFrameSize: CGSize

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    static func == (lhs: DetectionResult, rhs: DetectionResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - PillDetectionService

final class PillDetectionService {

    // MARK: - Configuration

    /// Input resolution for the pills_detector_fp16 model.
    private let inputSize: CGFloat = 640

    /// Number of DFL distribution bins per box side (68 channels / 4 sides = 17).
    private let regMax: Int = 17

    /// ENTER hysteresis threshold: a brand-new (non-overlapping) detection must
    /// exceed this confidence to be accepted in the current frame.
    ///
    /// The cls output is already post-sigmoid (model has baked-in sigmoid, per the
    /// iOS integration spec).  Values are direct probabilities [0, 1] — do NOT apply
    /// sigmoid again.  Reference scoreThresh from spec = 0.25; we use 0.45 to be
    /// stricter for a stable pill count.
    private let enterConf: Float = 0.70

    /// STAY hysteresis threshold: a detection overlapping a box from the previous
    /// frame is kept as long as confidence stays above this softer threshold.
    /// Lower than enterConf to avoid flickering on detections already confirmed.
    private let stayConf: Float = 0.70

    /// Minimum IoU between a new detection and a previous-frame detection to
    /// count as "the same object" for STAY-mode purposes.
    private let overlapIoU: Float = 0.45

    /// IoU threshold used in final Non-Maximum Suppression after hysteresis.
    /// 0.60 per the iOS integration spec (higher = less aggressive suppression
    /// of tightly-packed pills that legitimately have high overlap).
    private let nmsIoU: Float = 0.60

    // MARK: - State

    /// Bounding boxes from the most recently completed frame.
    /// Used as the "previous frame" reference for STAY-mode hysteresis.
    private var previousFrameBoxes: [CGRect] = []

    // MARK: - Model Reference

    private let model = PillDetector.shared.model

    // MARK: - Public API

    /// Runs full detection pipeline (preprocess → infer → decode → NMS → hysteresis).
    ///
    /// - Parameters:
    ///   - pixelBuffer: Raw camera frame (any resolution). Will be letterboxed to 640×640.
    ///   - completion:  Called on the inference queue with (filtered detections, stable count).
    func detect(pixelBuffer: CVPixelBuffer,
                completion: @escaping ([DetectionResult], Int) -> Void) {

        guard let model else { return }

        let frameSize = pixelBuffer.size

        // ── Step 1: Letterbox to 640×640 ──────────────────────────────────
        guard let resized = Letterbox.preprocess(pixelBuffer, targetSize: Int(inputSize)) else {
            return
        }

        var scaleInfo = Letterbox.currentScaleInfo

        // ── Step 2: Build CoreML image input ──────────────────────────────
        let mlInput = pills_detector_fp16Input(image: resized)

        // ── Step 3: Run inference ──────────────────────────────────────────
        let inferenceStart = CACurrentMediaTime()
        guard let output = try? model.prediction(input: mlInput) else {
            print("❌ [PILL MODEL] Inference failed")
            completion([], 0)
            return
        }
        let inferenceMs = (CACurrentMediaTime() - inferenceStart) * 1000


        // ── Step 4: Decode all three FPN stride levels ─────────────────────
        // Each stride level contributes a cls tensor and a box tensor.
        // All outputs are CHANNEL-LAST: shape [1, H, W, C].
        scaleInfo = Letterbox.currentScaleInfo

        var raw: [DetectionResult] = []

        let strideLevels: [(cls: MLMultiArray, box: MLMultiArray, stride: Int)] = [
            // Stride 8 → 80×80 grid — best for small, closely-packed pills
            (output.Identity,   output.Identity_3, 8),
            // Stride 16 → 40×40 grid — mid-scale
            (output.Identity_1, output.Identity_4, 16),
            // Stride 32 → 20×20 grid — large pills / wide-angle shots
            (output.Identity_2, output.Identity_5, 32),
        ]

        for (cls, box, stride) in strideLevels {
            let decoded = decodeFPNLevel(
                cls: cls, box: box, stride: stride,
                originalSize: frameSize, scaleInfo: scaleInfo
            )
            raw.append(contentsOf: decoded)
        }

        // ── Step 5: Confidence hysteresis ──────────────────────────────────
        // Split raw candidates into ENTER (new) and STAY (seen in prev frame).
        // Apply the appropriate threshold to each group before merging.
        let afterHysteresis = applyHysteresis(raw)

        // ── Step 6: Non-Maximum Suppression ────────────────────────────────
        let final = NMS.run(detections: afterHysteresis, iouThreshold: nmsIoU)

        // Update hysteresis state for the next frame.
        previousFrameBoxes = final.map { $0.rect }

        completion(final, final.count)
    }

    // MARK: - FPN Level Decode (DFL + Sigmoid + Un-letterbox)

    /// Decodes one stride-level pair of (cls, box) tensors into DetectionResult values.
    ///
    /// Tensor layout — both cls and box are CHANNEL-LAST [1, H, W, C]:
    ///   cls[0, row, col, 0]    = raw classification logit for the pill class
    ///   box[0, row, col, 0..67] = 68 DFL logits (17 per box side: l, t, r, b)
    ///
    /// Decode steps:
    ///   1. score = sigmoid(cls_logit) — gate on ENTER/STAY threshold later.
    ///   2. For each box side (4 groups of 17 values):
    ///        softmax across 17 bins → weighted sum [0..16] → dist × stride = pixels.
    ///   3. Reconstruct corners from anchor center ± decoded distances.
    ///   4. Un-letterbox corners to original camera-frame space.
    private func decodeFPNLevel(cls: MLMultiArray,
                                box: MLMultiArray,
                                stride: Int,
                                originalSize: CGSize,
                                scaleInfo: Letterbox.ScaleInfo?) -> [DetectionResult] {

        let gridH = cls.shape[1].intValue  // height of this FPN grid
        let gridW = cls.shape[2].intValue  // width  of this FPN grid

        // Strides for channel-last indexing:
        //   flat_index = batch * s0 + row * sH + col * sW + channel * 1
        // cls shape:  [1, H, W, 1]  → strides [H*W*1, W*1, 1, 1]
        // box shape:  [1, H, W, 68] → strides [H*W*68, W*68, 68, 1]
        let clsS0 = cls.strides[0].intValue
        let clsSH = cls.strides[1].intValue
        let clsSW = cls.strides[2].intValue

        let boxS0 = box.strides[0].intValue
        let boxSH = box.strides[1].intValue
        let boxSW = box.strides[2].intValue

        // ── Runtime data-type detection ────────────────────────────────────
        // CoreML may return Float16 or Float32 MLMultiArrays depending on
        // compute unit, device, and CoreML version.  We must not assume one
        // type at compile time: binding Float.self to a Float16 buffer causes
        // 2× stride overrun → EXC_BAD_ACCESS; binding UInt16.self to a Float32
        // buffer reads half-words and produces garbage scores.
        //
        // Solution: use raw byte-offset loads (not element-index subscripting)
        // with the element size determined from dataType at runtime.
        // MLMultiArray.strides are always in element units regardless of type.
        let clsRaw  = cls.dataPointer
        let boxRaw  = box.dataPointer
        let clsElem = cls.dataType == .float16 ? 2 : 4   // bytes per element
        let boxElem = box.dataType == .float16 ? 2 : 4

        var results: [DetectionResult] = []

        for row in 0..<gridH {
            for col in 0..<gridW {

                // ── Classification score ───────────────────────────────────
                // Tensor layout [1, H, W, 1]: single value per anchor.
                // IMPORTANT: pills_detector_fp16 bakes sigmoid into the model's
                // final layer — the cls output is already a probability in [0, 1].
                // Do NOT apply sigmoid() again; that would double-compress scores
                // (e.g. a background cell with true score 0.3 becomes sigmoid(0.3)=0.57,
                // which passes any reasonable threshold and causes all 8400 cells to
                // appear as candidates).
                let clsIdx = 0 * clsS0 + row * clsSH + col * clsSW
                let score  = readF32(clsRaw, at: clsIdx, elem: clsElem)

                // Pre-filter: reject anchors below the lower STAY threshold.
                // Proper ENTER/STAY gating happens in applyHysteresis().
                guard score >= stayConf else { continue }

                // ── DFL box decode ─────────────────────────────────────────
                // Box tensor layout [1, H, W, 68]: 68 logits per anchor.
                // Channels 0..16  = left   distribution (17 bins)
                // Channels 17..33 = top    distribution
                // Channels 34..50 = right  distribution
                // Channels 51..67 = bottom distribution
                let boxBase = 0 * boxS0 + row * boxSH + col * boxSW

                let lDist = dfl(raw: boxRaw, offset: boxBase + 0,          count: regMax, elem: boxElem) * CGFloat(stride)
                let tDist = dfl(raw: boxRaw, offset: boxBase + regMax,      count: regMax, elem: boxElem) * CGFloat(stride)
                let rDist = dfl(raw: boxRaw, offset: boxBase + regMax * 2,  count: regMax, elem: boxElem) * CGFloat(stride)
                let bDist = dfl(raw: boxRaw, offset: boxBase + regMax * 3,  count: regMax, elem: boxElem) * CGFloat(stride)

                // ── Anchor center (half-pixel aligned) ─────────────────────
                // Grid cells are indexed from (0,0) at top-left.  The anchor point
                // sits at the CENTER of the cell, hence the + 0.5 offset.
                let cx = (CGFloat(col) + 0.5) * CGFloat(stride)
                let cy = (CGFloat(row) + 0.5) * CGFloat(stride)

                // ── Letterbox-space box corners ────────────────────────────
                var x1 = cx - lDist
                var y1 = cy - tDist
                var x2 = cx + rDist
                var y2 = cy + bDist

                // ── Un-letterbox to original camera-frame space ────────────
                // Letterbox.preprocess stored (scale, padX, padY).
                // Reverse: original = (letterboxed − pad) / scale
                if let s = scaleInfo {
                    x1 = (x1 - s.padX) / s.scale
                    y1 = (y1 - s.padY) / s.scale
                    x2 = (x2 - s.padX) / s.scale
                    y2 = (y2 - s.padY) / s.scale
                }

                guard x2 > x1, y2 > y1 else { continue }

                results.append(DetectionResult(
                    rect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                    confidence: score,
                    originalFrameSize: originalSize
                ))
            }
        }

        return results
    }

    // MARK: - Confidence Hysteresis

    /// Partitions raw candidates into ENTER and STAY sets, applies the
    /// appropriate threshold to each, and merges the survivors.
    ///
    /// STAY candidates are those whose bounding box overlaps (IoU ≥ overlapIoU)
    /// at least one box from the previous frame.  They are kept if confidence
    /// ≥ stayConf.  All other candidates are ENTER and require ≥ enterConf.
    private func applyHysteresis(_ candidates: [DetectionResult]) -> [DetectionResult] {

        var kept: [DetectionResult] = []

        for det in candidates {
            let overlapsAnything = previousFrameBoxes.contains { prev in
                iou(det.rect, prev) >= overlapIoU
            }

            if overlapsAnything {
                // STAY mode — lower bar: detection was already "confirmed"
                if det.confidence >= stayConf { kept.append(det) }
            } else {
                // ENTER mode — stricter bar: new detection must be confident enough
                if det.confidence >= enterConf { kept.append(det) }
            }
        }

        return kept
    }

    // MARK: - DFL Soft-Argmax

    /// Computes the DFL soft-argmax over `count` logits from a raw byte buffer.
    /// Works for both Float32 (elem=4) and Float16 (elem=2) backing storage.
    ///
    /// Steps:
    ///   1. Load each value via readF32 (handles FP16↔FP32 transparently).
    ///   2. Numerically stable softmax (subtract max to prevent exp overflow).
    ///   3. Weighted sum: Σ(i × softmax_i) — the soft-argmax that recovers
    ///      the continuous distance in stride units.
    @inline(__always)
    private func dfl(raw: UnsafeMutableRawPointer, offset: Int, count: Int, elem: Int) -> CGFloat {
        var maxVal = readF32(raw, at: offset, elem: elem)
        for i in 1..<count { maxVal = Swift.max(maxVal, readF32(raw, at: offset + i, elem: elem)) }

        var expVals = [Float](repeating: 0, count: count)
        var sumExp: Float = 0
        for i in 0..<count {
            let e = exp(readF32(raw, at: offset + i, elem: elem) - maxVal)
            expVals[i] = e
            sumExp    += e
        }

        var weightedSum: Float = 0
        for i in 0..<count { weightedSum += Float(i) * (expVals[i] / sumExp) }
        return CGFloat(weightedSum)
    }

    // MARK: - Utilities

    /// Reads one Float32 value from a raw MLMultiArray data pointer.
    /// `elem` is the element byte size: 4 for Float32, 2 for Float16.
    /// Handles both backing types correctly using byte-offset loads.
    @inline(__always)
    private func readF32(_ raw: UnsafeMutableRawPointer, at index: Int, elem: Int) -> Float {
        if elem == 2 {
            let bits = raw.load(fromByteOffset: index * 2, as: UInt16.self)
            return Float(Float16(bitPattern: bits))
        }
        return raw.load(fromByteOffset: index * 4, as: Float.self)
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let ia = inter.width * inter.height
        return Float(ia / (a.width * a.height + b.width * b.height - ia))
    }
}

// MARK: - MLMultiArray subscript helpers

extension MLMultiArray {
    /// 2-D subscript [row, col] — used for the old `best` model compatibility.
    subscript(i: Int, j: Int) -> NSNumber {
        self[i * strides[0].intValue + j * strides[1].intValue]
    }
}

extension NSNumber {
    var cgFloat: CGFloat { CGFloat(doubleValue) }
}

extension CVPixelBuffer {
    var size: CGSize {
        CGSize(width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))
    }
}
