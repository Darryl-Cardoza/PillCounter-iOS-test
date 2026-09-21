//
//  TourTargetModifier.swift
//  PillCounter
//
//  SwiftUI equivalent of Modifier.tourTarget(state, id): tags a real
//  composable so TourGuideOverlay can read its bounds. anchorPreference
//  captures an Anchor<CGRect>, which the overlay later resolves into its own
//  local coordinate space via GeometryProxy.subscript(_:) — the equivalent of
//  boundsInRoot()/positionInRoot() plus the local conversion, done in one step
//  instead of two.
//

import SwiftUI

struct TourTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func tourTarget(_ id: String) -> some View {
        anchorPreference(key: TourTargetPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }

    /// Tags a real control as an .actionTap target. While this step is the
    /// active one, a simultaneousGesture fires advanceIfCurrent on touch-DOWN
    /// (.onChanged of a zero-distance DragGesture) rather than on release —
    /// the real control's own onClick/navigation still fires normally on
    /// release, unaffected, so this never requires (or risks) a second tap and
    /// never races a navigation that tears the view down before release.
    func ftueActionTarget(id: String, state: TourGuideState) -> some View {
        modifier(FtueActionTargetModifier(id: id, state: state))
    }

    /// Convenience for a control that's an .actionTap target for one FTUE
    /// step id (dispenseEntryId) and a plain .info target for every other id
    /// (e.g. stockCountId) — avoids call sites needing to know which kind of
    /// step their id maps to.
    @ViewBuilder
    func ftueQuickAction(id: String, state: TourGuideState) -> some View {
        if id == DashboardFtueSteps.dispenseEntryId {
            ftueActionTarget(id: id, state: state)
        } else {
            tourTarget(id)
        }
    }
}

private struct FtueActionTargetModifier: ViewModifier {
    let id: String
    @ObservedObject var state: TourGuideState

    func body(content: Content) -> some View {
        // advanceIfCurrent no-ops unless this really is the active step, so
        // the gesture can stay attached unconditionally — no branching on a
        // Gesture-typed value, which Optional can't uniformly represent.
        content
            .tourTarget(id)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onChanged { _ in
                    state.advanceIfCurrent(id)
                }
            )
    }
}

/// For shared components (e.g. NotePopupView) used by both tour-tagged and
/// untagged call sites — applies ftueActionTarget only when an id is given,
/// so every other call site is unaffected by default.
struct OptionalFtueTarget: ViewModifier {
    let id: String?
    let state: TourGuideState

    func body(content: Content) -> some View {
        if let id {
            content.ftueActionTarget(id: id, state: state)
        } else {
            content
        }
    }
}
