//
//  FaceAvatarRendererTests.swift
//  PillCounterTests
//
//  Geometry of the enrollment-thumbnail crop. The crop must stay square (the
//  row renders it with scaledToFill, which would distort a non-square image)
//  and must stay inside the frame (a rect hanging off an edge produces an empty
//  CIImage extent and therefore no avatar at all).
//

import Testing
import CoreGraphics
@testable import PillCounter

struct FaceAvatarRendererTests {

    private let frame = CGSize(width: 720, height: 1280)

    @Test func cropIsSquare() {
        // A non-square detection box — the padded result must still come out
        // square, sized by the longer edge.
        let box = CGRect(x: 300, y: 500, width: 100, height: 140)

        let crop = FaceAvatarRenderer.squareCropRect(around: box, frameSize: frame)

        #expect(crop != nil)
        #expect(crop?.width == crop?.height)
    }

    @Test func cropAddsPaddingAroundTheFace() {
        let box = CGRect(x: 300, y: 500, width: 100, height: 100)

        let crop = FaceAvatarRenderer.squareCropRect(around: box, frameSize: frame)

        // 40% on each side of a 100pt box = 180pt.
        #expect(crop?.width == 180)
        // Padding is symmetric, so the crop stays centred on the face.
        #expect(crop?.midX == box.midX)
        #expect(crop?.midY == box.midY)
    }

    @Test func cropStaysInsideTheFrameAtTheTopLeft() {
        // A face near the corner: padding would push the crop negative.
        let box = CGRect(x: 5, y: 5, width: 100, height: 100)

        let crop = FaceAvatarRenderer.squareCropRect(around: box, frameSize: frame)

        #expect(crop?.minX == 0)
        #expect(crop?.minY == 0)
        // Shifted back inside, NOT trimmed — full side length is preserved.
        #expect(crop?.width == 180)
        #expect(crop?.height == 180)
    }

    @Test func cropStaysInsideTheFrameAtTheBottomRight() {
        let box = CGRect(x: frame.width - 105, y: frame.height - 105, width: 100, height: 100)

        let crop = FaceAvatarRenderer.squareCropRect(around: box, frameSize: frame)

        #expect(crop?.maxX == frame.width)
        #expect(crop?.maxY == frame.height)
        #expect(crop?.width == 180)
    }

    @Test func cropSideIsCappedToTheSmallerFrameDimension() {
        // A face filling the frame: the padded box is wider than the frame, so
        // the side must clamp to the frame's short edge rather than produce a
        // rect that cannot fit.
        let box = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)

        let crop = FaceAvatarRenderer.squareCropRect(around: box, frameSize: frame)

        #expect(crop?.width == frame.width)
        #expect(crop?.height == frame.width)
        #expect(crop?.minX == 0)
        #expect((crop?.maxY ?? 0) <= frame.height)
    }

    @Test func degenerateBoxYieldsNoCrop() {
        let zeroWidth = CGRect(x: 100, y: 100, width: 0, height: 100)
        let zeroHeight = CGRect(x: 100, y: 100, width: 100, height: 0)

        #expect(FaceAvatarRenderer.squareCropRect(around: zeroWidth, frameSize: frame) == nil)
        #expect(FaceAvatarRenderer.squareCropRect(around: zeroHeight, frameSize: frame) == nil)
    }

    @Test func emptyFrameYieldsNoCrop() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(FaceAvatarRenderer.squareCropRect(around: box, frameSize: .zero) == nil)
    }
}
