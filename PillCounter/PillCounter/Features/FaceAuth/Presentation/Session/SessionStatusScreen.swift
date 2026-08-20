//
//  SessionStatusScreen.swift
//  PillCounter
//
//  Shared full-screen layout for every SessionLockOverlay state (locked,
//  unlocked, failed). All three are the same design — ringed icon + title
//  + subtitle centred vertically, optional action buttons pinned to the
//  bottom — so they differ only by icon, copy, and the action slot.
//

import SwiftUI

struct SessionStatusScreen<Actions: View>: View {

    @EnvironmentObject private var appColors: AppColors

    let iconName: String
    let title: String
    let subtitle: String
    /// Longer copy (the enrollment intro pitch) needs more room than the
    /// terse lock/unlock lines this was built for.
    var subtitleMaxWidth: CGFloat = 260
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                badge

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(appColors.secondary)
                    .fixedSize()
                    .padding(.top, 8)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(appColors.text.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: subtitleMaxWidth)
                    .padding(.top, 8)
            }

            Spacer()

            actions()
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Asset icon inside a thin accent ring, lifted off the background by a
    /// soft drop shadow under the circle (spec mock).
    private var badge: some View {
        Image(iconName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 60, height: 60)
            .foregroundStyle(appColors.secondary)
            .frame(width: 140, height: 140)
            .background(
                Circle()
                    .fill(appColors.primaryBackground)
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
            )
            .overlay(
                Circle().stroke(appColors.primary.opacity(0.8), lineWidth: 2)
            )
    }
}

extension SessionStatusScreen where Actions == EmptyView {
    init(iconName: String, title: String, subtitle: String, subtitleMaxWidth: CGFloat = 260) {
        self.init(
            iconName: iconName,
            title: title,
            subtitle: subtitle,
            subtitleMaxWidth: subtitleMaxWidth
        ) { EmptyView() }
    }
}
