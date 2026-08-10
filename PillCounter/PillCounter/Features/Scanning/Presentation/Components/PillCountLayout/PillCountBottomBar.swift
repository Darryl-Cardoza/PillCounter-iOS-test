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
    /// Forwarded to the steps row — host re-shows the tooltip on any step tap.
    var onTapStep: (ControlledStep) -> Void = { _ in }
    /// Open-ended step (parent pour) — there is no target, so we show the live
    /// count plus an explicit "Done" button instead of a meaningless `current/0`
    /// progress bar.
    var isOpenEndedCountStep: Bool = false
    /// REGULAR count type — no fixed target; hides progress bar, shows live count
    /// and Proceed button (same visual treatment as the open-ended pour step).
    var isRegularCountType: Bool = false
    /// Whether the "Done" button on the open-ended step is tappable (≥1 pill).
    var isDoneEnabled: Bool = true

    let onShowDetailGrid: () -> Void
    /// Finish the open-ended parent pour. Only used when `isOpenEndedCountStep`.
    var onDone: () -> Void = {}

    /// iPhone in portrait — needs extra vertical padding so the bar isn't too thin.
    private var isPortrait: Bool { !isLandscape }

    /// Bare live-count number — shown for the open-ended container-initiate pour
    /// and for REGULAR count type (both have no meaningful fixed target).
    private var showsLiveCount: Bool {
        isRegularCountType || (isOpenEndedCountStep && currentStep != .containerPending)
    }

    /// Target progress bar — hidden for REGULAR count type and the open-ended
    /// container-initiate pour (neither has a meaningful target).
    private var showsProgressBar: Bool {
        !isRegularCountType && !(isOpenEndedCountStep && currentStep != .containerPending)
    }

    /// Explicit Proceed button — shown for open-ended steps and REGULAR count type.
    private var showsProceedButton: Bool { isOpenEndedCountStep || isRegularCountType }

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
            // In portrait the button hugs its content so the trailing progress bar
            // can claim ALL the remaining width; in landscape it shares the bar
            // equally (steps row sits centred between the two flexible sides).
            .frame(maxWidth: isPortrait ? nil : .infinity, alignment: .leading)
            .fixedSize(horizontal: isPortrait, vertical: false)

            // Steps For — hidden here on iPhone portrait (shown above the bar instead).
            // Wrapped in an equal-share flexible frame so the row stays centred in
            // the bar regardless of how wide the leading / trailing slots become —
            // otherwise the side slots split the leftover space and shove it off-centre.
            if showSteps {
                StepProgressRow(
                    activeSteps: activeSteps,
                    currentStep: currentStep,
                    onTapStep: onTapStep
                )
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // The live pill-count number is shown only for the open-ended parent
            // pour (container-initiate). `.containerPending` has a real target, so
            // it uses the progress bar instead and the bare count is suppressed.
            if showsLiveCount && !isLandscape {
                Text("\(currentTotalCount)")
                    .font(.system(size: isIpad ? 22 : 16, weight: .bold))
                    .foregroundStyle(appColors.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(alignment: .center)
            }

            // Trailing slot:
            //  • container-initiate (open-ended, no target) → live count + Proceed
            //  • container-pending → target progress bar + Proceed (no bare count)
            //  • everything else → target progress bar only
            HStack(spacing: isIpad ? 16 : 10) {
                if showsProgressBar {
                    PillCountTargetProgressBar(
                        current: currentTotalCount,
                        target: targetCount,
                        isIpad: isIpad,
                        isLandscape: isLandscape
                    )
                    // In portrait the steps row is lifted out of the bar, so this
                    // slot is the only flexible content on the right — let the bar
                    // stretch into all the remaining width instead of hugging right.
                    .frame(maxWidth: isPortrait ? .infinity : nil)
                }
                
                if showsProceedButton {
                    
                    if showsLiveCount && isLandscape {
                        Text("\(currentTotalCount)")
                            .font(.system(size: isIpad ? 22 : 16, weight: .bold))
                            .foregroundStyle(appColors.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(alignment: .center)
                    }
                    
                    Button(action: onDone) {
                        Text(L10n.BarcodeScan.proceed)
                            .font(.system(size: isIpad ? 16 : 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, isIpad ? 20 : 14)
                            .padding(.vertical, isIpad ? 10 : 7)
                            .background(
                                Capsule().fill(isDoneEnabled ? appColors.secondary : Color.gray)
                            )
                    }
                    .disabled(!isDoneEnabled)
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, isPortrait ? 14 : 0)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }
}
