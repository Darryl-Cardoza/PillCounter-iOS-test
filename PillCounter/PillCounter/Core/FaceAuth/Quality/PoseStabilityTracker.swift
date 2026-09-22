//
//  PoseStabilityTracker.swift
//  PillCounter
//
//  Counts how many sampled frames in a row the pose held. One bad frame starts
//  the count over.
//
//  Landmark jitter alone can make a straight face read as turned for an
//  instant, so accepting the first frame that looks right accepts strays.
//
//  Port of Android's PoseStabilityTracker.
//

final class PoseStabilityTracker {

    /// Consecutive passing frames before a pose counts as held. At the 150ms
    /// frame interval this is roughly 450ms. Android measured one in six
    /// failing frames drifting within 0.07 of the acceptance line, so one
    /// frame is not enough; it started at 5 and dropped to 3 because a
    /// marginal turn kept resetting the count and the step took many seconds.
    static let requiredStableFrames = 3

    private let requiredFrames: Int

    /// How many frames in a row have passed.
    private(set) var streak = 0

    init(requiredFrames: Int = PoseStabilityTracker.requiredStableFrames) {
        self.requiredFrames = requiredFrames
    }

    /// Records one frame's pose verdict. Returns true once the pose has passed
    /// `requiredFrames` frames in a row.
    @discardableResult
    func record(posePassed: Bool) -> Bool {
        streak = posePassed ? streak + 1 : 0
        return streak >= requiredFrames
    }

    func reset() {
        streak = 0
    }
}
