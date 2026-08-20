//
//  FaceQualityCheckerTests.swift
//  PillCounterTests
//
//  FaceQualityChecker is deliberately minimal — face width (too small / too
//  close) plus sharpness-as-soft-score, matching this app's proven-working
//  Android/Python reference gates exactly. See FaceQualityChecker.swift's
//  header for why extra gates were removed.
//

import Testing
import CoreGraphics
import CoreVideo
@testable import PillCounter

struct FaceQualityCheckerTests {

    private let frameSize = CGSize(width: 1280, height: 720)

    /// A well-sized detection over `frameSize` (matches the default
    /// minFaceWidthPx=240 / maxFaceWidthRatio=0.85 gate).
    private func goodDetection(width: CGFloat = 400) -> FaceDetectionResult {
        let box = CGRect(x: 400, y: 200, width: width, height: width)
        let landmarks = FaceLandmarks(
            rightEye: CGPoint(x: box.minX + width * 0.25, y: box.minY + width * 0.3),
            leftEye: CGPoint(x: box.minX + width * 0.75, y: box.minY + width * 0.3),
            nose: CGPoint(x: box.midX, y: box.minY + width * 0.5),
            rightMouthCorner: CGPoint(x: box.minX + width * 0.3, y: box.minY + width * 0.75),
            leftMouthCorner: CGPoint(x: box.minX + width * 0.7, y: box.minY + width * 0.75)
        )
        return FaceDetectionResult(boundingBox: box, landmarks: landmarks, confidence: 0.9, frameSize: frameSize)
    }

    /// Solid-color BGRA buffer with random per-pixel noise inside the face
    /// box, so the Laplacian-variance sharpness score has real texture to
    /// measure rather than a flat, zero-variance region.
    private func noisyPixelBuffer(size: CGSize) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA, nil, &pb
        )
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var seed: UInt32 = 42
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                seed = seed &* 1103515245 &+ 12345
                let value = UInt8(truncatingIfNeeded: seed >> 16)
                let p = base + y * bytesPerRow + x * 4
                p[0] = value; p[1] = value; p[2] = value; p[3] = 255
            }
        }
        return buffer
    }

    @Test func acceptsGoodFrontalDetection() {
        let checker = FaceQualityChecker.shared
        let buffer = noisyPixelBuffer(size: frameSize)
        let result = checker.check(detection: goodDetection(), pixelBuffer: buffer)
        #expect(result.isAcceptable)
    }

    @Test func checkWithNoDetectionsRejectsAsFaceNotFound() {
        let checker = FaceQualityChecker.shared
        let buffer = noisyPixelBuffer(size: frameSize)
        let result = checker.check(detections: [], pixelBuffer: buffer)
        #expect(!result.isAcceptable)
        #expect(result.reason == .faceNotFound)
    }

    @Test func checkWithMultipleDetectionsRejectsAsMultipleFaces() {
        let checker = FaceQualityChecker.shared
        let buffer = noisyPixelBuffer(size: frameSize)
        let result = checker.check(detections: [goodDetection(), goodDetection()], pixelBuffer: buffer)
        #expect(!result.isAcceptable)
        #expect(result.reason == .multipleFaces)
    }

    @Test func rejectsTooSmallFace() {
        let checker = FaceQualityChecker.shared
        let buffer = noisyPixelBuffer(size: frameSize)
        let result = checker.check(detection: goodDetection(width: 50), pixelBuffer: buffer)
        #expect(!result.isAcceptable)
        #expect(result.reason == .faceTooSmall)
    }

    @Test func rejectsTooCloseFace() {
        let checker = FaceQualityChecker.shared
        let buffer = noisyPixelBuffer(size: frameSize)
        // 1280 * 0.85 = 1088 — anything wider than that should reject.
        let result = checker.check(detection: goodDetection(width: 1200), pixelBuffer: buffer)
        #expect(!result.isAcceptable)
        #expect(result.reason == .faceTooClose)
    }

    @Test func acceptsFaceAtMinimumWidthThreshold() {
        let checker = FaceQualityChecker.shared
        let buffer = noisyPixelBuffer(size: frameSize)
        let result = checker.check(detection: goodDetection(width: checker.minFaceWidthPx), pixelBuffer: buffer)
        #expect(result.isAcceptable)
    }
}
