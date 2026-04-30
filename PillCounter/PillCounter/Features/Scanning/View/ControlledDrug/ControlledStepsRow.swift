//
//  ControlledStepsRow.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/03/26.
//
import SwiftUI



// MARK: - STEP STATE

private enum StepState {
    case completed   // white bg, dark icon
    case current     // white bg, gray/muted icon
    case upcoming    // white bg, low opacity (not done)
}

// MARK: - MAIN STEP ROW VIEW

struct ControlledStepRow: View {

    @EnvironmentObject var appColors: AppColors

    let activeSteps: [ControlledStep]
    let currentStep: ControlledStep

    var body: some View {

        let items = buildSteps()

        HStack(spacing: 8) {

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in

                stepIcon(for: item)

                if index < items.count - 1 {
                    connectorView(between: item, and: items[index + 1])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 5)
        .padding(.vertical, 15)
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }
}

// MARK: - BUILD STEP STATES

private extension ControlledStepRow {

    func buildSteps() -> [(ControlledStep, StepState)] {

        guard let currentIndex = activeSteps.firstIndex(of: currentStep) else {
            return activeSteps.map { ($0, .upcoming) }
        }

        return activeSteps.enumerated().map { index, step in
            if index < currentIndex {
                return (step, .completed)
            } else if index == currentIndex {
                return (step, .current)
            } else {
                return (step, .upcoming)
            }
        }
    }
}

// MARK: - STEP ICON

private extension ControlledStepRow {

    @ViewBuilder
    func stepIcon(for item: (ControlledStep, StepState)) -> some View {

        let step  = item.0
        let state = item.1

        Image(assetName(for: step))
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .colorMultiply(appColors.text)
            .padding(8)
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(appColors.primaryBackground)
                    .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
                    .overlay(
                        Circle()
                            .stroke(
                                state == .current ? appColors.secondary : .clear,
                                lineWidth: 2
                            )
                    )
            )
            .opacity(stateOpacity(for: state))
    }
    
    func iconColor(for state: StepState) -> Color {
        switch state {
        case .completed:
            return appColors.text
        case .current:
            return appColors.text.opacity(0.7)

        case .upcoming:
            return appColors.text.opacity(0.3)
        }
    }
    
    func stateOpacity(for state: StepState) -> Double {
        switch state {
            
        case .completed:
            return 1
            
        case .current:
            return 1
            
        case .upcoming:
            return 0.50
        }
    }
}

// MARK: - CONNECTOR

private extension ControlledStepRow {

    @ViewBuilder
    func connectorView(
        between current: (ControlledStep, StepState),
        and next: (ControlledStep, StepState)
    ) -> some View {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .opacity(current.1 == .upcoming ? 0.5 : 1)
                .foregroundColor(.white)
                .opacity(next.1 == .upcoming ? 0.5 : 1)

    }
}
