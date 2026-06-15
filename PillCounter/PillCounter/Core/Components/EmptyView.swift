//
//  EmptyView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import SwiftUI


struct EmptyStateView: View {

    let imageName: String?
    let systemImageName: String?
    let title: String?
    let subtitle: String?

    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 16) {

            Spacer()

            // SYSTEM IMAGE (preferred)
            if let systemImageName {
                Image(systemName: systemImageName)
                    .font(.system(size: 40))
                    .foregroundColor(appColors.primary)
                    .padding(20)
                    
            }
            // ASSET IMAGE (fallback)
            else if let imageName {
                Image(imageName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(appColors.secondary)
                    .padding(20)
            }

            if let title {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appColors.text)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(appColors.text.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
