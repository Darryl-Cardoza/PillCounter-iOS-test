//
//  PillCountBottomBar.swift
//  PillCounter
//
//  Bottom bar of the full-screen pill-count UI:
//   "View all counts" | steps row | horizontal target progress bar.
//  Full-width, transparent dark background.
//

import SwiftUI

struct PillCountBottomBar: View {

    @EnvironmentObject private var appColors: AppColors

    let activeSteps: [ControlledStep]
    let currentStep: ControlledStep
    let currentTotalCount: Int
    let targetCount: Int
    let isIpad: Bool
    let isLandscape: Bool
    /// When false (iPhone portrait), the steps row is rendered outside this bar.
    var showSteps: Bool = true
    /// Forwarded to the steps row — host re-shows the tooltip on a current-step tap.
    var onTapCurrentStep: () -> Void = {}
    /// Open-ended step (parent pour) — there is no target, so we show the live
    /// count plus an explicit "Done" button instead of a meaningless `current/0`
    /// progress bar.
    var isOpenEndedCountStep: Bool = false
    /// Whether the "Done" button on the open-ended step is tappable (≥1 pill).
    var isDoneEnabled: Bool = true

    let onShowDetailGrid: () -> Void
    /// Finish the open-ended parent pour. Only used when `isOpenEndedCountStep`.
    var onDone: () -> Void = {}

    /// iPhone in portrait — needs extra vertical padding so the bar isn't too thin.
    private var isIphonePortrait: Bool { !isIpad && !isLandscape }

    var body: some View {
        HStack(alignment: .center, spacing: isIpad ? 24 : 12) {
            // "View all counts" — opens the full detail grid overlay.
            Button(action: onShowDetailGrid) {
                HStack(spacing: 8) {
                    Text(L10n.PillScan.viewAllCounts)
                        .font(.system(size: isIpad ? 16 : 13, weight: .semibold))
                        .foregroundStyle(appColors.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: isIpad ? 14 : 11, weight: .semibold))
                        .foregroundStyle(appColors.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Steps For — hidden here on iPhone portrait (shown above the bar instead).
            if showSteps {
                StepProgressRow(
                    activeSteps: activeSteps,
                    currentStep: currentStep,
                    onTapCurrentStep: onTapCurrentStep
                )
            }

            // Trailing slot: for the open-ended parent pour (no target) show the
            // live count and an explicit "Done" button; otherwise the horizontal
            // target progress bar.
            if isOpenEndedCountStep {
                HStack(spacing: isIpad ? 16 : 10) {
                    Text("\(currentTotalCount)")
                        .font(.system(size: isIpad ? 22 : 16, weight: .bold))
                        .foregroundStyle(appColors.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Button(action: onDone) {
                        Text(L10n.PillCount.done)
                            .font(.system(size: isIpad ? 16 : 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, isIpad ? 20 : 14)
                            .padding(.vertical, isIpad ? 10 : 7)
                            .background(
                                Capsule().fill(isDoneEnabled ? appColors.secondary : Color.gray)
                            )
                    }
                    .disabled(!isDoneEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                PillCountTargetProgressBar(
                    current: currentTotalCount,
                    target: targetCount,
                    isIpad: isIpad,
                    isLandscape: isLandscape
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, isIphonePortrait ? 14 : 0)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }
}
