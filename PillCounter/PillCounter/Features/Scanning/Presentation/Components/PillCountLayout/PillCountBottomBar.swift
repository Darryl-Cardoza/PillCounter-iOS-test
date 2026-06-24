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

    let onShowDetailGrid: () -> Void

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

            // Steps For
            StepProgressRow(
                activeSteps: activeSteps,
                currentStep: currentStep
            )

            // Horizontal target progress bar — always visible, trailing.
            PillCountTargetProgressBar(
                current: currentTotalCount,
                target: targetCount,
                isIpad: isIpad,
                isLandscape: isLandscape
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(16)
    }
}
