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
    @EnvironmentObject private var appColors: AppColors
    let size: CGFloat

    @State private var animatedFraction: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(appColors.primaryBackground)

            PieShape(fraction: animatedFraction)
                .fill(appColors.secondary)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedFraction = fraction
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                animatedFraction = newValue
            }
        }
    }
}


struct PieShape: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

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
            clockwise: false
        )

        path.closeSubpath()

        return path
    }
}
