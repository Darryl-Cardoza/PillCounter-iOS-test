//
//  TrayDetectionService.swift
//  PillCounter
//

import CoreML
import CoreVideo
import UIKit

struct TrayResult: Identifiable {
    let id = UUID()
    let rect: CGRect
    let confidence: Float
    let originalFrameSize: CGSize
}

final class TrayDetectionService {

    static let shared = TrayDetectionService()

    private var model: trayBest?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let inputSize: Int       = 640
    private let confThreshold: Float = 0.80
    private let iouThreshold: Float  = 0.45
    private let trayClassIndex: Int  = 1

    private init() { loadModel() }

    private func loadModel() {
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuOnly
            model = try trayBest(configuration: cfg)
        } catch {
        }
    }

    // MARK: - Public

    func detect(pixelBuffer: CVPixelBuffer) -> [TrayResult] {
        guard let model else { return [] }

        let frameSize = pixelBuffer.size

        guard let (resized, scale, padX, padY) = letterbox(pixelBuffer) else {
            return []
        }

        let input = trayBestInput(image: resized)
        guard let output = try? model.prediction(input: input) else { return [] }

        let raw        = output.var_1326
        let numAnchors = raw.shape[2].intValue   // 8400
        let numAttribs = raw.shape[1].intValue   // 38
        let scoreCol   = 4 + trayClassIndex      // 5

        guard scoreCol < numAttribs else { return [] }

        struct Cand { let box: CGRect; let score: Float }
        var cands = [Cand]()

        for a in 0 ..< numAnchors {
            let score = raw[0, scoreCol, a]
            guard score >= confThreshold else { continue }

            // trayBest outputs cx/cy/w/h in letterboxed pixel space (0…640).
            // Do NOT multiply by inputSize — that is only needed for models
            // that output normalised 0…1 coords (like `best` with built-in NMS).
            let cx = CGFloat(raw[0, 0, a])
            let cy = CGFloat(raw[0, 1, a])
            let w  = CGFloat(raw[0, 2, a])
            let h  = CGFloat(raw[0, 3, a])

            let x1 = (cx - w / 2 - padX) / scale
            let y1 = (cy - h / 2 - padY) / scale
            let x2 = (cx + w / 2 - padX) / scale
            let y2 = (cy + h / 2 - padY) / scale

            cands.append(Cand(
                box: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                score: score
            ))
        }

        guard !cands.isEmpty else { return [] }

        let kept = nms(cands.map { $0.box }, scores: cands.map { $0.score })
        let results = kept.map { i in
            TrayResult(rect: cands[i].box,
                       confidence: cands[i].score,
                       originalFrameSize: frameSize)
        }

        return results
    }

    // MARK: - Letterbox

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

        let attrs: CFDictionary = [
            kCVPixelBufferWidthKey:           inputSize,
            kCVPixelBufferHeightKey:          inputSize,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ] as CFDictionary

        var outBuf: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault,
                                  inputSize, inputSize,
                                  kCVPixelFormatType_32BGRA,
                                  attrs, &outBuf) == kCVReturnSuccess,
              let out = outBuf else { return nil }

        ciContext.render(transformed, to: out,
                         bounds: CGRect(x: 0, y: 0,
                                        width: inputSize, height: inputSize),
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        return (out, scale, padX, padY)
    }

    // MARK: - NMS

    private func nms(_ boxes: [CGRect], scores: [Float]) -> [Int] {
        let order = scores.indices.sorted { scores[$0] > scores[$1] }
        var suppressed = [Bool](repeating: false, count: boxes.count)
        var keep = [Int]()
        for i in order {
            guard !suppressed[i] else { continue }
            keep.append(i)
            for j in order where j != i && !suppressed[j] {
                if iou(boxes[i], boxes[j]) > iouThreshold { suppressed[j] = true }
            }
        }
        return keep
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let ia = inter.width * inter.height
        return Float(ia / (a.width * a.height + b.width * b.height - ia))
    }
}

// MARK: - MLMultiArray [batch, attrib, anchor]
private extension MLMultiArray {
    subscript(_ b: Int, _ c: Int, _ a: Int) -> Float {
        self[b * strides[0].intValue
           + c * strides[1].intValue
           + a * strides[2].intValue].floatValue
    }
}   
