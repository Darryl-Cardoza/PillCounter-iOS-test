//
//  PillCountRingView.swift
//  PillCounter
//

import SwiftUI

struct PillCountRingView: View {
    let count: Int
    @EnvironmentObject private var appColors: AppColors

    @State private var animationID = UUID()
    @State private var trimValue: CGFloat = 1.0
    @State private var displayedCount: Int = 0
    @State private var popScale: CGFloat = 1.0
    @State private var countTimer: Timer? = nil

    @State private var isAnimating: Bool = false
    @State private var stabilityWorkItem: DispatchWorkItem?

    private let size: CGFloat = 120

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Circle()
                    .trim(from: 0, to: trimValue)
                    .stroke(
                        appColors.secondary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: size, height: size)
                    .id(animationID)
                    .onAppear { updateAnimationState() }
                    .onChange(of: isAnimating) { _, _ in updateAnimationState() }

                Text("\(displayedCount)")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(appColors.text)
                    .scaleEffect(popScale)
            }
            .onChange(of: count) { _, newCount in
                scheduleAnimatingOff()
                if newCount == 0 { snapToZero() } else { animateCount(to: newCount) }
            }
            .onAppear {
                displayedCount = count
                scheduleAnimatingOff()
            }
            .padding(.bottom, 48)
        }
    }

    private func scheduleAnimatingOff() {
        stabilityWorkItem?.cancel()
        if !isAnimating { isAnimating = true }
        let work = DispatchWorkItem { isAnimating = false }
        stabilityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func snapToZero() {
        countTimer?.invalidate()
        countTimer = nil
        displayedCount = 0
        popScale = 1.0
    }

    private func animateCount(to target: Int) {
        countTimer?.invalidate()
        countTimer = nil

        let start = displayedCount
        let delta = target - start
        guard delta != 0 else { return }

        let stepCount = abs(delta)
        let increment = delta > 0 ? 1 : -1
        let totalDuration: Double = min(Double(stepCount) * 0.04, 0.3)
        let interval: Double = totalDuration / Double(stepCount)
        var current = start

        countTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            current += increment
            displayedCount = current
            popScale = 1.15
            withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) {
                popScale = 1.0
            }
            if current == target {
                t.invalidate()
                countTimer = nil
            }
        }
        RunLoop.main.add(countTimer!, forMode: .common)
    }

    private func updateAnimationState() {
        animationID = UUID()
        if isAnimating {
            trimValue = 0
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                trimValue = 1
            }
        } else {
            withAnimation(.linear(duration: 0.2)) {
                trimValue = 1
            }
        }
    }
}
