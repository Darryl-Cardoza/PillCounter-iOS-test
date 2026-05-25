//
//  NoCameraPermissionView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/05/26.
//

import SwiftUI

struct NoCameraPermissionView: View {
    
    var body: some View {
        VStack(spacing: 20) {
            
            Image(systemName: "camera.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.gray)
            
            Text(L10n.Camera.accessRequired)
                .font(.headline)

            Text(L10n.Camera.accessMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)

            Button(action: openSettings) {
                Text(L10n.Camera.openSettings)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(AppColors.shared.primary)
                    .cornerRadius(25)
            }
        }
        .padding(24)
        .frame(maxWidth: 300)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
    
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}


