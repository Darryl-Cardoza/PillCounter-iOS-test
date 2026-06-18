//
//  DashboardQueueTabHeaders.swift
//  PillCounter
//
//  The "Today's Queue" / "Recent Activity" segmented tab headers on
//  DashboardView. Binds to the selected-tab index.
//

import SwiftUI

struct DashboardQueueTabHeaders: View {
    @EnvironmentObject private var appColors: AppColors

    @Binding var selectedQueueTab: Int
    let isIpad: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabHeader(
                    title: L10n.Dashboard.HeaderTabs.todaysQueue,
                    index: 0
                )
                tabHeader(
                    title: L10n.Dashboard.HeaderTabs.recentActivity,
                    index: 1
                )
            }
            Divider()
        }
    }

    private func tabHeader(title: String, index: Int) -> some View {
        let isSelected = selectedQueueTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedQueueTab = index
            }
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(
                        .system(
                            size: isIpad ? 15 : 13,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .textCase(.uppercase)
                    .foregroundColor(appColors.text)
                    .tracking(0.8)

                Rectangle()
                    .fill(isSelected ? appColors.secondary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
