//
//  ControlledDrug.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/02/26.
//
import SwiftUI

extension CameraContentView {

    struct StepProgressView: View {
        
        let totalSteps: Int
        let currentStep: Int   // 1-based index
        
        var primaryColor: Color
        
        var body: some View {
            HStack(spacing: 0) {
                ForEach(1...totalSteps, id: \.self) { step in
                    
                    // Circle
                    ZStack {
                        Circle()
                            .fill(circleBackground(for: step))
                            .overlay(
                                Circle()
                                    .stroke(primaryColor, lineWidth: 1.5)
                            )
                            .frame(width: 26, height: 26)   // ⬅️ smaller
                        
                        Text("\(step)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(textColor(for: step))
                    }
                    
                    // Line (except last)
                    if step != totalSteps {
                        Rectangle()
                            .fill(lineColor(for: step))
                            .frame(height: 2) // ⬅️ thinner line
                            .frame(maxWidth: 28) // ⬅️ shorter line width
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: currentStep)
        }
        
        // MARK: - Helpers
        
        private func circleBackground(for step: Int) -> Color {
            step <= currentStep ? primaryColor : .white
        }
        
        private func textColor(for step: Int) -> Color {
            step <= currentStep ? .white : primaryColor
        }
        
        private func lineColor(for step: Int) -> Color {
            step < currentStep ? primaryColor : primaryColor.opacity(0.3)
        }
    }}
