//
//  PillTrackerTests.swift
//  PillCounterTests
//
//  Mirrors the Android PillTrackerTest suite: the deploy-contract hysteresis
//  (enter 0.50 on two frames, keep 0.35, exit after three misses), the
//  one-pill-one-track rules, and camera-motion compensation.
//

import CoreGraphics
import Testing
@testable import PillCounter

struct PillTrackerTests {

    private let frameSize = CGSize(width: 640, height: 640)

    private func det(_ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat,
                     _ confidence: Float) -> DetectionResult {
        DetectionResult(rect: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                        confidence: confidence,
                        originalFrameSize: frameSize)
    }

    private func pill(_ confidence: Float) -> DetectionResult { det(0, 0, 10, 10, confidence) }

    /// `count` pills in a row, 10 px boxes 30 px apart, all shifted right by `shift`.
    private func row(_ count: Int, _ shift: CGFloat) -> [DetectionResult] {
        (0..<count).map { i in det(CGFloat(i) * 30 + shift, 0, CGFloat(i) * 30 + 10 + shift, 10, 0.90) }
    }

    // MARK: - Hysteresis

    @Test func confirmsNothingOnTheFirstFrame() {
        let tracker = PillTracker()
        #expect(tracker.update([pill(0.90)]).isEmpty)
    }

    @Test func confirmsAfterTwoConsecutiveFramesAboveEnterScore() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        let confirmed = tracker.update([pill(0.90)])
        #expect(confirmed.count == 1)
        #expect(confirmed[0].confidence == 0.90)
    }

    @Test func doesNotConfirmWhenTheSecondFrameIsBelowEnterScore() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        // 0.40 is above keep score, so the track lives, but the enter streak resets.
        #expect(tracker.update([pill(0.40)]).isEmpty)
        #expect(tracker.update([pill(0.90)]).isEmpty)
        #expect(tracker.update([pill(0.90)]).count == 1)
    }

    @Test func keepsAConfirmedTrackAliveAtKeepScore() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        #expect(tracker.update([pill(0.36)]).count == 1)
    }

    @Test func coastsAConfirmedTrackForTwoMissedFramesAndDropsItOnTheThird() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        #expect(tracker.update([]).count == 1)
        #expect(tracker.update([]).count == 1)
        #expect(tracker.update([]).isEmpty)
    }

    @Test func spawnsANewTrackWhenIoUIsBelowTheAssociationThreshold() {
        let tracker = PillTracker()
        _ = tracker.update([det(0, 0, 10, 10, 0.90)])
        _ = tracker.update([det(0, 0, 10, 10, 0.90)])
        // IoU of [0,0,10,10] vs [8,0,18,10] = 20 / 180 = 0.11, below trackIoU 0.30.
        _ = tracker.update([det(8, 0, 18, 10, 0.90)])
        // The original track has missed 2 frames so it still coasts: 2 confirmed.
        #expect(tracker.update([det(8, 0, 18, 10, 0.90)]).count == 2)
    }

    @Test func ignoresDetectionsBelowKeepScore() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.34)])
        #expect(tracker.update([pill(0.34)]).isEmpty)
    }

    // MARK: - One pill, one track

    @Test func aSecondBoxOnAnAlreadyTrackedPillDoesNotStartASecondTrack() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        // IoU of [0,0,10,10] vs [4,0,14,10] = 60 / 140 = 0.43: past NMS at 0.5, but
        // at the association threshold, so it is the same pill seen twice.
        for _ in 0..<3 {
            #expect(tracker.update([pill(0.90), det(4, 0, 14, 10, 0.80)]).count == 1)
        }
    }

    @Test func aSmallPartialBoxInsideATrackedPillDoesNotStartASecondTrack() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        // [0,0,4,10] is 40% of the pill and fully contained in it — a class-flip
        // fragment, not another pill.
        for _ in 0..<3 {
            #expect(tracker.update([pill(0.90), det(0, 0, 4, 10, 0.85)]).count == 1)
        }
    }

    @Test func twoLeftoverBoxesOnOneNewPillStartASingleTrack() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90), det(4, 0, 14, 10, 0.80)])
        #expect(tracker.update([pill(0.90), det(4, 0, 14, 10, 0.80)]).count == 1)
    }

    @Test func aTrackSupersededByALargerBoxOnTheSamePillIsRetiredInsteadOfCoasting() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        // The box doubles in size (e.g. the input switched from the full frame to
        // the tray crop): IoU 100/400 = 0.25 fails association, so a new track starts.
        _ = tracker.update([det(0, 0, 20, 20, 0.90)])
        // Next frame the new track confirms and the old one, fully inside it, is a
        // ghost: retired instead of being counted for two more frames.
        #expect(tracker.update([det(0, 0, 20, 20, 0.90)]).count == 1)
    }

    @Test func twoDistinctTouchingPillsAreBothTracked() {
        let tracker = PillTracker()
        // Adjacent boxes with a 1 px overlap: IoU 10/190 = 0.05, containment 0.1.
        let frame = [det(0, 0, 10, 10, 0.90), det(9, 0, 19, 10, 0.90)]
        _ = tracker.update(frame)
        #expect(tracker.update(frame).count == 2)
        // One goes missing for a frame: it coasts, it is not a ghost of its neighbour.
        #expect(tracker.update([det(0, 0, 10, 10, 0.90)]).count == 2)
    }

    // MARK: - Camera motion

    @Test func aCameraPanThatMovesEveryPillKeepsTheExistingTracks() {
        let tracker = PillTracker()
        _ = tracker.update(row(5, 0))
        #expect(tracker.update(row(5, 0)).count == 5)
        // Every box jumps 9 px per frame: IoU 1/19 with its own old box, far below
        // trackIoU, yet the count must stay 5 — not ~10 from coasting + spawned
        // tracks, and not 0 from every track missing.
        #expect(tracker.update(row(5, 9)).count == 5)
        let result = tracker.update(row(5, 18))
        #expect(result.count == 5)
        // The tracks moved with the pan.
        #expect(abs((result.map { $0.rect.minX }.min() ?? -1) - 18) < 0.01)
    }

    @Test func aMeasuredCameraShiftIsAppliedEvenWithASinglePill() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        // One pill is too few to vote for a shift on its own, and its box jumped
        // 9 px (IoU 1/19). Image registration says the frame moved 9 px, so this is
        // the same pill: the track follows it instead of coasting at 0.
        let result = tracker.update([det(9, 0, 19, 10, 0.90)], cameraShift: CGVector(dx: 9, dy: 0))
        #expect(result.count == 1)
        #expect(abs(result[0].rect.minX - 9) < 0.01)
    }

    @Test func aMeasuredShiftWithTheWrongSignIsCorrectedByTheDetections() {
        let tracker = PillTracker()
        _ = tracker.update(row(5, 0))
        _ = tracker.update(row(5, 0))
        // Registration reports the pan with the opposite sign; the candidate that
        // lets the most detections find a track wins, so the tracks still follow.
        let result = tracker.update(row(5, 9), cameraShift: CGVector(dx: -9, dy: 0))
        #expect(result.count == 5)
        #expect(abs((result.map { $0.rect.minX }.min() ?? -1) - 9) < 0.01)
    }

    @Test func aSinglePillMovedByHandDoesNotDragTheSteadyTracks() {
        let tracker = PillTracker()
        let steady = row(4, 0)
        func fifth(_ left: CGFloat) -> DetectionResult { det(left, 0, left + 10, 10, 0.90) }
        _ = tracker.update(steady + [fifth(120)])
        #expect(tracker.update(steady + [fifth(120)]).count == 5)
        // The fifth pill slides 12 px while the other four stay put: the median
        // camera shift is zero, so the four steady tracks stay exactly in place.
        _ = tracker.update(steady + [fifth(132)])
        let result = tracker.update(steady + [fifth(132)])
        let steadyLefts = result.map { $0.rect.minX }.filter { $0 < 100 }.sorted()
        #expect(steadyLefts == [0, 30, 60, 90])
    }

    @Test func resetDropsEveryTrack() {
        let tracker = PillTracker()
        _ = tracker.update([pill(0.90)])
        _ = tracker.update([pill(0.90)])
        tracker.reset()
        #expect(tracker.update([pill(0.90)]).isEmpty)
    }
}
