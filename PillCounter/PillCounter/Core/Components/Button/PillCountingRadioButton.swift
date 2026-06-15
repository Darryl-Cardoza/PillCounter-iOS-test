//
//  PillCountingRadioButton.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct PillCountingRadioButton<Option: Hashable>: View {
    let option: Option
    @Binding var selectedOption: Option
    let label: String
    let selectedColor: Color
    let unselectedColor: Color
    let size: CGFloat
    let lineWidth: CGFloat
    let textColor: Color

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedOption = option
            }
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(selectedOption == option ? selectedColor : unselectedColor, lineWidth: lineWidth)
                        .frame(width: size, height: size)

                    if selectedOption == option {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: size / 2, height: size / 2)
                    }
                }

                Text(label)
                    .foregroundColor(textColor)
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .buttonStyle(.plain)
    }
}
