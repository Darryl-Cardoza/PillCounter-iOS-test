//
//  CountStabilizerTests.swift
//  PillCounterTests
//
//  Median over the last 5 frame counts, latched: the displayed number only moves
//  after 3 consecutive medians agree on the new value (deploy contract).
//

import Testing
@testable import PillCounter

struct CountStabilizerTests {

    @Test func aNewValueIsDisplayedOnlyAfterThreeAgreeingFrames() {
        let s = CountStabilizer()
        #expect(s.update(rawCount: 6) == 0)
        #expect(s.update(rawCount: 6) == 0)
        #expect(s.update(rawCount: 6) == 6)
    }

    @Test func aSingleFrameSpikeDoesNotMoveTheDisplayedCount() {
        let s = CountStabilizer()
        for _ in 0..<5 { _ = s.update(rawCount: 6) }
        #expect(s.update(rawCount: 9) == 6)   // median of [6,6,6,6,9] is 6
        #expect(s.update(rawCount: 6) == 6)
    }

    @Test func aTwoFrameBlipNeverReachesTheDisplay() {
        let s = CountStabilizer()
        for _ in 0..<5 { _ = s.update(rawCount: 10) }
        // Two raw frames at 12 never make 12 the median of five, so nothing to latch.
        #expect(s.update(rawCount: 12) == 10)   // [10,10,10,10,12]
        #expect(s.update(rawCount: 12) == 10)   // [10,10,10,12,12]
        #expect(s.update(rawCount: 10) == 10)
        #expect(s.update(rawCount: 10) == 10)
    }

    @Test func aSustainedChangeLatches() {
        let s = CountStabilizer()
        for _ in 0..<5 { _ = s.update(rawCount: 10) }
        // Window fills with 12s: median flips to 12 on the third 12 and the latch
        // needs three agreeing medians after that.
        var last = 10
        for _ in 0..<6 { last = s.update(rawCount: 12) }
        #expect(last == 12)
    }

    @Test func resetClearsTheWindowAndTheLatch() {
        let s = CountStabilizer()
        for _ in 0..<5 { _ = s.update(rawCount: 6) }
        #expect(s.update(rawCount: 6) == 6)
        s.reset()
        #expect(s.update(rawCount: 6) == 0)
    }
}
