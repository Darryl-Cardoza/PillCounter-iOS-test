//
//  FaceCaptureValidator.swift
//  PillCounter
//
//  Strict "is this frame complete enough to embed" gate, run AFTER
//  FaceQualityChecker's existing box-size/sharpness check and BEFORE
//  alignment + SFace embedding, identically at enrollment and verify time.
//
//  NOTE ON HISTORY: FaceQualityChecker.swift documents that an earlier
//  version of THIS APP added hard gates on detector-confidence, landmark
//  geometry, and roll, and they were removed after over-rejecting real
//  frames — root-caused mainly to a since-fixed camera-orientation bug.
//  This validator reintroduces the same class of checks, deliberately kept
//  in a separate file/function so it can be disabled or deleted in one
//  place (just stop calling `isFaceCaptureValid`) without touching the
//  existing, proven box-size/sharpness gate in FaceQualityChecker. If real
//  captures start failing broadly again, suspect THIS file first.
//
//  All checks are pure geometry/arithmetic over an already-computed
//  FaceDetectionResult plus one small pixel-buffer crop for sharpness — no
//  extra ML inference, so this adds negligible per-frame cost.
//

import CoreGraphics
import CoreVideo

/// Specific reason a capture failed the strict completeness gate, mapped to
/// on-screen user guidance by the caller (see `userMessage`).
enum FaceCaptureRejectionReason {
    case lowConfidence
    case badAspectRatio
    case eyesTooClose
    case landmarksOutOfOrder
    case mouthTooNarrow
    case landmarkOutsideBox
    case tooMuchRoll
    case tooMuchYaw
    case tooBlurry

    /// Short, user-facing instruction. Caller decides exact copy/L10n key;
    /// this is a sane default.
    var userMessage: String {
        switch self {
        case .lowConfidence, .landmarkOutsideBox, .landmarksOutOfOrder:
            return "Face partially covered or unclear — reposition and try again."
        case .badAspectRatio, .eyesTooClose, .mouthTooNarrow:
            return "Move closer and make sure your whole face is visible."
        case .tooMuchRoll:
            return "Hold your head level."
        case .tooMuchYaw:
            return "Turn to face the camera directly."
        case .tooBlurry:
            return "Hold still."
        }
    }
}

enum FaceCaptureValidator {

    // MARK: - Thresholds (see each check for rationale)

    private static let minAcceptConfidence: Float = 0.9
    private static let minAspectRatio: CGFloat = 0.65
    private static let maxAspectRatio: CGFloat = 1.15
    private static let minEyeDistanceRatio: CGFloat = 0.25
    private static let minMouthWidthRatio: CGFloat = 0.15
    /// Small outward margin so a landmark exactly on the box edge (common
    /// and legitimate) doesn't get flagged as "outside."
    private static let landmarkBoxMargin: CGFloat = 0.08
    private static let maxRollDegrees: Float = 20
    /// Yaw proxy is a ratio of eye-to-nose distances, not degrees — 0.3 is
    /// an empirical stand-in for "~30° off frontal", not a literal angle.
    private static let maxYawRatio: Float = 0.3
    private static let minSharpnessVariance: Float = 45

    // MARK: - Public API

    /// Strict single-frame completeness gate. Run once per candidate frame,
    /// immediately after detection and any existing box-size check, and
    /// before alignment/embedding. Identical at enrollment and verify time.
    ///
    /// - Parameters:
    ///   - face: detection to validate (box + landmarks + confidence).
    ///   - frame: the camera pixel buffer the detection came from, used only
    ///     for the sharpness crop.
    /// - Returns: nil if the capture is valid and safe to embed, otherwise
    ///   the specific reason it was rejected.
    static func isFaceCaptureValid(face: FaceDetectionResult, frame: CVPixelBuffer) -> FaceCaptureRejectionReason? {
        let box = face.boundingBox
        let l = face.landmarks

        // 1. Detection confidence — stricter than the decoder's base
        // accept/NMS threshold. A frame can clear NMS with a mediocre score
        // and still be a partial/garbled detection; this raises the bar
        // specifically for "safe to embed."
        guard face.confidence >= minAcceptConfidence else {
            return .lowConfidence
        }

        // 2. Aspect ratio sanity. Box-size (width) range is checked
        // upstream by FaceQualityChecker; a sliver/partial detection often
        // keeps a plausible width while its height collapses or balloons.
        guard box.height > 0 else { return .badAspectRatio }
        let aspect = box.width / box.height
        guard aspect >= minAspectRatio, aspect <= maxAspectRatio else {
            return .badAspectRatio
        }

        // 3a. Eye-to-eye distance vs box width — catches a detection that
        // only really covers one side of the face (the box is sized off
        // e.g. hair/chin extent while the eyes are bunched to one side).
        let eyeDist = hypot(l.leftEye.x - l.rightEye.x, l.leftEye.y - l.rightEye.y)
        guard eyeDist >= box.width * minEyeDistanceRatio else {
            return .eyesTooClose
        }

        // 3b. Vertical ordering — both eyes above nose, nose above both
        // mouth corners. Catches upside-down/garbled landmark sets a bad
        // detection can still produce even with a plausible score.
        let eyeMidY = (l.leftEye.y + l.rightEye.y) / 2
        guard l.nose.y > eyeMidY,
              l.nose.y < l.leftMouthCorner.y,
              l.nose.y < l.rightMouthCorner.y else {
            return .landmarksOutOfOrder
        }

        // 3c. Mouth-corner-to-mouth-corner distance vs box width.
        let mouthDist = hypot(l.leftMouthCorner.x - l.rightMouthCorner.x, l.leftMouthCorner.y - l.rightMouthCorner.y)
        guard mouthDist >= box.width * minMouthWidthRatio else {
            return .mouthTooNarrow
        }

        // 3d. All 5 landmarks inside the box (with small margin). A point
        // outside the box means the detector's landmark head and box head
        // disagree — a reliable signal of a partial/unstable detection.
        let marginBox = box.insetBy(dx: -box.width * landmarkBoxMargin, dy: -box.height * landmarkBoxMargin)
        let points = [l.rightEye, l.leftEye, l.nose, l.rightMouthCorner, l.leftMouthCorner]
        guard points.allSatisfy({ marginBox.contains($0) }) else {
            return .landmarkOutsideBox
        }

        // 4a. Roll — angle between the two eyes. Large roll on a real,
        // complete face is rare in a guided capture flow; it's a strong
        // tell for a garbled/partial landmark set.
        let rollRadians = atan2(l.leftEye.y - l.rightEye.y, l.leftEye.x - l.rightEye.x)
        let rollDegrees = abs(Float(rollRadians * 180 / .pi))
        guard rollDegrees <= maxRollDegrees else {
            return .tooMuchRoll
        }

        // 4b. Yaw proxy — asymmetry between left-eye-to-nose and
        // right-eye-to-nose distances, normalized by their sum. A face
        // turned well off frontal is likely to have one side partially
        // occluded even when the landmark regressor "fills in" a plausible
        // point for it.
        let leftEyeToNose = hypot(l.leftEye.x - l.nose.x, l.leftEye.y - l.nose.y)
        let rightEyeToNose = hypot(l.rightEye.x - l.nose.x, l.rightEye.y - l.nose.y)
        let eyeToNoseSum = leftEyeToNose + rightEyeToNose
        if eyeToNoseSum > 0 {
            let yawRatio = Float(abs(leftEyeToNose - rightEyeToNose) / eyeToNoseSum)
            guard yawRatio <= maxYawRatio else {
                return .tooMuchYaw
            }
        }

        // 5. Sharpness — same Laplacian-variance metric FaceQualityChecker
        // already computes as advisory-only; here it hard-gates. Computed
        // on the same face-box crop for consistency with that scoring.
        let sharpness = sharpnessVariance(pixelBuffer: frame, box: box) ?? 0
        guard sharpness >= minSharpnessVariance else {
            return .tooBlurry
        }

        return nil
    }

    // MARK: - Sharpness (mirrors FaceQualityChecker's private implementation)

    private static func sharpnessVariance(pixelBuffer: CVPixelBuffer, box: CGRect) -> Float? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let x0 = max(0, Int(box.minX))
        let y0 = max(0, Int(box.minY))
        let x1 = min(width, Int(box.maxX))
        let y1 = min(height, Int(box.maxY))
        guard x1 - x0 > 2, y1 - y0 > 2 else { return nil }

        let ptr = base.assumingMemoryBound(to: UInt8.self)

        @inline(__always) func luma(_ x: Int, _ y: Int) -> Float {
            let p = ptr + y * bytesPerRow + x * 4 // BGRA
            let b = Float(p[0]), g = Float(p[1]), r = Float(p[2])
            return 0.299 * r + 0.587 * g + 0.114 * b
        }

        var sumSq: Float = 0
        var sum: Float = 0
        var count = 0
        let stepX = max(1, (x1 - x0) / 40)
        let stepY = max(1, (y1 - y0) / 40)

        var y = y0 + 1
        while y < y1 - 1 {
            var x = x0 + 1
            while x < x1 - 1 {
                let lap = -4 * luma(x, y) + luma(x - 1, y) + luma(x + 1, y) + luma(x, y - 1) + luma(x, y + 1)
                sum += lap
                sumSq += lap * lap
                count += 1
                x += stepX
            }
            y += stepY
        }
        guard count > 0 else { return nil }
        let mean = sum / Float(count)
        let variance = sumSq / Float(count) - mean * mean
        return variance
    }
}
