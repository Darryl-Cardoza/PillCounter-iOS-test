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
                if CGRectGeometry.iou(det.rect, kept.rect) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }

            if shouldKeep { keep.append(det) }
        }

        return keep
    }
}
