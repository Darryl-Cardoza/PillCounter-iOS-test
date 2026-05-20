//
//  CountAddButtonView.swift
//  PillCounter
//

import SwiftUI

struct CountAddButtonView: View {
    let count: Int
    let ringColor: Color
    let buttonColor: Color
    let textColor: Color
    let ringLineWidth: CGFloat
    let size: CGFloat
    let isAnimating: Bool
    let onAddTap: () -> Void
    var isDisabled: Bool = false
    let isLandscape: Bool
    let appColors: AppColors

    @State private var animationID = UUID()
    @State private var trimValue: CGFloat = 1.0
    @State private var displayedCount: Int = 0
    @State private var popScale: CGFloat = 1.0
    @State private var countTimer: Timer? = nil

    private var uiScale: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? (isLandscape ? 2.0 : 1.5) : 1.0
    }

    var body: some View {
        VStack(spacing: -20) {
            ZStack {
                Circle()
                    .trim(from: 0, to: trimValue)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: size * uiScale, height: size * uiScale)
                    .id(animationID)
                    .onAppear { updateAnimationState() }
                    .onChange(of: isAnimating) { _, _ in updateAnimationState() }

                Text("\(displayedCount)")
                    .font(.system(size: size * 0.28 * uiScale, weight: .semibold))
                    .foregroundStyle(textColor)
                    .scaleEffect(popScale)
            }
            .onChange(of: count) { _, newCount in
                if newCount == 0 { snapToZero() } else { animateCount(to: newCount) }
            }
            .onAppear { displayedCount = count }

            Button(action: onAddTap) {
                Text(isDisabled ? L10n.PillCount.addButtonWait : L10n.PillCount.addButton)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(isDisabled ? .gray : appColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(NoPressEffectStyle())
            .disabled(isDisabled)
        }
        .padding(.top, 10)
    }

    struct NoPressEffectStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
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
            withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) { popScale = 1.0 }
            if current == target { t.invalidate(); countTimer = nil }
        }
        RunLoop.main.add(countTimer!, forMode: .common)
    }

    private func updateAnimationState() {
        animationID = UUID()
        if isAnimating {
            trimValue = 0
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { trimValue = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                guard isAnimating else { return }
                FeedbackManager.shared.triggerDetectionFeedback(
                    isHapticEnabled: AppStorageManager.shared.isHapticEnabled,
                    isSoundEnabled: AppStorageManager.shared.isSoundEnabled
                )
            }
        } else {
            withAnimation(.linear(duration: 0.2)) { trimValue = 1 }
        }
    }
}
