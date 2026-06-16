//
//  DashboardStatCardView.swift
//  PillCounter
//
//  Tappable stat card on DashboardView. Highlights when its filter is active
//  and toggles the filter via the supplied callback.
//

import SwiftUI

struct DashboardStatCardView: View {
    @EnvironmentObject private var appColors: AppColors

    let card: DashboardStatCard
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                onTap()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    Image(card.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(card.iconColor)
                }

                Text("\(card.count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(appColors.primary)
                    .padding(.top, 4)

                Text(card.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appColors.secondaryBackground)
            .cornerRadius(14)
            .shadow(
                color: isActive
                    ? appColors.primary.opacity(0.6)
                    : appColors.text.opacity(0.05),
                radius: isActive ? 8 : 4,
                x: 0,
                y: isActive ? 0 : 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isActive
                            ? appColors.primary.opacity(0.8) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
    }
}
