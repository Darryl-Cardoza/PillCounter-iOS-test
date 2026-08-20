//
//  FaceDetectionResult.swift
//  PillCounter
//
//  One YuNet detection, decoded from the raw multi-head output into
//  original-frame pixel coordinates. Shared by enrollment AND (later)
//  authentication — this is the contract FaceAligner/FaceQualityChecker
//  consume, regardless of who produced it.
//

import CoreGraphics

struct FaceLandmarks {
    let rightEye: CGPoint
    let leftEye: CGPoint
    let nose: CGPoint
    let rightMouthCorner: CGPoint
    let leftMouthCorner: CGPoint
}

struct FaceDetectionResult {
    /// Bounding box in original camera-frame pixel coordinates.
    let boundingBox: CGRect

    /// YuNet landmarks, in the same coordinate space as `boundingBox`.
    let landmarks: FaceLandmarks

    /// Detection confidence in [0, 1] (obj * cls score).
    let confidence: Float

    /// Pixel dimensions of the camera frame this detection came from.
    let frameSize: CGSize
}
