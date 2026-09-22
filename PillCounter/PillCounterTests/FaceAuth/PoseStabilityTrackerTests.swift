//
//  PoseStabilityTrackerTests.swift
//  PillCounterTests
//
//  Ported from Android's PoseStabilityTrackerTest.
//

import Testing
@testable import PillCounter

@Suite(.serialized)
struct PoseStabilityTrackerTests {

    @Test func doesNotHoldBeforeTheRequiredStreak() {
        let tracker = PoseStabilityTracker(requiredFrames: 3)

        #expect(tracker.record(posePassed: true) == false)
        #expect(tracker.record(posePassed: true) == false)
    }

    @Test func holdsOnTheRequiredFrame() {
        let tracker = PoseStabilityTracker(requiredFrames: 3)

        _ = tracker.record(posePassed: true)
        _ = tracker.record(posePassed: true)

        #expect(tracker.record(posePassed: true) == true)
    }

    /// The whole point: one stray frame is not a pose, and one bad frame
    /// starts the count over.
    @Test func oneFailingFrameResetsTheStreak() {
        let tracker = PoseStabilityTracker(requiredFrames: 3)
        _ = tracker.record(posePassed: true)
        _ = tracker.record(posePassed: true)

        #expect(tracker.record(posePassed: false) == false)
        #expect(tracker.streak == 0)
        #expect(tracker.record(posePassed: true) == false)
    }

    @Test func staysHeldWhileFramesKeepPassing() {
        let tracker = PoseStabilityTracker(requiredFrames: 3)
        for _ in 0..<3 { _ = tracker.record(posePassed: true) }

        #expect(tracker.record(posePassed: true) == true)
        #expect(tracker.streak == 4)
    }

    @Test func resetClearsTheStreak() {
        let tracker = PoseStabilityTracker(requiredFrames: 3)
        _ = tracker.record(posePassed: true)
        _ = tracker.record(posePassed: true)

        tracker.reset()

        #expect(tracker.streak == 0)
        #expect(tracker.record(posePassed: true) == false)
    }

    @Test func defaultMatchesAndroidsMeasuredValue() {
        #expect(PoseStabilityTracker.requiredStableFrames == 3)
    }
}
