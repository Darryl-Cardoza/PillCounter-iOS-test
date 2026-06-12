//
//  DashboardQuickActionCards.swift
//  PillCounter
//
//  Quick-action cards used by NewDashboardView in its three layouts
//  (portrait / iPad, phone-landscape, iPad-landscape). Pure presentation —
//  takes an icon, copy and an action; reads theming from AppColors.
//

import SwiftUI

/// Portrait + iPad quick-action card.
struct DashboardQuickActionCard: View {
    @EnvironmentObject private var appColors: AppColors

    let iconName: String
    let title: String
    let subtitle: String
    let isIpad: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(appColors.primary.opacity(0.25), lineWidth: 6)
                        .blur(radius: 3)
                    Circle()
                        .stroke(appColors.primary, lineWidth: 2.5)
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(appColors.secondary)
                        .padding(isIpad ? 18 : 14)
                }
                .frame(width: isIpad ? 90 : 60, height: isIpad ? 90 : 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isIpad ? 24 : 20, weight: .semibold))
                        .foregroundColor(appColors.secondary)
                    Text(subtitle)
                        .font(.system(size: isIpad ? 16 : 14))
                        .fontWeight(.semibold)
                        .foregroundColor(appColors.text)
                }

                Spacer()
            }
            .padding(.horizontal, isIpad ? 24 : 16)
            .padding(.vertical, isIpad ? 48 : 22)
            .frame(maxWidth: .infinity)
            .background(appColors.secondaryBackground)
            .cornerRadius(16)
            .shadow(color: appColors.text.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        .buttonStyle(PlainButtonStyle())
    }
}

/// Compact card for the phone-landscape left column.
struct PhoneQuickActionCard: View {
    @EnvironmentObject private var appColors: AppColors

    let iconName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(appColors.primary.opacity(0.25), lineWidth: 5)
                        .blur(radius: 3)
                    Circle()
                        .stroke(appColors.primary, lineWidth: 2)
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(appColors.secondary)
                        .padding(10)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(appColors.secondary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(appColors.text)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.secondaryBackground)
            .cornerRadius(14)
            .shadow(color: appColors.text.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Large card for the iPad-landscape left column.
struct LandscapeQuickActionCard: View {
    @EnvironmentObject private var appColors: AppColors

    let iconName: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let circleSize = min(geo.size.width, geo.size.height) * 0.45
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .stroke(
                                appColors.primary.opacity(0.25),
                                lineWidth: 6
                            )
                            .blur(radius: 3)
                        Circle()
                            .stroke(appColors.primary, lineWidth: 2.5)
                        Image(iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaleEffect(1.5)
                            .foregroundColor(appColors.secondary)
                            .padding(circleSize * 0.3)
                    }
                    .frame(width: circleSize, height: circleSize)

                    VStack(spacing: 3) {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(appColors.secondary)
                        Text(subtitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(appColors.text)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.secondaryBackground)
            .cornerRadius(16)
            .shadow(color: appColors.text.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        .buttonStyle(PlainButtonStyle())
    }
}
