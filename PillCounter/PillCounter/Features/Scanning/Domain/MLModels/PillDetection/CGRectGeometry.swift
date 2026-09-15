//
//  CGRectGeometry.swift
//  PillCounter
//
//  Shared box-geometry helpers for the Scanning ML pipeline (NMS, PillTracker,
//  GloveDetectionService) — one IoU/intersection/median implementation instead
//  of several near-identical private copies.
//

import CoreGraphics

enum CGRectGeometry {

    /// Intersection area of two rects, 0 when they don't overlap.
    static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        return inter.width * inter.height
    }

    /// Intersection-over-union of two rects.
    static func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = intersectionArea(a, b)
        guard inter > 0 else { return 0 }
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? Float(inter / union) : 0
    }
}

extension Array where Element == CGFloat {
    /// Lower-middle element of the sorted array; 0 when empty.
    func median() -> CGFloat {
        guard !isEmpty else { return 0 }
        return sorted()[count / 2]
    }
}
