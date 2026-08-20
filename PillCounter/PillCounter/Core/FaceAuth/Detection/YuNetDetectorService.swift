//
//  YuNetDetectorService.swift
//  PillCounter
//
// ─────────────────────────────────────────────────────────────────────────────
// PURPOSE
// ───────
// Runs the PRE-TRAINED YuNet face detector (yunet_640x640_float16.mlpackage)
// and decodes its raw multi-head output into FaceDetectionResult values in
// original camera-frame coordinates. This is the ONLY place YuNet's output
// layout is interpreted — enrollment and (later) authentication both call
// `detect(pixelBuffer:)` and never touch the raw model output themselves,
// so detection behaves identically in both flows (spec section 16).
//
// MODEL I/O (inspected directly from the .mlpackage spec — this model has no
// bundled NMS/decode, unlike the tray segmentation model):
//   • Input:  "input" — MLMultiArray Float16 [1, 640, 640, 3], NHWC, RGB in
//             [0, 255] (no ImageNet normalization baked in for YuNet; the
//             reference OpenCV/libfacedetection export takes raw pixel values).
//   • Output: 12 tensors, 3 detection heads at strides {8, 16, 32} over a
//             640×640 input → grids of {80×80, 40×40, 20×20} = {6400, 1600, 400}
//             cells. Per head: cls [1,N,1], obj [1,N,1], bbox [1,N,4], kps [1,N,10].
//             Tensor name → (stride, kind) mapping is the standard YuNet ONNX
//             export order also used by OpenCV's FaceDetectorYN:
//               Identity    = cls  @ stride 8   (6400)
//               Identity_1  = cls  @ stride 16  (1600)
//               Identity_2  = kps  @ stride 16  (1600)
//               Identity_3  = kps  @ stride 32  (400)
//               Identity_4  = obj  @ stride 32  (400)
//               Identity_5  = obj  @ stride 8   (6400)
//               Identity_6  = obj  @ stride 16  (1600)
//               Identity_7  = obj  @ stride 32  (400)
//               Identity_8  = bbox @ stride 8   (6400)
//               Identity_9  = bbox @ stride 16  (1600)
//               Identity_10 = bbox @ stride 32  (400)
//               Identity_11 = kps  @ stride 8   (6400)
//             (Grouped below by shape.last — cls/obj share [*,1], bbox is
//             [*,4], kps is [*,10] — so the mapping is derived from shape,
//             not hardcoded to the Identity_N names, which are not stable
//             across export runs.)
//
// DECODE (anchor-free, one prior per grid cell — standard YuNet/libface
// detection postprocess):
//   score = sqrt(cls * obj)     ← cls/obj tensors are ALREADY sigmoid
//                                  probabilities inside the exported graph
//                                  (the network's Sigmoid is the final op
//                                  before output) — applying sigmoid() again
//                                  here would crush real high-confidence
//                                  scores toward ~0.7 and was the root cause
//                                  of "almost never detects a clearly visible
//                                  face." Matches OpenCV's FaceDetectorYN
//                                  postProcess, which reads these blobs raw.
//   cx = (gridX + bbox[0]) * stride,  cy = (gridY + bbox[1]) * stride
//   w  = exp(bbox[2]) * stride,       h  = exp(bbox[3]) * stride
//   landmark_i = (gridX + kps[2i], gridY + kps[2i+1]) * stride
//   Then confidence threshold + greedy NMS across all strides combined.
// ─────────────────────────────────────────────────────────────────────────────

import CoreML
import CoreVideo
import CoreImage
import CoreGraphics

final class YuNetDetectorService {

    static let shared = YuNetDetectorService()

    // MARK: - Configuration

    private let inputSize: Int = 640
    private let strides: [Int] = [8, 16, 32]
    private let gridSizes: [Int] = [80, 40, 20]     // 640/stride

    /// Detections below this score are discarded before NMS.
    var confidenceThreshold: Float = 0.6
    /// IoU threshold for greedy NMS across all strides.
    var nmsIoUThreshold: Float = 0.3
    /// Enrollment/auth-facing detection cap. Only the top-scoring face is
    /// used by the pipeline, but we keep more around so "multiple faces"
    /// can be reported accurately instead of silently picking the best one.
    private let maxDetections: Int = 8

    // MARK: - Model & context

    private var model: yunet_640x640_float16?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var inputBuffer: CVPixelBuffer?

    private init() { loadModel() }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            model = try yunet_640x640_float16(configuration: cfg)
            Log("YuNet: model loaded and ready")
        } catch {
            Log("YuNet: failed to load — \(error)")
        }
    }

    // MARK: - Public API

    /// Runs YuNet on one camera frame and returns all detections above
    /// `confidenceThreshold`, sorted by descending confidence, in original
    /// camera-frame coordinates. Empty array on any failure (no model, no
    /// letterbox, inference error) — callers treat that as "no face found".
    func detect(pixelBuffer: CVPixelBuffer) -> [FaceDetectionResult] {
        guard let model else {
            Log("YuNet: model not loaded")
            return []
        }
        let frameSize = pixelBuffer.size

        guard let (lbBuffer, scale, padX, padY) = letterbox(pixelBuffer) else {
            Log("YuNet: letterbox failed for frame \(frameSize)")
            return []
        }
        guard let inputArray = pixelBufferToNHWCFloat16(lbBuffer) else {
            Log("YuNet: NHWC conversion failed")
            return []
        }
        guard let output = try? model.prediction(input: inputArray) else {
            Log("YuNet: model.prediction threw")
            return []
        }

        let raw = decodeAllStrides(output: output)
        let kept = nonMaxSuppression(raw)

        if kept.isEmpty {
            let topScore = raw.map(\.score).max() ?? 0
            Log("YuNet: 0 detections above threshold \(confidenceThreshold) — best raw score this frame: \(topScore)")
        } else {
            Log("YuNet: \(kept.count) detection(s), scores: \(kept.map { String(format: "%.2f", $0.score) })")
        }

        return kept.map { det in
            unletterbox(det, scale: scale, padX: padX, padY: padY, frameSize: frameSize)
        }
    }

    // MARK: - Raw (letterboxed-space) detection, pre-NMS

    private struct RawDetection {
        let box: CGRect          // in 640×640 letterboxed space, x/y/w/h
        let landmarks: [CGPoint] // 5 points, same space
        let score: Float
    }

    private func decodeAllStrides(output: yunet_640x640_float16Output) -> [RawDetection] {
        // Group the 12 output tensors by role using shape, not name — export
        // names (Identity_N) are not guaranteed stable, shapes are (see header).
        let all: [(name: String, array: MLMultiArray)] = [
            ("Identity", output.Identity), ("Identity_1", output.Identity_1),
            ("Identity_2", output.Identity_2), ("Identity_3", output.Identity_3),
            ("Identity_4", output.Identity_4), ("Identity_5", output.Identity_5),
            ("Identity_6", output.Identity_6), ("Identity_7", output.Identity_7),
            ("Identity_8", output.Identity_8), ("Identity_9", output.Identity_9),
            ("Identity_10", output.Identity_10), ("Identity_11", output.Identity_11),
        ]

        func cells(_ a: MLMultiArray) -> Int { a.shape.count >= 2 ? a.shape[1].intValue : 0 }
        func lastDim(_ a: MLMultiArray) -> Int { a.shape.count >= 3 ? a.shape[2].intValue : 1 }

        var results: [RawDetection] = []

        for (strideIdx, stride) in strides.enumerated() {
            let gridN = gridSizes[strideIdx]
            let numCells = gridN * gridN

            // Two tensors share [*, N, 1] at this cell-count — cls and obj,
            // both already post-sigmoid probabilities. Their roles are
            // interchangeable here: score = sqrt(a * b) is symmetric, so
            // which one is "cls" vs "obj" doesn't matter as long as both
            // come from the SAME stride's pair.
            let oneDim = all.filter { cells($0.array) == numCells && lastDim($0.array) == 1 }
            let fourDim = all.filter { cells($0.array) == numCells && lastDim($0.array) == 4 }
            let tenDim = all.filter { cells($0.array) == numCells && lastDim($0.array) == 10 }

            guard oneDim.count >= 2, let bboxArr = fourDim.first?.array,
                  let kpsArr = tenDim.first?.array else { continue }

            let a0 = oneDim[0].array
            let a1 = oneDim[1].array

            for cellIdx in 0..<numCells {
                let gy = cellIdx / gridN
                let gx = cellIdx % gridN

                // a0/a1 are already post-sigmoid probabilities in the
                // exported graph — do NOT apply sigmoid() again here.
                let s0 = readScalar(a0, cellIdx)
                let s1 = readScalar(a1, cellIdx)
                let score = max(0, s0 * s1).squareRoot()
                guard score >= confidenceThreshold else { continue }

                let bx = readScalar(bboxArr, cellIdx, dim: 0)
                let by = readScalar(bboxArr, cellIdx, dim: 1)
                let bw = readScalar(bboxArr, cellIdx, dim: 2)
                let bh = readScalar(bboxArr, cellIdx, dim: 3)

                let cx = (Float(gx) + bx) * Float(stride)
                let cy = (Float(gy) + by) * Float(stride)
                let w  = exp(bw) * Float(stride)
                let h  = exp(bh) * Float(stride)

                let x1 = cx - w / 2
                let y1 = cy - h / 2

                var points: [CGPoint] = []
                for i in 0..<5 {
                    let kx = readScalar(kpsArr, cellIdx, dim: i * 2)
                    let ky = readScalar(kpsArr, cellIdx, dim: i * 2 + 1)
                    let px = (Float(gx) + kx) * Float(stride)
                    let py = (Float(gy) + ky) * Float(stride)
                    points.append(CGPoint(x: CGFloat(px), y: CGFloat(py)))
                }

                results.append(RawDetection(
                    box: CGRect(x: CGFloat(x1), y: CGFloat(y1), width: CGFloat(w), height: CGFloat(h)),
                    landmarks: points,
                    score: score
                ))
            }
        }

        return results
    }

    // MARK: - NMS

    private func nonMaxSuppression(_ dets: [RawDetection]) -> [RawDetection] {
        let sorted = dets.sorted { $0.score > $1.score }
        var kept: [RawDetection] = []

        for det in sorted {
            if kept.count >= maxDetections { break }
            let overlaps = kept.contains { iou($0.box, det.box) > nmsIoUThreshold }
            if !overlaps { kept.append(det) }
        }
        return kept
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = Float(inter.width * inter.height)
        let unionArea = Float(a.width * a.height + b.width * b.height) - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }

    // MARK: - Coordinate mapping

    private func unletterbox(
        _ det: RawDetection, scale: CGFloat, padX: CGFloat, padY: CGFloat, frameSize: CGSize
    ) -> FaceDetectionResult {
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - padX) / scale, y: (p.y - padY) / scale)
        }
        let x1 = (det.box.minX - padX) / scale
        let y1 = (det.box.minY - padY) / scale
        let x2 = (det.box.maxX - padX) / scale
        let y2 = (det.box.maxY - padY) / scale

        let box = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        let pts = det.landmarks.map(map)

        let landmarks = FaceLandmarks(
            rightEye: pts[0], leftEye: pts[1], nose: pts[2],
            rightMouthCorner: pts[3], leftMouthCorner: pts[4]
        )

        return FaceDetectionResult(
            boundingBox: box,
            landmarks: landmarks,
            confidence: det.score,
            frameSize: frameSize
        )
    }

    // MARK: - MLMultiArray helpers

    /// Reads element `[0, cellIdx, dim]` from an MLMultiArray shaped
    /// [1, N, lastDim], handling both Float16 and Float32 storage.
    @inline(__always)
    private func readScalar(_ arr: MLMultiArray, _ cellIdx: Int, dim: Int = 0) -> Float {
        let sN = arr.strides[1].intValue
        let sD = arr.shape.count >= 3 ? arr.strides[2].intValue : 1
        let offset = cellIdx * sN + dim * sD
        let elem = arr.dataType == .float16 ? 2 : 4
        let raw = arr.dataPointer
        if elem == 2 {
            let bits = raw.load(fromByteOffset: offset * 2, as: UInt16.self)
            return Float(Float16(bitPattern: bits))
        }
        return raw.load(fromByteOffset: offset * 4, as: Float.self)
    }

    // MARK: - Letterbox (640×640, pad = 0 black) + NHWC Float16 conversion

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

        if inputBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferWidthKey:  inputSize as CFNumber,
                kCVPixelBufferHeightKey: inputSize as CFNumber,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA as CFNumber,
            ]
            var outBuf: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, inputSize, inputSize,
                                      kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                                      &outBuf) == kCVReturnSuccess, outBuf != nil else { return nil }
            inputBuffer = outBuf
        }
        guard let out = inputBuffer else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let black = CIImage(color: .black).cropped(to: bounds)
        ciContext.render(transformed.composited(over: black), to: out, bounds: bounds,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        return (out, scale, padX, padY)
    }

    /// Converts the letterboxed BGRA pixel buffer into the [1,640,640,3]
    /// Float16 NHWC array YuNet expects.
    ///
    /// Channel order: BGR, not RGB — matches this app's proven-working
    /// Android/Python reference pipelines exactly. Both of those read an
    /// RGB-native source (Android ARGB_8888 / a BGR OpenCV Mat is passed
    /// through unchanged in Python) and deliberately feed the model
    /// B,G,R-first. Our CVPixelBuffer is natively BGRA, so channel 0/1/2 are
    /// ALREADY B,G,R — copy them in that native order, don't reorder to RGB
    /// (an earlier version of this file did, which silently swapped R/B on
    /// every pixel going into the detector).
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
