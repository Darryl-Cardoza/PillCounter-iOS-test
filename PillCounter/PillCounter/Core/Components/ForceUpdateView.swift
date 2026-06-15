//
//  ForceUpdateView.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import SwiftUI

struct ForceUpdateView: View {

    @EnvironmentObject private var appColors: AppColors

    /// 🔗 Replace with your actual App Store URL
    private let appStoreURL = URL(
        string: "https://apps.apple.com/app/idXXXXXXXXXX"
    )!

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            ZStack {

                Circle()
                    .fill(appColors.primaryBackground.opacity(0.2))
                    .frame(width: 96, height: 96)

                Image("force_update")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .overlay(appColors.secondary)
                    .mask(
                        Image("force_update")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    )
            }

            Text(L10n.ForceUpdate.message)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundColor(appColors.text.opacity(0.8))
            .padding(.horizontal)

            EqualWidthHStackButtons {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.ForceUpdate.updateButton,
                    textColor: appColors.text,
                    backgroundColor: appColors.secondary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        openAppStore()
                    }
                )
            }
            
            Spacer()
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.secondaryBackground)
    }

    // MARK: - App Store Redirect
    private func openAppStore() {
        if UIApplication.shared.canOpenURL(appStoreURL) {
            UIApplication.shared.open(appStoreURL)
        }
    }
}

