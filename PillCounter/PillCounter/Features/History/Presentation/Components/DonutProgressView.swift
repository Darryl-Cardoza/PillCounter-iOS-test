//
//  DonutProgressView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
import SwiftUI

// MARK: - Donut Progress View
struct DonutProgressView: View {
    let fraction: Double
    let appColors: AppColors
    let size: CGFloat

    var body: some View {
        ZStack {
            // Background (remaining)
            Circle()
                .fill(appColors.primaryBackground)

            // Progress (filled pie)
            PieShape(fraction: fraction)
                .fill(appColors.secondary)
                .rotationEffect(.degrees(-90)) // start from top
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}


struct PieShape: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * fraction),
            clockwise: false // ← this controls direction
        )

        path.closeSubpath()

        return path
    }
}
