//
//  StepperRepeatButton.swift
//  PillCounter
//

import SwiftUI

/// A button that fires once on tap and fires repeatedly while held down.
struct StepperRepeatButton: View {

    let label: String
    let isEnabled: Bool
    let leadingCorners: Bool
    let background: Color
    let foreground: Color
    let action: () -> Void

    // Initial delay before repeat starts, then interval between repeats
    private let initialDelay: TimeInterval = 0.4
    private let repeatInterval: TimeInterval = 0.08

    @State private var timer: Timer? = nil

    var body: some View {
        Text(label)
            .font(.system(size: 50, weight: .semibold))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard timer == nil else { return }
                        // Fire once immediately
                        action()
                        // After initial delay, start rapid repeat
                        timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { _ in
                            timer = Timer.scheduledTimer(withTimeInterval: repeatInterval, repeats: true) { _ in
                                action()
                            }
                        }
                    }
                    .onEnded { _ in
                        stopTimer()
                    }
            )
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
