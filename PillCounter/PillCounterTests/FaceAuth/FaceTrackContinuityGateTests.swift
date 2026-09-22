//
//  FaceTrackContinuityGateTests.swift
//  PillCounterTests
//
//  Ported from Android's FaceTrackContinuityGateTest. The gate is pure
//  geometry over a clock, so this is the one part of the continuity feature
//  that can be tested exhaustively without a camera.
//

import CoreGraphics
import Foundation
import Testing
@testable import PillCounter

@Suite(.serialized)
struct FaceTrackContinuityGateTests {

    private static let box = CGRect(x: 100, y: 100, width: 200, height: 200)
    /// Same size, shifted a few pixels — what a stationary face looks like
    /// between two frames 150ms apart. IoU well above 0.35.
    private static let nudgedBox = CGRect(x: 108, y: 104, width: 200, height: 200)
    /// Far enough away to share no area at all — a different face.
    private static let jumpedBox = CGRect(x: 600, y: 600, width: 200, height: 200)

    @Test func nothingBreaksBeforeArming() {
        let gate = FaceTrackContinuityGate()

        gate.observe(Self.box)
        gate.observe(Self.jumpedBox)
        for _ in 0...(FaceTrackContinuityGate.maxTrackGapFrames + 2) {
            gate.observe(nil)
        }

        #expect(gate.isBroken == false)
    }

    @Test func steadyFaceNeverBreaks() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()

        for _ in 0..<50 {
            gate.observe(Self.nudgedBox)
            gate.observe(Self.box)
        }

        #expect(gate.isBroken == false)
    }

    @Test func boxJumpBreaksOnTheFirstFrame() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()

        gate.observe(Self.jumpedBox)

        #expect(gate.isBroken == true)
    }

    @Test func absenceWithinGraceIsForgiven() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()

        for _ in 0..<FaceTrackContinuityGate.maxTrackGapFrames {
            gate.observe(nil)
        }

        #expect(gate.isBroken == false)
    }

    @Test func absenceBeyondGraceBreaks() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()

        for _ in 0...FaceTrackContinuityGate.maxTrackGapFrames {
            gate.observe(nil)
        }

        #expect(gate.isBroken == true)
    }

    @Test func aSeenFaceResetsTheGapCounter() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()

        for _ in 0..<FaceTrackContinuityGate.maxTrackGapFrames {
            gate.observe(nil)
        }
        gate.observe(Self.box)
        for _ in 0..<FaceTrackContinuityGate.maxTrackGapFrames {
            gate.observe(nil)
        }

        #expect(gate.isBroken == false)
    }

    /// The duplicate prompt stops the frame loop for seconds. Without this the
    /// first frame back would be compared against a stale box and read as a
    /// person swap.
    @Test func dropLastReferenceLetsAnyNextBoxThrough() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()

        gate.dropLastReference()
        gate.observe(Self.jumpedBox)

        #expect(gate.isBroken == false)
    }

    @Test func isBrokenLatchesUntilReset() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()
        gate.observe(Self.jumpedBox)

        gate.observe(Self.jumpedBox)
        #expect(gate.isBroken == true)

        gate.reset()
        #expect(gate.isBroken == false)
    }

    /// reset() disarms as well as clearing, so a post-reset break can't latch
    /// before the scan re-establishes whose face it is.
    @Test func resetDisarms() {
        let gate = FaceTrackContinuityGate()
        gate.observe(Self.box)
        gate.arm()
        gate.reset()

        gate.observe(Self.box)
        gate.observe(Self.jumpedBox)

        #expect(gate.isBroken == false)
    }
}
