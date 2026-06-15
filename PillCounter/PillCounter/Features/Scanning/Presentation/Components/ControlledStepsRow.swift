//
//  ControlledStepsRow.swift
//  PillCounter
//
//  Created by Bhushan Patil on 05/03/26.
//
import SwiftUI

// MARK: - STEP STATE

private enum StepState {
    case completed
    case current
    case upcoming
}

// MARK: - MAIN STEP ROW VIEW

struct ControlledStepRow: View {

    @EnvironmentObject var appColors: AppColors

    let activeSteps: [ControlledStep]
    let currentStep: ControlledStep

    private var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // Sizing tokens
    private var iconSize: CGFloat       { isIpad ? 32 : 20 }
    private var circlePadding: CGFloat  { isIpad ? 12 : 8  }
    private var circleFrame: CGFloat    { isIpad ? 56 : 40  }
    private var chevronSize: CGFloat    { isIpad ? 16 : 12  }
    private var hSpacing: CGFloat       { isIpad ? 12 : 8   }
    private var vPadding: CGFloat       { isIpad ? 20 : 15  }
    private var strokeWidth: CGFloat    { isIpad ? 2.5 : 2  }

    var body: some View {
        let items = buildSteps()

        HStack(spacing: hSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                stepIcon(for: item)
                if index < items.count - 1 {
                    connectorView(between: item, and: items[index + 1])
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, vPadding)
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
            if index < currentIndex       { return (step, .completed) }
            else if index == currentIndex { return (step, .current)   }
            else                          { return (step, .upcoming)  }
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
            .frame(width: iconSize, height: iconSize)
            .colorMultiply(appColors.text)
            .padding(circlePadding)
            .frame(width: circleFrame, height: circleFrame)
            .background(
                Circle()
                    .fill(appColors.secondaryBackground)
                    .overlay(
                        Circle()
                            .stroke(
                                state == .current ? appColors.secondary : .clear,
                                lineWidth: strokeWidth
                            )
                    )
            )
            .foregroundColor(appColors.text)
            .opacity(stateOpacity(for: state))
    }

    func stateOpacity(for state: StepState) -> Double {
        switch state {
        case .completed: return 1.0
        case .current:   return 1.0
        case .upcoming:  return 0.65
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
            .font(.system(size: chevronSize, weight: .semibold))
            .foregroundColor(.white)
            .opacity(next.1 == .upcoming ? 0.5 : 1)
    }
}
