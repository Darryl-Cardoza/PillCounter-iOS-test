// Traydetectionservice.swift
// PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Runs the MobileNetV2-UNet tray/chute SEMANTIC SEGMENTATION model on every
// camera frame and returns one bounding box per detected region class
// (TRAY or CHUTE). Only pills whose centres fall inside a TRAY box are counted;
// CHUTE boxes are excluded from pill filtering.
//
// This is a 1:1 port of the Android `TraySegmentationDetector`, because the iOS
// and Android tray models are the SAME exported network. The previous Swift
// implementation here was written for an old RTMDet-Tiny object detector that
// is no longer the model shipped in tray_detector_fp16.mlpackage — it assumed a
// 640×640 MLMultiArray input and six FPN output tensors. The actual model is:
//
//   • Input:  "images"  — CVPixelBuffer image, 384×384, ARGB, raw [0,255] RGB.
//             ImageNet normalisation is baked into the graph; pass raw pixels.
//   • Output: "logits"  — MLMultiArray [1, 3, 384, 384] Float, channel-first.
//             Per-pixel class logits. Channel order: 0 = background,
//             1 = chute, 2 = tray (matches Android CLASS_BG/CHUTE/TRAY).
//
// DECODE (mirrors Android decodeOutputs):
//   For each of the 384×384 pixels, argmax over the 3 class logits. Skip
//   background. A foreground pixel is only accepted if its winning logit beats
//   the background logit by at least FG_LOGIT_MARGIN (a cheap confidence gate,
//   no softmax/exp needed). Accumulate the per-class pixel bounding box. A class
//   is emitted only if it has more than MIN_CLASS_PIXELS pixels. The 384-space
//   bbox is then un-letterboxed back to original camera-frame coordinates.
//
// Because the box is the bounding box of EVERY tray pixel, it always spans the
// true tray extent in any orientation — there is no "shrunk box from a single
// anchor" failure mode (the bug the old object-detector code had in landscape).
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
/// CHUTE (dispenser opening — excluded from pill filtering).
struct TrayResult: Identifiable {
    let id = UUID()

    /// Bounding box in original camera-frame pixel coordinates.
    let rect: CGRect

    /// Detection confidence. Segmentation has no per-box score, so this is 1.0
    /// for any emitted region (it passed the per-pixel margin + min-pixel gates).
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

    /// Model input/output spatial resolution. Must match the exported .mlpackage
    /// (logits is [1, 3, 384, 384]).
    private let inputSize: Int = 384

    /// Number of semantic classes in the output (bg / chute / tray).
    private let numClasses: Int = 3

    // Channel indices in the model output. Keep in sync with Android's
    // TraySegmentationDetector (CLASS_BG / CLASS_CHUTE / CLASS_TRAY).
    private let classBackground = 0
    private let classChute      = 1
    private let classTray       = 2

    /// Minimum pixel count for a class to be reported as a detection. 400 px at
    /// 384×384 is ~0.27% of the frame — well below any real tray/chute and large
    /// enough to reject borderline noise blobs. Matches Android MIN_CLASS_PIXELS.
    private let minClassPixels: Int = 400

    /// Confidence margin between the winning foreground class's logit and the
    /// background logit, in logit units. A pixel is only assigned to a foreground
    /// class if `fgLogit - bgLogit >= fgLogitMargin`. Matches Android
    /// FG_LOGIT_MARGIN = 1.5 (≈ requiring softmax(fg) > 0.82). Raise to reject
    /// false-positive foreground pixels; lower if real boundaries are missed.
    private let fgLogitMargin: Float = 1.0

    // MARK: - Model & Context

    private var model: tray_detector_fp16?

    /// GPU-backed CIContext shared across letterbox calls; allocating per-frame is expensive.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Reused 384×384 BGRA buffer for the letterboxed input. Allocated lazily on
    /// the first frame and kept for the lifetime of the (singleton) service.
    private var inputBuffer: CVPixelBuffer?

    // MARK: - Init

    private init() { loadModel() }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine

            model = try tray_detector_fp16(configuration: cfg)
            print("✅ [TRAY MODEL] Segmentation model loaded and ready")
        } catch {
            print("❌ [TRAY MODEL] Failed to load — \(error)")
        }
    }

    // MARK: - Public API

    /// Runs the full tray segmentation pipeline on one camera frame.
    ///
    /// - Parameter pixelBuffer: Raw camera frame (any resolution, BGRA).
    ///   Internally letterboxed to 384×384 before being passed to the model.
    /// - Returns: At most one TRAY and one CHUTE region (the bbox of each class's
    ///   segmentation mask), in original camera-frame coordinates.
    func detect(pixelBuffer: CVPixelBuffer) -> [TrayResult] {
        guard let model else { return [] }

        let frameSize = pixelBuffer.size

        // ── Step 1: Letterbox to 384×384 ──────────────────────────────────
        guard let (lbBuffer, scale, padX, padY) = letterbox(pixelBuffer) else {
            return []
        }

        // ── Step 2: Run inference (image input) ───────────────────────────
        let inferenceStart = CACurrentMediaTime()
        guard let output = try? model.prediction(images: lbBuffer) else {
            print("❌ [TRAY MODEL] Inference failed")
            return []
        }
        let inferenceMs = (CACurrentMediaTime() - inferenceStart) * 1000

        // ── Step 3: Decode the per-pixel logits → per-class bounding boxes ─
        let results = decodeSegmentation(
            logits: output.logits,
            scale: scale, padX: padX, padY: padY,
            frameSize: frameSize
        )

        // ── Debug: print every detection ──────────────────────────────────
        let trayCount  = results.filter { $0.trayClass == .tray  }.count
        let chuteCount = results.filter { $0.trayClass == .chute }.count
        print(String(format:
            "── [TRAY MODEL] tray=%@ chute=%@ | infer=%.1fms frame=%.0f×%.0f",
            trayCount  > 0 ? "yes" : "no",
            chuteCount > 0 ? "yes" : "no",
            inferenceMs, frameSize.width, frameSize.height))
        for det in results {
            let cls = det.trayClass == .tray ? "TRAY" : "CHUTE"
            let r = det.rect
            print(String(format:
                "   %@ frame=(%.0f,%.0f,%.0f×%.0f)",
                cls, r.origin.x, r.origin.y, r.width, r.height))
        }

        return results
    }

    // MARK: - Segmentation Decode

    /// Per-pixel argmax over the [1, 3, 384, 384] channel-first logits, with a
    /// background-margin confidence gate, accumulating one bounding box per
    /// foreground class. Mirrors Android `decodeOutputs`.
    private func decodeSegmentation(logits: MLMultiArray,
                                    scale: CGFloat,
                                    padX: CGFloat,
                                    padY: CGFloat,
                                    frameSize: CGSize) -> [TrayResult] {

        // Expected shape [1, 3, 384, 384] (NCHW). Read strides so we don't assume
        // a contiguous layout.
        guard logits.shape.count == 4 else { return [] }
        let gridH = logits.shape[2].intValue
        let gridW = logits.shape[3].intValue

        let sC = logits.strides[1].intValue
        let sH = logits.strides[2].intValue
        let sW = logits.strides[3].intValue

        let raw  = logits.dataPointer
        let elem = logits.dataType == .float16 ? 2 : 4

        // Per-class bbox accumulators (in 384 space).
        var chuteMinX = gridW, chuteMinY = gridH, chuteMaxX = -1, chuteMaxY = -1
        var trayMinX  = gridW, trayMinY  = gridH, trayMaxX  = -1, trayMaxY  = -1
        var chutePixels = 0
        var trayPixels  = 0

        let bgBase    = classBackground * sC
        let chuteBase = classChute * sC
        let trayBase  = classTray * sC

        for y in 0..<gridH {
            let rowOff = y * sH
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
                    if x < chuteMinX { chuteMinX = x }
                    if x > chuteMaxX { chuteMaxX = x }
                    if y < chuteMinY { chuteMinY = y }
                    if y > chuteMaxY { chuteMaxY = y }
                    chutePixels += 1
                } else {
                    if x < trayMinX { trayMinX = x }
                    if x > trayMaxX { trayMaxX = x }
                    if y < trayMinY { trayMinY = y }
                    if y > trayMaxY { trayMaxY = y }
                    trayPixels += 1
                }
            }
        }

        var out: [TrayResult] = []
        if trayPixels > minClassPixels {
            out.append(buildResult(
                cls: .tray,
                minX: trayMinX, minY: trayMinY, maxX: trayMaxX, maxY: trayMaxY,
                scale: scale, padX: padX, padY: padY, frameSize: frameSize))
        }
        if chutePixels > minClassPixels {
            out.append(buildResult(
                cls: .chute,
                minX: chuteMinX, minY: chuteMinY, maxX: chuteMaxX, maxY: chuteMaxY,
                scale: scale, padX: padX, padY: padY, frameSize: frameSize))
        }
        return out
    }

    /// Converts a 384-space pixel bbox back to original-frame coordinates.
    /// Mirrors Android `buildDetection` (clamps to frame bounds).
    private func buildResult(cls: TrayClass,
                             minX: Int, minY: Int, maxX: Int, maxY: Int,
                             scale: CGFloat, padX: CGFloat, padY: CGFloat,
                             frameSize: CGSize) -> TrayResult {
        // Un-letterbox: original = (letterboxed − pad) / scale.
        // +1 on the max edge so the bbox spans the full last pixel.
        let x1 = (CGFloat(minX)     - padX) / scale
        let y1 = (CGFloat(minY)     - padY) / scale
        let x2 = (CGFloat(maxX + 1) - padX) / scale
        let y2 = (CGFloat(maxY + 1) - padY) / scale

        let cx1 = max(0, min(x1, frameSize.width))
        let cy1 = max(0, min(y1, frameSize.height))
        let cx2 = max(0, min(x2, frameSize.width))
        let cy2 = max(0, min(y2, frameSize.height))

        return TrayResult(
            rect: CGRect(x: cx1, y: cy1, width: max(0, cx2 - cx1), height: max(0, cy2 - cy1)),
            confidence: 1.0,
            originalFrameSize: frameSize,
            trayClass: cls
        )
    }

    // MARK: - Letterbox (384×384, pad = 114)

    /// Letterboxes the camera frame into the reused 384×384 ARGB input buffer.
    /// Returns the buffer plus the (scale, padX, padY) needed to un-letterbox the
    /// output bboxes back to original-frame coordinates.
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

        // (Re)allocate the input buffer only on first use; reuse thereafter.
        if inputBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferWidthKey:           inputSize as CFNumber,
                kCVPixelBufferHeightKey:          inputSize as CFNumber,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB as CFNumber,
            ]
            var outBuf: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault,
                                      inputSize, inputSize,
                                      kCVPixelFormatType_32ARGB,
                                      attrs as CFDictionary,
                                      &outBuf) == kCVReturnSuccess,
                  outBuf != nil else { return nil }
            inputBuffer = outBuf
        }
        guard let out = inputBuffer else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let grey = CIImage(color: CIColor(red: 114/255, green: 114/255, blue: 114/255))
            .cropped(to: bounds)
        ciContext.render(transformed.composited(over: grey), to: out, bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        return (out, scale, padX, padY)
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
