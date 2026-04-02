//
//  BarcodeScanComponent.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/04/26.
//
import SwiftUI

struct CameraPermissionView: View {
    
    var body: some View {
        VStack(spacing: 20) {
            
            Image(systemName: "camera.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.gray)
            
            Text("Camera Access Required")
                .font(.headline)
            
            Text("Please enable camera access in Settings to scan barcodes.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            Button(action: openSettings) {
                Text("Open Settings")
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



struct BarcodeScanBox: View {
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        AppColors.shared.primary,
                        AppColors.shared.secondary,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 3
            )
            .frame(width: 180, height: 180)
            .scaleEffect(animate ? 1.05 : 0.95)
            .opacity(animate ? 1 : 0.6)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    animate = true
                }
            }
            .allowsHitTesting(false)
    }
}
