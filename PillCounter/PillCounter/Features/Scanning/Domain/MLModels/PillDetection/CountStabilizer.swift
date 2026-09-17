//
//  CountStabilizer.swift
//  PillCounter
//
//  Created by HC on 24/11/25.
//

import Foundation

/// Two-stage smoothing for the displayed pill count, per the shipped deploy
/// contract (count_window / count_hold_frames): the median over the last
/// `medianWindow` raw counts feeds a latch that only moves the displayed number
/// once `agreeingFrames` consecutive medians agree on the same new value.
///
/// The median kills single-frame outliers; the latch kills a median that is
/// oscillating between two values. Mirrors Android `CountStabilizer`.
final class CountStabilizer {

    static let medianWindow = 5
    static let agreeingFrames = 3

    private var recent: [Int] = []
    private var displayed = 0
    private var pendingValue = 0
    private var pendingStreak = 0

    /// Feeds one frame's raw count and returns the number to show.
    func update(rawCount: Int) -> Int {
        recent.append(rawCount)
        if recent.count > Self.medianWindow {
            recent.removeFirst(recent.count - Self.medianWindow)
        }
        let median = recent.sorted()[recent.count / 2]

        if median == displayed {
            pendingStreak = 0
        } else if median == pendingValue {
            pendingStreak += 1
            if pendingStreak >= Self.agreeingFrames {
                displayed = median
                pendingStreak = 0
            }
        } else {
            pendingValue = median
            pendingStreak = 1
        }
        return displayed
    }

    /// Clears the window and the latch so a new scene starts from zero.
    func reset() {
        recent.removeAll()
        displayed = 0
        pendingValue = 0
        pendingStreak = 0
    }
}
