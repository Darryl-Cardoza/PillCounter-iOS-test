//
//  MaskComponentsTests.swift
//  PillCounterTests
//
//  Mirrors the Android MaskComponentsTest suite: the largest 4-connected blob
//  of a segmentation mask is what the tray/chute bbox and mask are built from,
//  so a stray blob elsewhere in the frame cannot stretch the pill-model crop.
//

import Testing
@testable import PillCounter

struct MaskComponentsTests {

    private let size = 32

    private func mask(_ rects: [(x0: Int, y0: Int, x1: Int, y1: Int)]) -> [Bool] {
        var m = [Bool](repeating: false, count: size * size)
        for r in rects {
            for y in r.y0..<r.y1 { for x in r.x0..<r.x1 { m[y * size + x] = true } }
        }
        return m
    }

    @Test func emptyMaskYieldsNil() {
        #expect(MaskComponents(size: size).largest([Bool](repeating: false, count: size * size)) == nil)
    }

    @Test func singleBlobIsReturnedWholeWithItsBBox() throws {
        let c = try #require(MaskComponents(size: size).largest(mask([(2, 3, 10, 9)])))
        #expect(c.pixelCount == 8 * 6)
        #expect(c.componentCount == 1)
        #expect(c.minX == 2 && c.minY == 3 && c.maxX == 9 && c.maxY == 8)
        #expect(c.mask[5 * size + 5])
        #expect(!c.mask[0])
    }

    @Test func largestOfTwoBlobsWinsAndStrayIsDroppedFromBBoxAndMask() throws {
        // Main 10x10 tray blob at the top-left; stray 3x3 blob far away at the bottom-right.
        let c = try #require(MaskComponents(size: size).largest(mask([(0, 0, 10, 10), (25, 25, 28, 28)])))
        #expect(c.pixelCount == 100)
        #expect(c.componentCount == 2)
        #expect(c.maxX == 9 && c.maxY == 9)
        #expect(c.mask[5 * size + 5])
        #expect(!c.mask[26 * size + 26])
    }

    @Test func diagonallyTouchingPixelsAreSeparateComponents() throws {
        var m = [Bool](repeating: false, count: size * size)
        m[0] = true                 // (0,0)
        m[1 * size + 1] = true      // (1,1) — touches (0,0) only at a corner
        m[1 * size + 2] = true      // (2,1) — 4-connected to (1,1)
        let c = try #require(MaskComponents(size: size).largest(m))
        #expect(c.componentCount == 2)
        #expect(c.pixelCount == 2)
        #expect(!c.mask[0])
        #expect(c.mask[1 * size + 1])
    }

    @Test func instanceCanBeReusedAcrossCalls() throws {
        let mc = MaskComponents(size: size)
        let first = try #require(mc.largest(mask([(0, 0, 4, 4)])))
        let second = try #require(mc.largest(mask([(10, 10, 20, 20), (0, 0, 2, 2)])))
        #expect(first.pixelCount == 16)
        #expect(second.pixelCount == 100)
        #expect(second.minX == 10)
        // The first result is untouched by the second call.
        #expect(first.mask[0])
        #expect(!second.mask[0])
    }
}
