//
//  PillCounterCheckbox.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import SwiftUI

struct PillCounterCheckbox: View {
    
    @EnvironmentObject private var appColors: AppColors
    
    // Properties
    @Binding var isChecked: Bool // binding to the variable that we want.
    var label: String? = nil
    var size: CGFloat = 15
    var tintColor: Color? = nil
    var selectedCheckmarkColor: Color? = nil
    
    // main body
    var body: some View {
        let tintColor = tintColor ?? appColors.text
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isChecked.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        // Outer box
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isChecked ? selectedCheckmarkColor ?? tintColor : .gray, lineWidth: 2)
                            .frame(width: size, height: size)
                            .background(isChecked ? selectedCheckmarkColor  : .clear)
                        
                        // Checkmark
                        if isChecked {
                            Image(systemName: "checkmark")
                                .foregroundColor(tintColor)
                                .font(.system(size: size * 0.7, weight: .bold))
                        }
                    }
                    
                    // Optional label next to checkbox
                    if let label = label {
                        Text(label)
                            .foregroundColor(appColors.text)
                            .font(.body)
                    }
                }
            }
            .buttonStyle(.plain)
        }
}
