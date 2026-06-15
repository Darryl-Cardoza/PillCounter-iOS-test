//
//  SecurityViolationView.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import SwiftUI

struct SecurityViolationView: View {
    
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text(L10n.Security.alertTitle)
                .font(.title2)
                .bold()

            Text(L10n.Security.alertMessage)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)

            PillCountingButton(
                iconName: nil,
                title: L10n.Security.exitButton,
                textColor: appColors.text,
                backgroundColor: appColors.secondary,
                borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30,
                horizontalPadding: 32,
                verticalPadding: 14,
                iconSize: 0,
                action: {
                    exit(0)
                }
            )
            .padding(.top, 20)
        }
        .padding()
    }
}

#Preview {
    SecurityViolationView()
}
