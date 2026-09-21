//
//  TourStep.swift
//  PillCounter
//

import Foundation

/// How a step advances. `.info` blocks all touches until Next/Skip/Back;
/// `.actionTap` blocks everything except the real target, advancing on the
/// user's real tap; `.actionWait` blocks nothing and advances only when
/// business logic calls `TourGuideState.advanceIfCurrent(_:)`.
enum TourStepMode: Equatable {
    case info
    case actionTap
    case actionWait
}

/// A fixed edge to pin the tooltip to instead of positioning it relative to
/// the target — for targets that fill most of the screen (e.g. a camera
/// preview), where "above/below the target" isn't meaningful.
enum PinnedEdge: Equatable {
    case top
    case bottom
}

struct TourStep: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let mode: TourStepMode
    var pinnedEdge: PinnedEdge? = nil
}
