//
//  PillCountingLoader.swift
//  PillCounter
//
//  Created by HC on 18/11/25.
//

import SwiftUI

struct PillCountingLoader: View {
    // MARK: - Configuration
    // You can change the color to match your app's theme (e.g., Medical Blue)
    let dotColor: Color = AppColors.shared.secondary
    let dotSize: CGFloat = 20
    let spacing: CGFloat = 10
    
    // MARK: - State
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    // Animation: Scale up and Down
                    .scaleEffect(isPulsing ? 1.0 : 0.5)
                    // Animation: Fade in and out slightly for softness
                    .opacity(isPulsing ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2), // Stagger the animation
                        value: isPulsing
                    )
            }
        }
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Preview
struct PillCountingLoader_Previews: PreviewProvider {
    static var previews: some View {
        PillCountingLoader()
    }
}
