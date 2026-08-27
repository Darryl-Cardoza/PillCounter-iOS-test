//
//  SandTimerIcon.swift
//  PillCounter
//

import SwiftUI

/// Hourglass with sand grains falling continuously from top to bottom —
/// infinite drip, no bulb fill accumulation.
struct SandTimerIcon: View {
    var size: CGFloat = 20
    var color: Color = .white

    @State private var fallProgress: CGFloat = 0

    private let fallDuration = 0.9
    private let pauseDuration = 0.15

    var body: some View {
        ZStack {
            Image(systemName: "hourglass")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(color)

            Circle()
                .fill(color)
                .frame(width: size * 0.18, height: size * 0.18)
                .offset(y: fallOffset)
                .opacity(fallProgress < 1 ? 1 : 0)
        }
        .onAppear { runCycle() }
    }

    /// Neck (~size*-0.05) down through the bottom bulb (~size*0.4).
    private var fallOffset: CGFloat {
        let start = -size * 0.05
        let end = size * 0.4
        return start + (end - start) * fallProgress
    }

    private func runCycle() {
        fallProgress = 0
        withAnimation(.easeIn(duration: fallDuration)) {
            fallProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fallDuration + pauseDuration) {
            runCycle()
        }
    }
}
