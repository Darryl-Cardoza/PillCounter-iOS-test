// Traydetectionservice.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Runs the MobileNetV2-UNet tray/chute SEMANTIC SEGMENTATION model on every
// camera frame and returns one region per detected class (TRAY or CHUTE), each
// carrying its per-pixel mask. Only pills whose centres fall on the TRAY mask
// are counted; the CHUTE mask is excluded from pill filtering.
//
// This is a 1:1 port of the Android `TraySegmentationDetector`, because the iOS
// and Android tray models are the SAME exported network (trained in
// `dispensesure-tray-model`). The model is:
//
//   • Input:  "images"  — MLMultiArray [1, 3, 384, 384] Float32, NCHW, RGB,
//             raw [0, 255]. ImageNet normalisation is baked into the graph; pass
//             raw pixel values. (`tray_fp16.mlpackage` takes a multi-array, not
//             an image, so the pixels are copied into planes here.)
//   • Output: "logits"  — MLMultiArray [1, 3, 384, 384] Float, channel-first.
//             Per-pixel class logits. Channel order: 0 = background,
//             1 = chute, 2 = tray (matches Android CLASS_BG/CHUTE/TRAY).
//
// INPUT GEOMETRY — a SQUASH, not a letterbox. The training set was resized to
// 384×384 by non-uniform scaling (dataset.md, "The resize is a squash, not a
// letterbox"), so the camera frame is stretched straight to 384×384 with no
// padding, each axis with its own scale. Feeding a letterboxed frame instead (as
// this class once did, with grey bars) is train/serve skew the model never saw:
// the bars and the changed aspect produced stray "tray" pixels on nearby objects.
//
// DECODE (mirrors Android decodeOutputs):
//   For each of the 384×384 pixels, argmax over the 3 class logits. Skip
//   background. A foreground pixel is only accepted if its winning logit beats
//   the background logit by at least fgLogitMargin (a cheap confidence gate,
//   no softmax/exp needed). A class is emitted only if it has more than
//   minClassPixels pixels.
//
// OUTPUT GEOMETRY — one blob per class. The bbox and mask reported for a class
// come from the LARGEST 4-connected component of its pixels (`MaskComponents`);
// a stray blob elsewhere in the frame no longer stretches the tray box — and
// with it the pill model's crop — across unrelated objects. The 384-space bbox
// is then un-squashed back to camera-frame coordinates, per axis.
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
/// rect is in the original camera-frame pixel coordinates.
/// trayClass indicates whether this is a TRAY (pill-counting region) or a
/// CHUTE (dispenser opening — excluded from pill filtering).
///
/// 1:1 port of Android `TrayDetection`. The crucial field is `mask`: the actual
/// per-pixel segmentation mask in `maskSize`×`maskSize` (384) space, row-major.
/// Pill containment is tested against this mask (see `containsPoint`), NOT the
/// bounding box — the bbox of an angled or L-shaped tray covers large non-tray
/// areas (including the chute), which is why bbox-based counting let chute pills
/// through and was fragile at odd angles. The mask is exact at any orientation.
struct TrayResult: Identifiable {
    let id = UUID()

    /// Bounding box in original camera-frame pixel coordinates (overlay + pill crop).
    let rect: CGRect

    /// Detection confidence. Segmentation has no per-box score, so this is 1.0
    /// for any emitted region (it passed the per-pixel margin + min-pixel gates).
    let confidence: Float

    /// Pixel dimensions of the raw camera frame this result was generated from.
    let originalFrameSize: CGSize

    /// Which region class was detected at this location.
    let trayClass: TrayClass

    /// Packed per-pixel mask in `maskSize`×`maskSize` (384) space, row-major:
    /// `mask[y * maskSize + x]` is true where this class' largest blob is.
    let mask: [Bool]

    /// Side length of the square mask (384). 0 if no mask (legacy/empty).
    let maskSize: Int

    /// Maps original-frame coords → mask (384) space. The input is a squash, so
    /// each axis has its own scale and there is no pad:
    /// `x_mask = x * maskScaleX`, `y_mask = y * maskScaleY`.
    /// Mirrors Android `TrayDetection.scaleInfo` (scale / scaleY, pad 0).
    let maskScaleX: CGFloat
    let maskScaleY: CGFloat

    /// True if the original-frame point (x, y) lands on a set mask pixel.
    /// Direct port of Android `TrayDetection.containsPoint`. Falls back to the
    /// bbox test only when no mask is present.
    func containsPoint(_ x: CGFloat, _ y: CGFloat) -> Bool {
        if maskSize > 0, !mask.isEmpty {
            let xMask = Int(x * maskScaleX)
            let yMask = Int(y * maskScaleY)
            if xMask < 0 || xMask >= maskSize || yMask < 0 || yMask >= maskSize { return false }
            return mask[yMask * maskSize + xMask]
        }
        return rect.contains(CGPoint(x: x, y: y))
    }

    /// True if this region contains any point of the square of half-side `radius`
    /// around (x, y) — the deploy contract's "dilate the tray mask by half a pill"
    /// without rewriting the mask. Sampled at the centre, the four edge midpoints
    /// and the four corners of that square; a radius of 0 is exactly `containsPoint`.
    func containsPointWithin(_ x: CGFloat, _ y: CGFloat, radius: CGFloat) -> Bool {
        if containsPoint(x, y) { return true }
        if radius <= 0 { return false }
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                if containsPoint(x + CGFloat(dx) * radius, y + CGFloat(dy) * radius) { return true }
            }
        }
        return false
    }
}

// MARK: - TrayDetectionService

final class TrayDetectionService {

    // MARK: - Singleton

    static let shared = TrayDetectionService()

    // MARK: - Configuration

    /// Model input/output spatial resolution. Must match the exported .mlpackage
    /// (images is [1, 3, 384, 384], logits is [1, 3, 384, 384]).
    private let inputSize: Int = 384

    /// Number of semantic classes in the output (bg / chute / tray).
    private let numClasses: Int = 3

    // Channel indices in the model output. Keep in sync with Android's
    // TraySegmentationDetector (CLASS_BG / CLASS_CHUTE / CLASS_TRAY).
    private let classBackground = 0
    private let classChute      = 1
    private let classTray       = 2

    /// Minimum pixel count for a class' largest blob to be reported as a
    /// detection. 400 px at 384×384 is ~0.27% of the frame — well below any real
    /// tray/chute and large enough to reject borderline noise blobs. Matches
    /// Android MIN_CLASS_PIXELS.
    private let minClassPixels: Int = 400

    /// Confidence margin between the winning foreground class's logit and the
    /// background logit, in logit units. A pixel is only assigned to a foreground
    /// class if `fgLogit - bgLogit >= fgLogitMargin`. Matches Android
    /// FG_LOGIT_MARGIN = 1.5 (≈ requiring softmax(fg) > 0.82). Raise to reject
    /// false-positive foreground pixels; lower if real boundaries are missed.
    private let fgLogitMargin: Float = 1.5

    // MARK: - Model & Context

    private var model: tray_fp16?

    /// GPU-backed CIContext shared across squash calls; allocating per-frame is expensive.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Reused 384×384 BGRA buffer the frame is squashed into before its pixels
    /// are copied to `inputArray`. Allocated lazily on the first frame.
    private var squashBuffer: CVPixelBuffer?

    /// Reused model input, [1, 3, 384, 384] Float32 NCHW. Allocated lazily.
    private var inputArray: MLMultiArray?

    /// Largest-connected-component scratch (visited set + stack), reused per frame.
    private let components: MaskComponents

    // MARK: - Init

    private init() {
        components = MaskComponents(size: inputSize)
        loadModel()
    }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine

            model = try tray_fp16(configuration: cfg)
            print("✅ [TRAY MODEL] Segmentation model tray_fp16 loaded and ready")
        } catch {
            print("❌ [TRAY MODEL] Failed to load — \(error)")
        }
    }

    // MARK: - Public API

    /// Runs the full tray segmentation pipeline on one camera frame.
    ///
    /// - Parameter pixelBuffer: Raw camera frame (any resolution, BGRA).
    ///   Internally squashed to 384×384 (no letterbox) before being passed to the model.
    /// - Returns: At most one TRAY and one CHUTE region (the largest blob of each
    ///   class), in original camera-frame coordinates.
    func detect(pixelBuffer: CVPixelBuffer) -> [TrayResult] {
        guard let model else { return [] }

        let frameSize = pixelBuffer.size
        guard frameSize.width > 0, frameSize.height > 0 else { return [] }

        // ── Step 1: Squash to the 384×384 NCHW float input ─────────────────
        guard let input = squashToInput(pixelBuffer) else { return [] }

        // ── Step 2: Run inference ─────────────────────────────────────────
        guard let output = try? model.prediction(images: input) else {
            return []
        }

        // ── Step 3: Decode the per-pixel logits → one blob per class ───────
        // Frame → mask mapping of the squash: per-axis scale, no pad.
        let scaleX = CGFloat(inputSize) / frameSize.width
        let scaleY = CGFloat(inputSize) / frameSize.height
        return decodeSegmentation(
            logits: output.logits,
            scaleX: scaleX, scaleY: scaleY,
            frameSize: frameSize
        )
    }

    // MARK: - Segmentation Decode

    /// Per-pixel argmax over the [1, 3, 384, 384] channel-first logits, with a
    /// background-margin confidence gate, then the largest connected blob per
    /// foreground class. Mirrors Android `decodeOutputs`.
    private func decodeSegmentation(logits: MLMultiArray,
                                    scaleX: CGFloat,
                                    scaleY: CGFloat,
                                    frameSize: CGSize) -> [TrayResult] {

        // Expected shape [1, 3, 384, 384] (NCHW). Read strides so we don't assume
        // a contiguous layout.
        guard logits.shape.count == 4 else { return [] }
        let gridH = logits.shape[2].intValue
        let gridW = logits.shape[3].intValue
        guard gridH == inputSize, gridW == inputSize else { return [] }

        let sC = logits.strides[1].intValue
        let sH = logits.strides[2].intValue
        let sW = logits.strides[3].intValue

        let raw  = logits.dataPointer
        let elem = logits.dataType == .float16 ? 2 : 4

        // Per-class masks, gridW×gridH (=384²) Bool arrays, row-major, exactly
        // like Android's chuteMaskScratch / trayMaskScratch BitSets.
        var chutePixels = 0
        var trayPixels  = 0
        var chuteMask = [Bool](repeating: false, count: gridW * gridH)
        var trayMask  = [Bool](repeating: false, count: gridW * gridH)

        let bgBase    = classBackground * sC
        let chuteBase = classChute * sC
        let trayBase  = classTray * sC

        for y in 0..<gridH {
            let rowOff = y * sH
            let maskRow = y * gridW
            for x in 0..<gridW {
                let colOff = rowOff + x * sW

                let bg = readF32(raw, at: colOff + bgBase,    elem: elem)
                let ch = readF32(raw, at: colOff + chuteBase, elem: elem)
                let tr = readF32(raw, at: colOff + trayBase,  elem: elem)

                // Argmax over {bg, chute, tray}; skip background.
                // (Matches Android: bg>=ch&&bg>=tr -> bg; ch>=tr -> chute; else tray.)
                if bg >= ch && bg >= tr { continue }

                let isChute = ch >= tr
                let fgLogit = isChute ? ch : tr

                // Confidence gate: foreground must beat background by the margin.
                guard fgLogit - bg >= fgLogitMargin else { continue }

                if isChute {
                    chuteMask[maskRow + x] = true
                    chutePixels += 1
                } else {
                    trayMask[maskRow + x] = true
                    trayPixels += 1
                }
            }
        }

        // One physical object per class: keep only the largest connected blob.
        // Its bbox and mask are what the caller sees, so a stray blob elsewhere
        // in the frame neither stretches the crop nor lets pills on it count.
        var out: [TrayResult] = []
        if trayPixels > minClassPixels,
           let tray = components.largest(trayMask), tray.pixelCount > minClassPixels {
            out.append(buildResult(cls: .tray, component: tray, maskSize: gridW,
                                   scaleX: scaleX, scaleY: scaleY, frameSize: frameSize))
        }
        if chutePixels > minClassPixels,
           let chute = components.largest(chuteMask), chute.pixelCount > minClassPixels {
            out.append(buildResult(cls: .chute, component: chute, maskSize: gridW,
                                   scaleX: scaleX, scaleY: scaleY, frameSize: frameSize))
        }
        return out
    }

    /// Converts a component's 384-space bbox back to original-frame coordinates
    /// (per-axis un-squash) and attaches its mask. Mirrors Android `buildDetection`.
    private func buildResult(cls: TrayClass,
                             component: MaskComponents.Component,
                             maskSize: Int,
                             scaleX: CGFloat, scaleY: CGFloat,
                             frameSize: CGSize) -> TrayResult {
        // +1 on the max edge so the bbox spans the full last pixel.
        let x1 = CGFloat(component.minX)     / scaleX
        let y1 = CGFloat(component.minY)     / scaleY
        let x2 = CGFloat(component.maxX + 1) / scaleX
        let y2 = CGFloat(component.maxY + 1) / scaleY

        let cx1 = max(0, min(x1, frameSize.width))
        let cy1 = max(0, min(y1, frameSize.height))
        let cx2 = max(0, min(x2, frameSize.width))
        let cy2 = max(0, min(y2, frameSize.height))

        return TrayResult(
            rect: CGRect(x: cx1, y: cy1, width: max(0, cx2 - cx1), height: max(0, cy2 - cy1)),
            confidence: 1.0,
            originalFrameSize: frameSize,
            trayClass: cls,
            mask: component.mask,
            maskSize: maskSize,
            maskScaleX: scaleX,
            maskScaleY: scaleY
        )
    }

    // MARK: - Squash (384×384, no padding) → NCHW Float32 input

    /// Stretches the camera frame to 384×384 with independent x/y scale (the
    /// training-set resize), renders it into the reused BGRA buffer, and copies
    /// the pixels into the reused `[1, 3, 384, 384]` Float32 array as raw
    /// [0, 255] RGB planes.
    private func squashToInput(_ px: CVPixelBuffer) -> MLMultiArray? {
        let src  = CIImage(cvPixelBuffer: px)
        let srcW = src.extent.width
        let srcH = src.extent.height
        let size = CGFloat(inputSize)
        guard srcW > 0, srcH > 0 else { return nil }

        // Move the extent origin to zero before scaling so a cropped/oriented
        // CIImage still lands at (0, 0).
        let transformed = src
            .transformed(by: CGAffineTransform(translationX: -src.extent.origin.x,
                                               y: -src.extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: size / srcW, y: size / srcH))

        // (Re)allocate the scratch buffer and input array only on first use.
        if squashBuffer == nil {
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
                  outBuf != nil else { return nil }
            squashBuffer = outBuf
        }
        if inputArray == nil {
            inputArray = try? MLMultiArray(
                shape: [1, NSNumber(value: numClasses), NSNumber(value: inputSize), NSNumber(value: inputSize)],
                dataType: .float32)
        }
        guard let buffer = squashBuffer, let array = inputArray else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ciContext.render(transformed, to: buffer, bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        // BGRA bytes → R, G, B float planes (NCHW), raw [0, 255].
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        let sC = array.strides[1].intValue
        let sH = array.strides[2].intValue
        let sW = array.strides[3].intValue
        let dst = array.dataPointer.assumingMemoryBound(to: Float.self)
        let rBase = 0 * sC, gBase = 1 * sC, bBase = 2 * sC

        for y in 0..<inputSize {
            let row = y * bytesPerRow
            let outRow = y * sH
            for x in 0..<inputSize {
                let p = row + x * 4              // B, G, R, A
                let o = outRow + x * sW
                dst[rBase + o] = Float(bytes[p + 2])
                dst[gBase + o] = Float(bytes[p + 1])
                dst[bBase + o] = Float(bytes[p])
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
}
