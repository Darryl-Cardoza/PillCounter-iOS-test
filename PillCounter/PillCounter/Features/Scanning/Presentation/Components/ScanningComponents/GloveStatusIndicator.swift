// GloveStatusIndicator.swift
// PillCounter
//
// Top-right hand-icon that reflects glove-detection state:
//   • Red hand  — gloves not yet confirmed (initial state, or after inactivity-resume reset)
//   • Green hand — gloves confirmed; inference stops for the remainder of the session
//
// When gloves are first confirmed the label "Gloves Detected" slides in, holds
// for ~2 s, then fades out — the icon stays green permanently until reset.

import SwiftUI

struct GloveStatusIndicator: View {

    @ObservedObject var cameraService: CameraService

    @State private var showLabel   = false
    @State private var labelOpacity: Double = 0

    private let green = Color(red: 0, green: 0.784, blue: 0.325)

    var body: some View {
        HStack(spacing: 8) {
            if showLabel {
                Text("Gloves Detected")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(green.opacity(0.88))
                    .clipShape(Capsule())
                    .opacity(labelOpacity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 40, height: 40)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(cameraService.glovesConfirmed ? green : .red)
                    .animation(.easeInOut(duration: 0.35), value: cameraService.glovesConfirmed)
            }
        }
        .onChange(of: cameraService.glovesConfirmed) { _, confirmed in
            if confirmed {
                animateLabel()
            } else {
                // Reset (inactivity resume) — snap back without animation
                showLabel    = false
                labelOpacity = 0
            }
        }
    }

    private func animateLabel() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            showLabel    = true
            labelOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.45)) {
                labelOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showLabel = false
            }
        }
    }
}
