//
//  FaceQualityChecker.swift
//  PillCounter
//
//  Reusable face-quality gate, used by both enrollment and (later)
//  authentication so "is this face good enough to embed" is decided in one
//  place.
//
//  Deliberately minimal, matching this app's proven-working Android
//  (FaceQualityGate.kt) and Python (quality_gate()) reference
//  implementations exactly: face width in pixels (too small / too close),
//  plus Laplacian-variance sharpness. Nothing else hard-rejects. An earlier
//  version of this checker added a detector-confidence recheck, an
//  edge-margin check, a landmarks-inside-expanded-box check, and a roll
//  check — none of which exist in either reference, and which (especially
//  the roll check, before the camera's video connection orientation was
//  fixed) could reject every single real frame. Do not add gates back
//  without a specific, evidenced reason — extra hard gates are exactly what
//  broke this pipeline before.
//

import CoreVideo
import CoreGraphics

final class FaceQualityChecker {

    static let shared = FaceQualityChecker()
    private init() {}

    // MARK: - Hard-gate thresholds (verbatim from the reference implementations)

    /// Face bounding-box width, in pixels of the ORIGINAL (not letterboxed)
    /// camera frame. Matches MIN_FACE_WIDTH_PX = 90 in both references —
    /// those assume a ~480px-wide capture frame; this app's capture is
    /// 1280x720, so this is scaled proportionally (90/480 * 1280 ≈ 240).
    var minFaceWidthPx: CGFloat = 240
    /// Face wider than this fraction of the frame = too close. Matches
    /// MAX_FACE_WIDTH_RATIO = 0.85 in both references, unscaled (a ratio).
    var maxFaceWidthRatio: CGFloat = 0.85

    // MARK: - Soft-score inputs (never hard-reject)

    /// Reference value for scoring only (ENROLL_MIN_SHARPNESS in both
    /// reference implementations) — not a rejection threshold here. Blur is
    /// intentionally soft: a Laplacian-variance measurement on a raw camera
    /// crop is notoriously exposure- and scale-sensitive, and a hard reject
    /// on it is a classic cause of a capture flow that never completes.
    private let softMinSharpness: Float = 45

    // MARK: - Public API

    /// Full quality gate for one camera frame given ALL detections YuNet
    /// returned for it (not just the best one) — needed to reject
    /// multi-face frames rather than silently picking a winner.
    func check(detections: [FaceDetectionResult], pixelBuffer: CVPixelBuffer) -> FaceQualityResult {
        guard !detections.isEmpty else {
            Log("Quality: REJECT faceNotFound (0 detections)")
            return .rejected(.faceNotFound)
        }
        guard detections.count == 1 else {
            Log("Quality: REJECT multipleFaces (\(detections.count) detections)")
            return .rejected(.multipleFaces)
        }

        return check(detection: detections[0], pixelBuffer: pixelBuffer)
    }

    /// Quality gate for a single, already-isolated detection. Only the
    /// width checks below can reject a frame — sharpness only affects
    /// `qualityScore`.
    func check(detection: FaceDetectionResult, pixelBuffer: CVPixelBuffer) -> FaceQualityResult {
        let frame = detection.frameSize
        let box = detection.boundingBox

        // TEMP DEBUG — remove after root-causing bug 1/bug 2.
        let l = detection.landmarks
        Log("DEBUG detect: score=\(String(format: "%.3f", detection.confidence)) box=(\(Int(box.minX)),\(Int(box.minY)),\(Int(box.width))x\(Int(box.height))) frame=\(Int(frame.width))x\(Int(frame.height))")
        Log("DEBUG landmarks: rEye=\(l.rightEye) lEye=\(l.leftEye) nose=\(l.nose) rMouth=\(l.rightMouthCorner) lMouth=\(l.leftMouthCorner)")

        guard box.width >= minFaceWidthPx else {
            Log("Quality: REJECT faceTooSmall (width \(box.width) < \(minFaceWidthPx))")
            return .rejected(.faceTooSmall, qualityScore: Float(box.width))
        }
        guard box.width <= frame.width * maxFaceWidthRatio else {
            Log("Quality: REJECT faceTooClose (width \(box.width) > \(frame.width * maxFaceWidthRatio))")
            return .rejected(.faceTooClose, qualityScore: Float(box.width))
        }

        // TEMP DEBUG landmark-sanity check — not gating yet, log only.
        let sane = landmarkSanityCheck(detection)
        Log("DEBUG landmarkSanity: \(sane ? "PASS" : "FAIL")")

        let yawDegrees = yawDegreesEstimate(detection)
        let pitchDegrees = pitchDegreesEstimate(detection)
        let sharpness = sharpnessScore(pixelBuffer: pixelBuffer, box: box) ?? softMinSharpness
        let sharpnessNormalized = min(1, max(0, sharpness / (softMinSharpness * 2)))

        Log("Quality: ACCEPT conf=\(String(format: "%.2f", detection.confidence)) width=\(String(format: "%.0f", box.width)) sharpness=\(String(format: "%.1f", sharpness)) yaw=\(String(format: "%.1f", yawDegrees))° pitch=\(String(format: "%.1f", pitchDegrees))°")
        return .accepted(qualityScore: sharpnessNormalized, yawDegrees: yawDegrees, pitchDegrees: pitchDegrees)
    }

    // MARK: - TEMP DEBUG landmark sanity (log-only, not gating)

    /// Coarse geometry check: eyes should be roughly level and separated,
    /// nose should sit between eye line and mouth line, all 5 points should
    /// fall inside the bounding box (expanded 20%). Occluded/bad detections
    /// often violate one of these even when confidence score looks fine.
    private func landmarkSanityCheck(_ detection: FaceDetectionResult) -> Bool {
        let l = detection.landmarks
        let box = detection.boundingBox

        let eyeDist = hypot(l.leftEye.x - l.rightEye.x, l.leftEye.y - l.rightEye.y)
        guard eyeDist > CGFloat(box.width) * 0.15 else { return false }

        let eyeMidY = (l.leftEye.y + l.rightEye.y) / 2
        let mouthMidY = (l.leftMouthCorner.y + l.rightMouthCorner.y) / 2
        guard l.nose.y > eyeMidY, l.nose.y < mouthMidY else { return false }
        guard mouthMidY > eyeMidY else { return false }

        let expanded = box.insetBy(dx: -box.width * 0.2, dy: -box.height * 0.2)
        let points = [l.rightEye, l.leftEye, l.nose, l.rightMouthCorner, l.leftMouthCorner]
        return points.allSatisfy { expanded.contains($0) }
    }

    // MARK: - Pose estimates (guidance/scoring only, never gating)

    /// Yaw estimate in degrees from the nose's horizontal offset relative to
    /// the eye midpoint, normalized by inter-eye distance. Coarse — callers
    /// requiring a pose target should smooth this over several consecutive
    /// frames rather than trust one reading.
    private func yawDegreesEstimate(_ detection: FaceDetectionResult) -> Float {
        let l = detection.landmarks
        let eyeMidX = (l.leftEye.x + l.rightEye.x) / 2
        let eyeDist = hypot(l.leftEye.x - l.rightEye.x, l.leftEye.y - l.rightEye.y)
        guard eyeDist > 1 else { return 0 }
        let ratio = Float((l.nose.x - eyeMidX) / eyeDist)
        return ratio * 55
    }

    /// Pitch estimate in degrees from the nose's vertical position relative
    /// to the eye-to-mouth span. Positive = chin up.
    private func pitchDegreesEstimate(_ detection: FaceDetectionResult) -> Float {
        let l = detection.landmarks
        let eyeMidY = (l.leftEye.y + l.rightEye.y) / 2
        let mouthMidY = (l.leftMouthCorner.y + l.rightMouthCorner.y) / 2
        let span = mouthMidY - eyeMidY
        guard abs(span) > 1 else { return 0 }
        let neutralRatio: CGFloat = 0.45
        let noseRatio = (l.nose.y - eyeMidY) / span
        let deviation = Float(neutralRatio - noseRatio)
        return deviation * 60
    }

    /// Laplacian-variance sharpness estimate over the face crop, using a
    /// coarse sampled grid — same metric as both reference implementations'
    /// `sharpness()`, computed inline here instead of on a separate resized
    /// crop for efficiency. Advisory only (see header).
    private func sharpnessScore(pixelBuffer: CVPixelBuffer, box: CGRect) -> Float? {
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
