//
//  PillDetectionService.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import CoreML
import Foundation
import UIKit

struct DetectionResult: Identifiable, Equatable {
    let id = UUID()  // Unique identifier for SwiftUI
    let rect: CGRect
    let confidence: Float
    let originalFrameSize: CGSize

    var center: CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    // Equatable conformance
    static func == (lhs: DetectionResult, rhs: DetectionResult) -> Bool {
        lhs.id == rhs.id
    }
}

final class PillDetectionService {

    private let model = PillDetector.shared.model
    private let inputSize: CGFloat = 640
    private let iouThreshold: Double = 0.75
    private let confThreshold: Double = 0.70

    private let stabilizer = CountStabilizer(windowSize: 7)

    func detect(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping ([DetectionResult], Int) -> Void
    ) {

        guard let model else {
            return
        }


        // PREPROCESS
        guard let resized = Letterbox.preprocess(
            pixelBuffer,
            targetSize: Int(inputSize)
        ) else {
            return
        }


        // BUILD MODEL INPUT
        let input = bestInput(
            image: resized,
            iouThreshold: iouThreshold,
            confidenceThreshold: confThreshold
        )


        // PREDICT
        let start = CFAbsoluteTimeGetCurrent()

        guard let output = try? model.prediction(input: input) else {
            completion([], 0)
            return
        }

        var inferenceTime = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // DECODE
        let decoded = decodeDetections(
            coords: output.coordinates,
            conf: output.confidence,
            originalSize: pixelBuffer.size,
            scaleInfo: Letterbox.currentScaleInfo
        )


        // NMS
        let final = NMS.run(
            detections: decoded,
            iouThreshold: Float(iouThreshold)
        )


        final.enumerated().forEach { index, det in

        }

        // STABILIZER
        let stabilized = stabilizer.update(rawCount: final.count)



        completion(final, stabilized)
    }


    private func decodeDetections(
        coords: MLMultiArray,
        conf: MLMultiArray,
        originalSize: CGSize,
        scaleInfo: Letterbox.ScaleInfo?
    ) -> [DetectionResult] {

        var results = [DetectionResult]()
        let rows = coords.shape[0].intValue

        for i in 0..<rows {
            let cx = coords[i, 0].cgFloat * inputSize
            let cy = coords[i, 1].cgFloat * inputSize
            let w = coords[i, 2].cgFloat * inputSize
            let h = coords[i, 3].cgFloat * inputSize

            let score = conf[i, 0].floatValue
            if score < Float(confThreshold) { continue }

            var x1 = cx - w / 2
            var y1 = cy - h / 2
            var x2 = cx + w / 2
            var y2 = cy + h / 2

            if let s = scaleInfo {
                x1 = (x1 - s.padX) / s.scale
                y1 = (y1 - s.padY) / s.scale
                x2 = (x2 - s.padX) / s.scale
                y2 = (y2 - s.padY) / s.scale
            }

            let rect = CGRect(
                x: x1, y: y1,
                width: x2 - x1,
                height: y2 - y1)

            results.append(
                .init(
                    rect: rect, confidence: score,
                    originalFrameSize: originalSize))
        }

        return results
    }
}

extension MLMultiArray {
    subscript(i: Int, j: Int) -> NSNumber {
        return self[i * strides[0].intValue + j * strides[1].intValue]
    }
}

extension NSNumber {
    var cgFloat: CGFloat { CGFloat(doubleValue) }
}

extension CVPixelBuffer {
    var size: CGSize {
        CGSize(
            width: CVPixelBufferGetWidth(self),
            height: CVPixelBufferGetHeight(self))
    }
}
