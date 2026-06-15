//
//  ForceUpdateView.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import SwiftUI

struct MaintenaceView: View {

    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            ZStack {

                Circle()
                    .fill(appColors.primaryBackground.opacity(0.2))
                    .frame(width: 96, height: 96)

                Image("maintenance")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .overlay(appColors.secondary)
                    .mask(
                        Image("maintenance")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    )
            }

            Text(
                """
                The counter is at the pharmacist's desk for a quick check-up.
                Back soon with accurate counts!
                """
            )
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundColor(appColors.text.opacity(0.8))
            .padding(.horizontal)
            
            Spacer()
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.secondaryBackground)
    }
}


