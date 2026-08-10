//
//  DashboardEmptyQueueState.swift
//  PillCounter
//
//  Empty-state shown in a queue tab when there are no items (or none matching
//  the active filter). Title/subtitle are computed by the caller.
//

import SwiftUI

struct DashboardEmptyQueueState: View {
    @EnvironmentObject private var appColors: AppColors

    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Image("icon_checkmark_with_circle")
                    .renderingMode(.template)
                    .foregroundColor(appColors.secondary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(appColors.secondary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(appColors.text)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}
