//
//  PillCountRingView.swift
//  PillCounter
//

import SwiftUI

struct PillCountRingView: View {
    let count: Int
    var isLandscape: Bool = false
    @EnvironmentObject private var appColors: AppColors

    @State private var animationID = UUID()
    @State private var trimValue: CGFloat = 1.0
    @State private var displayedCount: Int = 0
    @State private var popScale: CGFloat = 1.0
    @State private var countTimer: Timer? = nil

    @State private var isAnimating: Bool = false
    @State private var stabilityWorkItem: DispatchWorkItem?

    private let baseSize: CGFloat = 120

    private var uiScale: CGFloat {
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad
        guard isIpad else { return 1.0 }
        return isLandscape ? 2.0 : 1.5
    }

    private var size: CGFloat { baseSize * uiScale }

    var body: some View {
        if count > 0 {
            if isLandscape {
                // Landscape: pin ring to the right edge, vertically centered
                HStack {
                    Spacer()
                    ringContent
                        .padding(.trailing, 32)
                }
            } else {
                // Portrait: pin ring to the bottom center
                VStack {
                    Spacer()
                    ringContent
                        .padding(.bottom, 48)
                }
            }
        }
    }

    private var ringContent: some View {
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
                .foregroundStyle(Color.white)
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
