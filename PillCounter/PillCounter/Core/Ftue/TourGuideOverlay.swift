//
//  TourGuideOverlay.swift
//  PillCounter
//
//  Mounted once at a screen's root via .overlayPreferenceValue. Renders the
//  dimmed scrim with a cut-out at the current step's real target, an accent
//  ring, and the Skip/Back/Next tooltip. Blocks touches everywhere except
//  inside the target (for .actionTap) or the tooltip itself.
//
//  Renders nothing at all when the current step's target can't currently be
//  resolved (rather than blocking with no cut-out) — needed for steps whose
//  target only exists in one UI mode of a screen that can toggle between
//  modes without navigating away (e.g. a bottom-sheet panel that gets
//  dismissed while a full-screen camera mode is active): the tour goes fully
//  passive until the user returns to the state where the target exists again,
//  instead of blocking a screen the target isn't even on.
//

import SwiftUI

/// A full-rect path with a hole cut out at each target rect (even-odd fill).
/// Used both for the visual scrim cut-out and, via .contentShape(eoFill:),
/// for punching a real hit-test hole so an .actionTap step's target is
/// reachable underneath without any gesture-stealing tricks.
private struct ScrimHoleShape: Shape {
    let holes: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for hole in holes {
            path.addRect(hole)
        }
        return path
    }
}

/// Reserved anchor ids for screen regions that aren't tour targets themselves
/// but that a pinnedEdge step needs to avoid colliding with (e.g. a bottom
/// sheet that's currently covering the bottom of the screen).
enum FtueOccupancyIds {
    static let stockCountPanel = "ftue.occupancy.stockCountPanel"
}

struct TourGuideOverlay: View {
    @ObservedObject var state: TourGuideState
    let anchors: [String: Anchor<CGRect>]

    /// Extra room around the real target so the ring/cut-out doesn't hug it pixel-tight.
    private let targetPadding: CGFloat = 8

    var body: some View {
        // This branch only exists in the hierarchy while `state.isActive`, so
        // its removal from the tree — by completion, Skip, or the last gated
        // step advancing off the end with no Next/Done button — always fires
        // the .onDisappear below, regardless of which UI path triggered it.
        // (Attaching .onDisappear outside this `if` instead would only fire
        // when the host screen itself disappears, e.g. on navigation, not
        // when the tour ends while the screen stays up — the equivalent of
        // Compose's DisposableEffect(state) { onDispose { ... } } depends on
        // this content's own mount lifecycle matching `isActive`, not the
        // screen's.)
        if state.isActive, let step = state.currentStep {
            GeometryReader { geo in
                let resolvedTarget = anchors[step.id].map { geo[$0] }

                // Nothing renders — no scrim, no block, no tooltip — until the
                // target is resolvable again. See the file header.
                if let resolvedTarget {
                    let target = resolvedTarget.insetBy(dx: -targetPadding, dy: -targetPadding)
                    let pinnedEdge = resolvedPinnedEdge(for: step, geo: geo)

                    ZStack(alignment: .topLeading) {
                        scrim(target: target, mode: step.mode)

                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.shared.primary, lineWidth: 3)
                            .frame(width: target.width, height: target.height)
                            .position(x: target.midX, y: target.midY)
                            .allowsHitTesting(false)

                        tooltip(step: step, target: target, pinnedEdge: pinnedEdge, screenSize: geo.size)
                    }
                    .onChange(of: resolvedTarget) { newValue in
                        state.targetBounds[step.id] = newValue
                    }
                }
            }
            .transition(.opacity)
            .onDisappear {
                if !state.isActive {
                    TourGuidePrefs.shared.markSeen(tourId: state.tourId)
                }
            }
        }
    }

    /// Flips a step's base pinnedEdge away from whichever edge the reserved
    /// occupancy anchor (e.g. a bottom sheet) currently covers, so the
    /// tooltip never sits behind real overlapping UI. No occupancy anchor
    /// registered (or step has no pinnedEdge) → the base edge is used as-is.
    private func resolvedPinnedEdge(for step: TourStep, geo: GeometryProxy) -> PinnedEdge? {
        guard let base = step.pinnedEdge else { return nil }
        guard let occupancyRect = anchors[FtueOccupancyIds.stockCountPanel].map({ geo[$0] }) else {
            return base
        }
        let significant = occupancyRect.height > geo.size.height * 0.15
        switch base {
        case .bottom:
            let occupiesBottom = significant && occupancyRect.maxY >= geo.size.height - 1
            return occupiesBottom ? .top : .bottom
        case .top:
            let occupiesTop = significant && occupancyRect.minY <= 1
            return occupiesTop ? .bottom : .top
        }
    }

    @ViewBuilder
    private func scrim(target: CGRect, mode: TourStepMode) -> some View {
        switch mode {
        case .actionWait:
            // Blocks nothing — the spotlight is purely visual; advancement is
            // gated by business logic (advanceIfCurrent), not by touch.
            ScrimHoleShape(holes: [target])
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
        case .info:
            Color.black.opacity(0.6)
                .contentShape(Rectangle())
                .onTapGesture {} // absorb all touches; only the tooltip (drawn above) is reachable
        case .actionTap:
            ScrimHoleShape(holes: [target])
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                .contentShape(ScrimHoleShape(holes: [target]), eoFill: true)
                .onTapGesture {} // absorbs touches everywhere except the punched-out target hole
        }
    }

    @ViewBuilder
    private func tooltip(step: TourStep, target: CGRect, pinnedEdge: PinnedEdge?, screenSize: CGSize) -> some View {
        // "placeBelow" means the tooltip is top-aligned on screen (sitting
        // below a target that's in the upper half, or pinned to the top
        // edge outright); the false case is bottom-aligned.
        let placeBelow = pinnedEdge.map { $0 == .top } ?? (target.midY < screenSize.height / 2)
        let fixedInset: CGFloat = 24
        let topPadding = pinnedEdge != nil ? fixedInset : target.maxY + 16
        let bottomPadding = pinnedEdge != nil ? fixedInset : screenSize.height - target.minY + 16

        VStack {
            if !placeBelow { Spacer(minLength: 0) }

            TourTooltipCard(
                step: step,
                stepIndex: state.currentIndex,
                stepCount: state.steps.count,
                onSkip: { state.dismiss() },
                onBack: { state.back() },
                onNext: { state.next() }
            )
            .padding(.horizontal, 20)
            .padding(.top, placeBelow ? topPadding : 0)
            .padding(.bottom, placeBelow ? 0 : bottomPadding)

            if placeBelow { Spacer(minLength: 0) }
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: placeBelow ? .top : .bottom)
    }
}

private struct TourTooltipCard: View {
    @EnvironmentObject private var appColors: AppColors

    let step: TourStep
    let stepIndex: Int
    let stepCount: Int
    let onSkip: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: Double(stepIndex + 1), total: Double(max(stepCount, 1)))
                .tint(appColors.primary)
                .accessibilityLabel(L10n.Ftue.stepProgress(stepIndex + 1, stepCount))

            Text(step.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appColors.text)

            Text(step.description)
                .font(.system(size: 14))
                .foregroundColor(appColors.text.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(action: onSkip) {
                    Text(L10n.Ftue.skip)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(appColors.text.opacity(0.7))
                }
                .accessibilityLabel(L10n.Ftue.skip)

                Spacer()

                if stepIndex > 0 {
                    Button(action: onBack) {
                        Text(L10n.Ftue.back)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(appColors.primary)
                    }
                    .accessibilityLabel(L10n.Ftue.back)
                }

                if step.mode == .info {
                    Button(action: onNext) {
                        Text(L10n.Ftue.next)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(appColors.primary)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel(L10n.Ftue.next)
                }
            }
        }
        .padding(16)
        .background(appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}
