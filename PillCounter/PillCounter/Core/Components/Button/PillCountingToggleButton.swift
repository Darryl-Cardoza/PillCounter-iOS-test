//
//  PillCountingToggleButton.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct PillCountingToggleButton: View {
    @Binding var isOn: Bool
    var onColor: Color = .green
    var offColor: Color = .gray

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOn.toggle()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                // Background capsule
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: isOn
                                ? [onColor.opacity(0.8), onColor]
                                : [offColor.opacity(0.5), offColor.opacity(0.8)]
                            ),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 40)

                // Circle handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 0)
            }
        }
        .accessibilityLabel(Text(isOn ? L10n.Common.switchOn : L10n.Common.switchOff))
    }
}


#Preview {
    StatefulPreviewWrapper(false) { isOn in
        VStack(spacing: 20) {
            PillCountingToggleButton(isOn: isOn, onColor: .blue, offColor: .gray)
            PillCountingToggleButton(isOn: isOn, onColor: .pink, offColor: .gray)
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}

/// Helper to preview @Binding components
struct StatefulPreviewWrapper<Content: View>: View {
    @State private var value: Bool
    var content: (Binding<Bool>) -> Content

    init(_ initialValue: Bool, @ViewBuilder content: @escaping (Binding<Bool>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
