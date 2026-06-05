// GloveDetectionService.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Runs the YOLOX-Nano glove-safety detector on every camera frame (after the
// first detection is found, inference is rate-limited to once per 400 ms so
// that it does not compete with the pill and tray models on the GPU).
//
// ─────────────────────────────────────────────────────────────────────────────
// MODEL ARCHITECTURE — gloves_detector_fp32.mlpackage
// ─────────────────────────────────────────────────────────────────────────────
// YOLOX-Nano with LeakyReLU activations, trained to distinguish:
//   Class 0 → "glove"    (operator wearing protective gloves — SAFE)
//   Class 1 → "no_glove" (bare hands visible — HAZARDOUS)
//
// The model uses a decoupled FPN head at three strides:
//   Stride  8 → 40×40 grid  (detects small / close hands)
//   Stride 16 → 20×20 grid  (mid-range)
//   Stride 32 → 10×10 grid  (large / distant hands)
//
// ─────────────────────────────────────────────────────────────────────────────
// INPUT — MLMultiArray [1, 3, 320, 320] Float32
// ─────────────────────────────────────────────────────────────────────────────
//   • Letterbox the camera frame to exactly 320×320 (pad value = 114).
//   • Pack RGB channels in channel-first order: [R, G, B] planes.
//   • Pixel values stay in [0, 255] — no mean subtraction, no /255 division.
//     YOLOX-Nano was trained on raw uint8 values; normalization is not baked in.
//
// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS — 3 MLMultiArrays (channel-first, Float32)
// ─────────────────────────────────────────────────────────────────────────────
//   var_1542 → [1, 7, 40, 40]  — stride-8 FPN head
//   var_1742 → [1, 7, 20, 20]  — stride-16 FPN head
//   var_1942 → [1, 7, 10, 10]  — stride-32 FPN head
//
//   The 7 channels per anchor cell are:
//     ch 0  : x_center offset  (raw logit — apply sigmoid → + col → × stride = cx_px)
//     ch 1  : y_center offset  (raw logit — apply sigmoid → + row → × stride = cy_px)
//     ch 2  : width            (raw value — apply exp → × stride = w_px)
//     ch 3  : height           (raw value — apply exp → × stride = h_px)
//     ch 4  : objectness score (raw logit — apply sigmoid)
//     ch 5  : class 0 logit    (glove    — apply sigmoid)
//     ch 6  : class 1 logit    (no_glove — apply sigmoid)
//
//   Final confidence = sigmoid(ch4) × sigmoid(ch5 or ch6 per argmax class)
//
// ─────────────────────────────────────────────────────────────────────────────
// RATE LIMITING
// ─────────────────────────────────────────────────────────────────────────────
//   • Before any glove is detected: run every frame (fast feedback on first use).
//   • After a glove is detected: run at most once per 400 ms.
//     This keeps GPU headroom for the pill and tray models which run every frame.
//
// ─────────────────────────────────────────────────────────────────────────────

import CoreML
import Accelerate
import CoreVideo
import CoreImage
import CoreGraphics
import QuartzCore   // CACurrentMediaTime() for rate-limit timestamp comparisons

final class GloveDetectionService {

    // MARK: - Configuration Constants

    /// Input resolution expected by the gloves_detector_fp32 model.
    private let inputSize: Int = 320

    /// Minimum sigmoid(objectness) × sigmoid(class) required to emit a detection.
    /// Tuned for YOLOX-Nano at 320×320 — lower values increase recall but add
    /// false positives from glove-shaped objects (e.g. trays).
    private let confThreshold: Float = 0.35

    /// IoU threshold used during Non-Maximum Suppression.
    private let iouThreshold: Float = 0.45

    /// YOLOX standard letterbox pad value (grey, matching training aug).
    private let padValue: Float = 114.0

    /// Time interval between glove inference runs once a detection has been found.
    /// Avoids competing with pill / tray models on every single frame.
    private let rateLimitAfterDetection: TimeInterval = 0.4  // 400 ms

    // MARK: - State

    /// Timestamp of the last time glove inference was actually executed.
    private var lastInferenceTime: TimeInterval = 0

    /// True once at least one glove or no-glove detection has been seen.
    /// Before this point inference runs every frame; after, it is rate-limited.
    private var hasDetectedOnce: Bool = false

    // MARK: - Model Reference

    private let model = GloveDetector.shared.model

    // MARK: - CIContext (shared, GPU-backed)

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Public API

    /// Resets detection state so inference restarts from the beginning.
    /// Call this when resuming from an inactivity pause or starting a new session.
    func reset() {
        hasDetectedOnce = false
        lastInferenceTime = 0
    }

    /// Checks the rate limit and, if inference should run, executes the full
    /// glove detection pipeline on the given camera frame.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Raw camera frame (any resolution, any BGRA format).
    ///                  Will be letterboxed internally to 320×320.
    ///   - now:         Current timestamp from CACurrentMediaTime(). Injected so
    ///                  tests can advance time without sleeping.
    /// - Returns: Array of detected regions; empty if the rate limit skips inference.
    func detect(pixelBuffer: CVPixelBuffer,
                now: TimeInterval = CACurrentMediaTime()) -> [GloveDetectionResult] {

        // ── Rate-limit gate ────────────────────────────────────────────────
        if hasDetectedOnce && (now - lastInferenceTime) < rateLimitAfterDetection {
            return []  // silently skip — rate limit active
        }
        lastInferenceTime = now

        guard let model else { return [] }

        let frameSize = pixelBuffer.size

        // ── Step 1: Letterbox to 320×320 ──────────────────────────────────
        guard let (letterboxed, scale, padX, padY) = letterbox(pixelBuffer) else {
            return []
        }

        // ── Step 2: CVPixelBuffer → MLMultiArray [1, 3, 320, 320] Float32 ─
        // YOLOX expects raw pixel values in [0, 255] — NO normalisation.
        guard let inputArray = pixelBufferToMLArray(letterboxed) else { return [] }

        // ── Step 3: Run CoreML inference ───────────────────────────────────
        guard let input = try? MLDictionaryFeatureProvider(
            dictionary: ["images": MLFeatureValue(multiArray: inputArray)]
        ) else { return [] }

        let inferenceStart = CACurrentMediaTime()
        guard let rawOutput = try? model.model.prediction(from: input) else {
            print("❌ [GLOVE MODEL] Inference failed")
            return []
        }
        let inferenceMs = (CACurrentMediaTime() - inferenceStart) * 1000

        // ── Step 4: Collect per-stride FPN tensors ─────────────────────────
        // Each output is [1, 7, H, W] Float32 (channel-first).
        // The three tensors correspond to strides 8, 16, and 32.
        let strideOutputs: [(tensor: MLMultiArray, stride: Int)] = [
            // stride 8  → 40×40 grid detects smaller / closer hands
            ("var_1542", 8),
            // stride 16 → 20×20 grid
            ("var_1742", 16),
            // stride 32 → 10×10 grid detects larger / distant hands
            ("var_1942", 32),
        ].compactMap { name, stride in
            guard let arr = rawOutput.featureValue(for: name)?.multiArrayValue else {
                return nil
            }
            return (arr, stride)
        }

        guard !strideOutputs.isEmpty else { return [] }

        // ── Step 5: Decode all anchors from the three FPN levels ──────────
        var candidates: [GloveDetectionResult] = []

        for (tensor, stride) in strideOutputs {
            let decoded = decodeYOLOXHead(
                tensor: tensor,
                stride: stride,
                scale: scale,
                padX: padX,
                padY: padY,
                frameSize: frameSize
            )
            candidates.append(contentsOf: decoded)
        }

        let gloveRaw   = candidates.filter { $0.gloveClass == .glove   }.count
        let noGloveRaw = candidates.filter { $0.gloveClass == .noGlove }.count

        guard !candidates.isEmpty else { return [] }

        // ── Step 6: Non-Maximum Suppression ───────────────────────────────
        let final = nmsPerClass(candidates)

        let finalGlove   = final.filter { $0.gloveClass == .glove   }.count
        let finalNoGlove = final.filter { $0.gloveClass == .noGlove }.count

        if !final.isEmpty { hasDetectedOnce = true }

        return final
    }

    // MARK: - YOLOX FPN Head Decode

    /// Decodes one stride-level FPN output into candidate GloveDetectionResult values.
    ///
    /// YOLOX anchor-free decode for a single [1, 7, H, W] tensor:
    ///
    ///   cx = (col + sigmoid(ch0)) × stride           // sub-pixel x center in 320×320 space
    ///   cy = (row + sigmoid(ch1)) × stride           // sub-pixel y center
    ///   w  =  exp(ch2) × stride                      // width in 320×320 space
    ///   h  =  exp(ch3) × stride                      // height in 320×320 space
    ///
    ///   obj_conf  = sigmoid(ch4)                      // "is there anything here?"
    ///   cls_conf  = sigmoid(ch5 or ch6 per class)    // "which class is it?"
    ///   final_conf = obj_conf × cls_conf
    ///
    /// After computing the box in letterboxed 320×320 space, it is un-warped back
    /// to the original camera-frame coordinate space using the same (scale, padX, padY)
    /// values that Letterbox applied when preparing the input.
    private func decodeYOLOXHead(tensor: MLMultiArray,
                                 stride: Int,
                                 scale: CGFloat,
                                 padX: CGFloat,
                                 padY: CGFloat,
                                 frameSize: CGSize) -> [GloveDetectionResult] {

        // Tensor layout: [1, 7, H, W] channel-first Float32.
        let gridH   = tensor.shape[2].intValue
        let gridW   = tensor.shape[3].intValue
        let s0      = tensor.strides[0].intValue  // batch stride   (always 0 for single item)
        let sC      = tensor.strides[1].intValue  // channel stride
        let sH      = tensor.strides[2].intValue  // row stride
        let sW      = tensor.strides[3].intValue  // column stride
        let floats  = tensor.dataPointer.assumingMemoryBound(to: Float.self)

        var results: [GloveDetectionResult] = []

        for row in 0..<gridH {
            for col in 0..<gridW {

                // Base index for this (row, col) cell — batch index 0.
                let base = row * sH + col * sW + 0 * s0

                // ── Box channels ──────────────────────────────────────────
                // YOLOX does NOT bake sigmoid/exp into the TFLite graph;
                // those activations must be applied at decode time.
                let rawX  = floats[base + 0 * sC]
                let rawY  = floats[base + 1 * sC]
                let rawW  = floats[base + 2 * sC]
                let rawH  = floats[base + 3 * sC]

                // Sub-pixel center offset (0–1 relative to grid cell) + cell index,
                // then scale by stride to get coordinates in 320×320 letterbox space.
                let cx = (CGFloat(col) + CGFloat(sigmoid(rawX))) * CGFloat(stride)
                let cy = (CGFloat(row) + CGFloat(sigmoid(rawY))) * CGFloat(stride)

                // Width / height: exponential to keep values positive.
                // exp() is unclamped; the training range ensures reasonable values.
                let w  = CGFloat(expf(rawW)) * CGFloat(stride)
                let h  = CGFloat(expf(rawH)) * CGFloat(stride)

                // ── Objectness ────────────────────────────────────────────
                let objConf = sigmoid(floats[base + 4 * sC])

                // ── Class scores (2 classes: glove=0, no_glove=1) ─────────
                let gloveConf   = sigmoid(floats[base + 5 * sC])
                let noGloveConf = sigmoid(floats[base + 6 * sC])

                // Argmax class selection.
                let (bestCls, bestClsConf): (GloveClass, Float) =
                    (gloveConf >= noGloveConf)
                    ? (.glove,   gloveConf)
                    : (.noGlove, noGloveConf)

                // YOLOX final confidence = objectness × best-class confidence.
                let finalConf = objConf * bestClsConf
                guard finalConf >= confThreshold else { continue }

                // ── Un-letterbox: 320×320 → original frame space ──────────
                // Letterbox.preprocess stored (scale, padX, padY) used during
                // preprocessing. Reverse the same transform:
                //   original_coord = (letterbox_coord − pad) / scale
                let x1 = (cx - w / 2 - padX) / scale
                let y1 = (cy - h / 2 - padY) / scale
                let x2 = (cx + w / 2 - padX) / scale
                let y2 = (cy + h / 2 - padY) / scale

                guard x2 > x1, y2 > y1 else { continue }

                results.append(GloveDetectionResult(
                    rect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                    confidence: finalConf,
                    originalFrameSize: frameSize,
                    gloveClass: bestCls
                ))
            }
        }

        return results
    }

    // MARK: - Per-Class NMS

    /// Runs NMS independently for each GloveClass so a "glove" box and a
    /// "no_glove" box can coexist in the same spatial region (they carry
    /// different semantic meaning and should not suppress each other).
    private func nmsPerClass(_ detections: [GloveDetectionResult]) -> [GloveDetectionResult] {
        let gloves   = nmsSingle(detections.filter { $0.gloveClass == .glove })
        let noGloves = nmsSingle(detections.filter { $0.gloveClass == .noGlove })
        return gloves + noGloves
    }

    /// Standard greedy NMS for a single-class list (sorted by confidence descending).
    private func nmsSingle(_ items: [GloveDetectionResult]) -> [GloveDetectionResult] {
        let sorted = items.sorted { $0.confidence > $1.confidence }
        var suppressed = [Bool](repeating: false, count: sorted.count)
        var kept = [GloveDetectionResult]()

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

    // MARK: - Letterbox (320×320, pad = 114)

    /// Scales the camera frame proportionally to fit inside 320×320, then
    /// fills the remaining border with value 114 (YOLOX standard grey pad).
    ///
    /// - Returns: (resized buffer, scale, padX, padY) or nil on allocation failure.
    private func letterbox(_ px: CVPixelBuffer)
        -> (buffer: CVPixelBuffer, scale: CGFloat, padX: CGFloat, padY: CGFloat)? {

        let src  = CIImage(cvPixelBuffer: px)
        let srcW = src.extent.width
        let srcH = src.extent.height
        let size = CGFloat(inputSize)

        // Uniform scale that fits the image inside 320×320 with no distortion.
        let scale = min(size / srcW, size / srcH)
        let newW  = srcW * scale
        let newH  = srcH * scale

        // Symmetric padding to center the scaled image.
        let padX  = (size - newW) / 2
        let padY  = (size - newH) / 2

        // Scale + translate.  CIImage origin is bottom-left; CoreML rendering
        // compensates automatically when we render to a standard buffer.
        let transformed = src
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: padX, y: padY))

        // Allocate a 320×320 BGRA buffer.
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey:            inputSize as CFNumber,
            kCVPixelBufferHeightKey:           inputSize as CFNumber,
            kCVPixelBufferPixelFormatTypeKey:  kCVPixelFormatType_32BGRA as CFNumber,
        ]
        var outBuf: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault,
                                  inputSize, inputSize,
                                  kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary,
                                  &outBuf) == kCVReturnSuccess,
              let out = outBuf else { return nil }

        // Fill the entire output with the pad value (114) before rendering
        // so that any uncovered border pixels have the correct background.
        fillBuffer(out, value: UInt8(exactly: padValue) ?? 114)

        ciContext.render(transformed, to: out,
                         bounds: CGRect(x: 0, y: 0, width: inputSize, height: inputSize),
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        return (out, scale, padX, padY)
    }

    // MARK: - CVPixelBuffer → MLMultiArray

    /// Converts a 320×320 BGRA CVPixelBuffer to a [1, 3, 320, 320] Float32
    /// MLMultiArray with pixel values in [0, 255] and channel order RGB.
    ///
    /// Layout mapping:
    ///   array[0, 0, row, col] = R = BGRA_pixel.byte[2]
    ///   array[0, 1, row, col] = G = BGRA_pixel.byte[1]
    ///   array[0, 2, row, col] = B = BGRA_pixel.byte[0]
    private func pixelBufferToMLArray(_ px: CVPixelBuffer) -> MLMultiArray? {
        guard let array = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)],
            dataType: .float32
        ) else { return nil }

        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(px) else { return nil }

        let rowBytes    = CVPixelBufferGetBytesPerRow(px)
        let totalPixels = inputSize * inputSize

        // Direct pointer to the Float32 backing store of the MLMultiArray.
        // Stride layout: [batch=1][channel][row][col] — all strides are contiguous.
        let dst = array.dataPointer.assumingMemoryBound(to: Float.self)

        // Pointers to each channel's plane start in the MLMultiArray buffer.
        // R = offset 0, G = offset totalPixels, B = offset 2*totalPixels.
        let rPlane = dst
        let gPlane = dst + totalPixels
        let bPlane = dst + 2 * totalPixels

        for row in 0..<inputSize {
            // Row pointer into the BGRA pixel buffer.
            let rowPtr = base.advanced(by: row * rowBytes)
                             .assumingMemoryBound(to: UInt8.self)
            let rowBase = row * inputSize

            for col in 0..<inputSize {
                // BGRA byte layout: B at [4n], G at [4n+1], R at [4n+2], A at [4n+3].
                let px4 = col * 4
                rPlane[rowBase + col] = Float(rowPtr[px4 + 2])  // R
                gPlane[rowBase + col] = Float(rowPtr[px4 + 1])  // G
                bPlane[rowBase + col] = Float(rowPtr[px4 + 0])  // B
            }
        }

        return array
    }

    // MARK: - Utilities

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let ia = inter.width * inter.height
        return Float(ia / (a.width * a.height + b.width * b.height - ia))
    }

    /// Fills every pixel of a BGRA CVPixelBuffer with a single grey value.
    /// Used to paint the letterbox padding before rendering the scaled image.
    private func fillBuffer(_ px: CVPixelBuffer, value: UInt8) {
        CVPixelBufferLockBaseAddress(px, [])
        defer { CVPixelBufferUnlockBaseAddress(px, []) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(px)
        let height   = CVPixelBufferGetHeight(px)
        // Fill with (B=value, G=value, R=value, A=255) per pixel.
        // memset sets each byte to the same value, which works for grey + opaque alpha.
        memset(base, Int32(value), rowBytes * height)
    }
}
