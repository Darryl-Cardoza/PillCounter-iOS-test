// Traydetectionservice.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Runs the RTMDet-Tiny tray/chute detector on every camera frame and returns
// bounding boxes annotated with the detected region class (TRAY or CHUTE).
// Only pills whose centres fall inside a TRAY box are counted; CHUTE boxes
// are shown in the overlay with a distinct colour so the operator can see them.
//
// ─────────────────────────────────────────────────────────────────────────────
// MODEL ARCHITECTURE — tray_detector_fp16.mlpackage
// ─────────────────────────────────────────────────────────────────────────────
// RTMDet-Tiny is an anchor-free single-stage object detector built on:
//   • CSPNeXt backbone — efficient multi-scale feature extraction
//   • PAN-FPN neck — three output strides (8 / 16 / 32)
//   • Shared detection head — classification + box regression branches
//
// Trained on two classes (⚠️ physical mapping is INVERTED from index order):
//   Model index 0 → physically = CHUTE  (dispenser slot)
//   Model index 1 → physically = TRAY   (pill counting surface)
//
// ─────────────────────────────────────────────────────────────────────────────
// INPUT — MLMultiArray [1, 3, 640, 640] Float32 (channel-first RGB)
// ─────────────────────────────────────────────────────────────────────────────
//   • Letterbox the camera frame to 640×640 (same scale as pill model).
//   • Convert the BGRA CVPixelBuffer to a Float32 MLMultiArray with RGB channel
//     order: plane 0 = R, plane 1 = G, plane 2 = B, values in [0, 255].
//   • ImageNet mean / std normalisation is baked into the model's first op;
//     raw [0, 255] pixel values are passed — no manual normalisation required.
//   • Input name: "images"
//
// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS — 6 MLMultiArrays (channel-first [1, C, H, W], Float32)
// ─────────────────────────────────────────────────────────────────────────────
//   Stride 8  (80×80 grid — best for small / close trays):
//     var_1480  → [1, 2, 80, 80]  — classification logits  (2 classes)
//     var_1382  → [1, 4, 80, 80]  — box regression: (l, t, r, b) in STRIDE units
//
//   Stride 16 (40×40 grid — mid-range):
//     var_1481  → [1, 2, 40, 40]  — classification logits
//     var_1427  → [1, 4, 40, 40]  — box regression in stride units
//
//   Stride 32 (20×20 grid — large / wide-angle):
//     var_1482  → [1, 2, 20, 20]  — classification logits
//     var_1472  → [1, 4, 20, 20]  — box regression in stride units
//
// ─────────────────────────────────────────────────────────────────────────────
// RTMDet BOX DECODE (per anchor)
// ─────────────────────────────────────────────────────────────────────────────
//   Anchor center (half-pixel aligned):
//     cx = (col + 0.5) × stride
//     cy = (row + 0.5) × stride
//
//   Class scores (apply sigmoid to raw logits):
//     score_tray  = sigmoid(cls[0, 0, row, col])
//     score_chute = sigmoid(cls[0, 1, row, col])
//     best_score  = max(score_tray, score_chute)
//
//   Box — (l, t, r, b) are distances in LETTERBOXED PIXEL UNITS (0–640 range).
//   ⚠️ This model exports raw pixel distances, NOT stride units — do NOT × stride:
//     x1 = cx − box[0, 0, row, col]
//     y1 = cy − box[0, 1, row, col]
//     x2 = cx + box[0, 2, row, col]
//     y2 = cy + box[0, 3, row, col]
//
//   Un-letterbox from 640×640 space → original camera-frame space.
//
// ─────────────────────────────────────────────────────────────────────────────

import CoreML
import CoreVideo
import CoreImage
import CoreGraphics
import QuartzCore   // CACurrentMediaTime()

// MARK: - TrayResult

/// A detected region returned by TrayDetectionService.
///
/// rect is in the original camera-frame pixel coordinates (un-letterboxed).
/// trayClass indicates whether this is a TRAY (pill-counting region) or a
/// CHUTE (dispenser opening — shown in overlay but excluded from pill filtering).
struct TrayResult: Identifiable {
    let id = UUID()

    /// Bounding box in original camera-frame pixel coordinates.
    let rect: CGRect

    /// Detection confidence: max(sigmoid(tray_logit), sigmoid(chute_logit)).
    let confidence: Float

    /// Pixel dimensions of the raw camera frame this result was generated from.
    let originalFrameSize: CGSize

    /// Which region class was detected at this location.
    let trayClass: TrayClass
}

// MARK: - TrayDetectionService

final class TrayDetectionService {

    // MARK: - Singleton

    static let shared = TrayDetectionService()

    // MARK: - Configuration

    /// Input resolution for the tray_detector_fp16 model (640×640).
    /// Same as the pill model so both models receive identically letterboxed frames.
    private let inputSize: Int = 640

    /// Minimum class confidence to emit a detection.
    /// tray_detector_fp16 bakes sigmoid into the model's cls head — outputs are
    /// already probabilities in [0, 1].  Do NOT apply sigmoid() again.
    /// 0.60 corresponds to "at least 60% confident this cell contains a tray/chute."
    private let confThreshold: Float = 0.80

    /// IoU threshold for Non-Maximum Suppression within each TrayClass.
    private let iouThreshold: Float = 0.40

    // MARK: - Model & Context

    private var model: tray_detector_fp16?

    /// GPU-backed CIContext shared across letterbox calls; allocating per-frame is expensive.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Init

    private init() { loadModel() }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine

            model = try tray_detector_fp16(configuration: cfg)
            print("✅ [TRAY MODEL] Model loaded and ready")
        } catch {
            print("❌ [TRAY MODEL] Failed to load — \(error)")
        }
    }

    // MARK: - Public API

    /// Runs the full tray detection pipeline on one camera frame.
    ///
    /// - Parameter pixelBuffer: Raw camera frame (any resolution, BGRA).
    ///   Internally letterboxed to 640×640 before being packed into a Float32
    ///   MLMultiArray and passed to the RTMDet-Tiny model.
    /// - Returns: All detected TRAY and CHUTE regions, NMS-filtered per class.
    func detect(pixelBuffer: CVPixelBuffer) -> [TrayResult] {
        guard let model else { return [] }

        let frameSize = pixelBuffer.size

        // ── Step 1: Letterbox to 640×640 ──────────────────────────────────
        guard let (lbBuffer, scale, padX, padY) = letterbox(pixelBuffer) else {
            return []
        }

        print("""
        ── [TRAY MODEL] INPUT ──────────────────────────
           Frame size  : \(Int(frameSize.width))×\(Int(frameSize.height))
           Letterbox   : \(inputSize)×\(inputSize)
           Scale       : \(String(format: "%.4f", scale))
           Pad (X, Y)  : (\(String(format: "%.1f", padX)), \(String(format: "%.1f", padY)))
           Input name  : images (MLMultiArray [1, 3, 640, 640] Float32, raw [0,255])
        ────────────────────────────────────────────────
        """)

        // ── Step 2: CVPixelBuffer → MLMultiArray [1, 3, 640, 640] Float32 ─
        guard let inputArray = pixelBufferToMLArray(lbBuffer) else { return [] }

        // ── Step 3: Run inference using typed prediction method ────────────
        let inferenceStart = CACurrentMediaTime()
        guard let output = try? model.prediction(images: inputArray) else {
            print("❌ [TRAY MODEL] Inference failed")
            return []
        }
        let inferenceMs = (CACurrentMediaTime() - inferenceStart) * 1000

        // ── Step 4: Decode all three FPN stride levels ─────────────────────
        let strideLevels: [(cls: MLMultiArray, box: MLMultiArray, stride: Int)] = [
            (output.var_1480, output.var_1382,  8),
            (output.var_1481, output.var_1427, 16),
            (output.var_1482, output.var_1472, 32),
        ]

        var candidates: [TrayResult] = []

        for (cls, box, stride) in strideLevels {
            let decoded = decodeRTMDetLevel(
                cls: cls, box: box, stride: stride,
                scale: scale, padX: padX, padY: padY, frameSize: frameSize
            )
            candidates.append(contentsOf: decoded)
        }

        let trayCount  = candidates.filter { $0.trayClass == .tray  }.count
        let chuteCount = candidates.filter { $0.trayClass == .chute }.count

        guard !candidates.isEmpty else { return [] }

        // ── Step 5: Per-class NMS ──────────────────────────────────────────
        let final = nmsPerClass(candidates)

        let finalTray  = final.filter { $0.trayClass == .tray  }.count
        let finalChute = final.filter { $0.trayClass == .chute }.count

        // ── Debug: print every final detection ────────────────────────────────
        print("── [TRAY MODEL] FINAL DETECTIONS (after NMS) ──")
        for (i, det) in final.enumerated() {
            let cls = det.trayClass == .tray ? "TRAY" : "CHUTE"
            let r   = det.rect
            let nx  = r.origin.x / det.originalFrameSize.width
            let ny  = r.origin.y / det.originalFrameSize.height
            let nw  = r.width    / det.originalFrameSize.width
            let nh  = r.height   / det.originalFrameSize.height
            print(String(format:
                "   [%d] %@ conf=%.3f | frame=(%.0f,%.0f,%.0f×%.0f) | norm=(%.3f,%.3f,%.3f×%.3f)",
                i, cls, det.confidence,
                r.origin.x, r.origin.y, r.width, r.height,
                nx, ny, nw, nh))
        }
        print("────────────────────────────────────────────────")

        return final
    }

    // MARK: - RTMDet FPN Level Decode

    /// Decodes one stride-level pair of (cls, box) tensors into TrayResult values.
    ///
    /// Tensor layouts (channel-first [1, C, H, W]):
    ///   cls[0, classIdx, row, col] = class probability (sigmoid baked in, range 0–1)
    ///   box[0, sideIdx,  row, col] = distance from anchor to box side IN PIXEL UNITS
    ///     (letterboxed 640×640 space — NOT stride units, do NOT multiply by stride)
    ///     sideIdx 0 = left, 1 = top, 2 = right, 3 = bottom
    private func decodeRTMDetLevel(cls: MLMultiArray,
                                   box: MLMultiArray,
                                   stride: Int,
                                   scale: CGFloat,
                                   padX: CGFloat,
                                   padY: CGFloat,
                                   frameSize: CGSize) -> [TrayResult] {

        let gridH = cls.shape[2].intValue
        let gridW = cls.shape[3].intValue

        // Channel-first strides: flat_index = b*s0 + c*sC + row*sH + col*sW
        let clsSC = cls.strides[1].intValue
        let clsSH = cls.strides[2].intValue
        let clsSW = cls.strides[3].intValue

        let boxSC = box.strides[1].intValue
        let boxSH = box.strides[2].intValue
        let boxSW = box.strides[3].intValue

        // Runtime data-type detection: outputs may be Float32 or Float16.
        let clsRaw  = cls.dataPointer
        let boxRaw  = box.dataPointer
        let clsElem = cls.dataType == .float16 ? 2 : 4
        let boxElem = box.dataType == .float16 ? 2 : 4

        let strideCG = CGFloat(stride)
        var results: [TrayResult] = []

        for row in 0..<gridH {
            for col in 0..<gridW {

                let clsBase = row * clsSH + col * clsSW

                // Class scores — read directly, NO sigmoid.
                // The model's cls head already has sigmoid baked in (outputs are [0,1]).
                // Applying sigmoid again double-compresses: a background cell with true
                // score 0.30 becomes sigmoid(0.30)=0.57, passing a 0.50 threshold and
                // causing 66% of all 8,400 cells to flood through as false detections.
                //
                // ⚠️ Physical class mapping is INVERTED vs the training label indices:
                //   Model output index 0 → physical CHUTE (dispenser slot)
                //   Model output index 1 → physical TRAY  (pill counting surface)
                // Swap here so downstream filtering (pills inside TRAY) and the overlay
                // both operate on the correct physical region.
                let scoreChute = readF32(clsRaw, at: clsBase + 0 * clsSC, elem: clsElem)
                let scoreTray  = readF32(clsRaw, at: clsBase + 1 * clsSC, elem: clsElem)

                let (bestScore, bestClass): (Float, TrayClass) =
                    scoreTray >= scoreChute ? (scoreTray, .tray) : (scoreChute, .chute)

                guard bestScore >= confThreshold else { continue }

                // Anchor center (half-pixel aligned).
                let cx = (CGFloat(col) + 0.5) * strideCG
                let cy = (CGFloat(row) + 0.5) * strideCG

                let boxBase = row * boxSH + col * boxSW

                // Box regression: multiply by stride to convert stride units → pixels.
                let lRaw = readF32(boxRaw, at: boxBase + 0 * boxSC, elem: boxElem)
                let tRaw = readF32(boxRaw, at: boxBase + 1 * boxSC, elem: boxElem)
                let rRaw = readF32(boxRaw, at: boxBase + 2 * boxSC, elem: boxElem)
                let bRaw = readF32(boxRaw, at: boxBase + 3 * boxSC, elem: boxElem)

                let cls2 = bestClass == .tray ? "TRAY" : "CHUTE"
                print(String(format:
                    "   [DECODE stride=%-2d row=%2d col=%2d] %@ conf=%.3f | ltrb_px=(%.1f,%.1f,%.1f,%.1f) cx=%.1f cy=%.1f",
                    stride, row, col, cls2, bestScore,
                    CGFloat(lRaw), CGFloat(tRaw), CGFloat(rRaw), CGFloat(bRaw),
                    cx, cy))

                // The model exports distances in letterboxed-pixel units (0–640 range),
                // NOT in stride units — do NOT multiply by stride.
                let l = CGFloat(lRaw)
                let t = CGFloat(tRaw)
                let r = CGFloat(rRaw)
                let b = CGFloat(bRaw)

                // Un-letterbox: 640×640 → original camera-frame space.
                // No clamping to frame bounds — return the model's box verbatim, the
                // same way PillDetectionService does. Clamping each edge to the frame
                // pulled the box inward whenever the model's regression slightly
                // overshot the edge, which showed up as a gap between the drawn tray
                // box and the real tray border (most visible on the larger landscape
                // tray). The overlay's layerRectConverted handles any slight overshoot
                // geometrically, exactly as it does for pills.
                let x1 = (cx - l - padX) / scale
                let y1 = (cy - t - padY) / scale
                let x2 = (cx + r - padX) / scale
                let y2 = (cy + b - padY) / scale

                guard x2 > x1, y2 > y1 else { continue }

                results.append(TrayResult(
                    rect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                    confidence: bestScore,
                    originalFrameSize: frameSize,
                    trayClass: bestClass
                ))
            }
        }

        return results
    }

    // MARK: - Per-Class NMS

    private func nmsPerClass(_ items: [TrayResult]) -> [TrayResult] {
        nmsSingle(items.filter { $0.trayClass == .tray })
        + nmsSingle(items.filter { $0.trayClass == .chute })
    }

    private func nmsSingle(_ items: [TrayResult]) -> [TrayResult] {
        let sorted     = items.sorted { $0.confidence > $1.confidence }
        var suppressed = [Bool](repeating: false, count: sorted.count)
        var kept       = [TrayResult]()

        for i in 0..<sorted.count {
            guard !suppressed[i] else { continue }
            kept.append(sorted[i])
            for j in (i + 1)..<sorted.count where !suppressed[j] {
                if iou(sorted[i].rect, sorted[j].rect) > iouThreshold {
                    suppressed[j] = true
                }
            }
        }
        return kept
    }

    // MARK: - Letterbox (640×640, pad = 114)

    private func letterbox(_ px: CVPixelBuffer)
        -> (buffer: CVPixelBuffer, scale: CGFloat, padX: CGFloat, padY: CGFloat)? {

        let src  = CIImage(cvPixelBuffer: px)
        let srcW = src.extent.width
        let srcH = src.extent.height
        let size = CGFloat(inputSize)

        let scale = min(size / srcW, size / srcH)
        let padX  = (size - srcW * scale) / 2
        let padY  = (size - srcH * scale) / 2

        let transformed = src
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))

        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey:           inputSize as CFNumber,
            kCVPixelBufferHeightKey:          inputSize as CFNumber,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA as CFNumber,
        ]
        var outBuf: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault,
                                  inputSize, inputSize,
                                  kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary,
                                  &outBuf) == kCVReturnSuccess,
              let out = outBuf else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let grey = CIImage(color: CIColor(red: 114/255, green: 114/255, blue: 114/255))
            .cropped(to: bounds)
        ciContext.render(transformed.composited(over: grey), to: out, bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        return (out, scale, padX, padY)
    }

    // MARK: - CVPixelBuffer → MLMultiArray [1, 3, 640, 640] Float32

    /// Converts a 640×640 BGRA CVPixelBuffer to a [1, 3, 640, 640] Float32
    /// MLMultiArray with RGB channel order and raw [0, 255] values.
    private func pixelBufferToMLArray(_ px: CVPixelBuffer) -> MLMultiArray? {
        guard let array = try? MLMultiArray(
            shape: [1, 3,
                    NSNumber(value: inputSize),
                    NSNumber(value: inputSize)],
            dataType: .float32
        ) else { return nil }

        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return nil }

        let rowBytes    = CVPixelBufferGetBytesPerRow(px)
        let totalPixels = inputSize * inputSize
        let dst         = array.dataPointer.assumingMemoryBound(to: Float.self)

        let rPlane = dst
        let gPlane = dst + totalPixels
        let bPlane = dst + 2 * totalPixels

        for row in 0..<inputSize {
            let rowPtr = base.advanced(by: row * rowBytes)
                             .assumingMemoryBound(to: UInt8.self)
            let rowBase = row * inputSize
            for col in 0..<inputSize {
                let px4 = col * 4  // BGRA: byte 0=B, 1=G, 2=R, 3=A
                rPlane[rowBase + col] = Float(rowPtr[px4 + 2])
                gPlane[rowBase + col] = Float(rowPtr[px4 + 1])
                bPlane[rowBase + col] = Float(rowPtr[px4 + 0])
            }
        }

        return array
    }

    // MARK: - Utilities

    /// Reads one Float32 value from a raw MLMultiArray data pointer.
    /// Handles both Float32 (elem=4) and Float16 (elem=2) backing storage.
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
