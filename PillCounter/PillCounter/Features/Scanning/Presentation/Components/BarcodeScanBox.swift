//
//  BarcodeScanBox.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/05/26.
//

import SwiftUI

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
