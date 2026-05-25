//
//  NMS.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import Foundation
import CoreGraphics

final class NMS {

    static func run(detections: [DetectionResult],
                    iouThreshold: Float) -> [DetectionResult] {

        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var keep = [DetectionResult]()

        for det in sorted {
            var shouldKeep = true

            for kept in keep {
                if iou(det.rect, kept.rect) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }

            if shouldKeep { keep.append(det) }
        }

        return keep
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b).area
        if intersection <= 0 { return 0 }

        let union = a.area + b.area - intersection
        return Float(intersection / union)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
