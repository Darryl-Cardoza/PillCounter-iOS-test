//
//  SharedInfoViews.swift
//  PillCounter
//
//  KeyValueInfoCard, MenuOption, PillCountInstructionOverlay, CircleBadge
//

import SwiftUI

// MARK: - Key-value info card

struct KeyValueInfoCard: View {

    let title: String
    let value: String
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(appColors.text.opacity(0.8))
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appColors.text)
                .lineLimit(nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appColors.inputBackground.opacity(appColors.isDarkMode ? 1 : 0.9))
        .cornerRadius(12)
    }
}

// MARK: - Menu option picker
//
//struct MenuOption<Option: Hashable>: View {
//
//    let options: [Option]
//    @Binding var selectedOption: Option
//    @Binding var isPresented: Bool
//    let label: (Option) -> String
//    let onSelect: (Option) -> Void
//    @EnvironmentObject private var appColors: AppColors
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 15) {
//            Text("SELECT OPTIONS")
//                .foregroundStyle(appColors.text)
//                .font(.system(size: 18, weight: .bold))
//
//            ForEach(options, id: \.self) { option in
//                PillCountingRadioButton(
//                    option: option,
//                    selectedOption: $selectedOption,
//                    label: label(option),
//                    selectedColor: appColors.primary,
//                    unselectedColor: .gray.opacity(0.5),
//                    size: 20,
//                    lineWidth: 2,
//                    textColor: appColors.text
//                )
//                .padding(.vertical)
//            }
//            .padding(.horizontal)
//
//            HStack {
//                PillCountingButton(
//                    iconName: nil, title: L10n.Common.cancel,
//                    textColor: appColors.text, backgroundColor: appColors.primaryBackground,
//                    borderColor: appColors.primary,
//                    font: .system(size: 12, weight: .semibold),
//                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
//                    action: { isPresented = false }
//                )
//                PillCountingButton(
//                    iconName: nil, title: L10n.Common.ok,
//                    textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
//                    font: .system(size: 12, weight: .regular),
//                    cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
//                    action: { isPresented = false; onSelect(selectedOption) }
//                )
//            }
//        }
//        .frame(width: 250)
//        .padding(.vertical)
//    }
//}

// MARK: - Step instruction overlay

struct PillCountInstructionOverlay: View {
    let text: String
    var backgroundOpacity: Double = 0.5
    var cornerRadius: CGFloat = 24

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundColor(AppColors.shared.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.shared.primaryBackground.opacity(backgroundOpacity))
            .cornerRadius(cornerRadius)
    }
}

// MARK: - Circle badge

struct CircleBadge: View {
    let size: CGFloat
    let strokeWidth: CGFloat
    let outerColor: Color
    let innerColor: Color
    let text: String
    let textColor: Color
    let font: Font
    let isAnimated: Bool

    @State private var trimValue: CGFloat = 1
    @State private var animationID = UUID()

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: trimValue)
                .stroke(outerColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .id(animationID)
                .onAppear { handleAnimationChange() }
                .onChange(of: isAnimated) { _, _ in handleAnimationChange() }

            Circle()
                .fill(innerColor)
                .frame(width: size - strokeWidth * 3, height: size - strokeWidth * 3)

            Text(text)
                .font(font)
                .foregroundColor(textColor)
                .contentTransition(.numericText())
        }
        .onChange(of: text) { oldValue, newValue in
            if oldValue != newValue { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
    }

    private func handleAnimationChange() {
        animationID = UUID()
        if isAnimated {
            trimValue = 0
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { trimValue = 1 }
        } else {
            trimValue = 1
        }
    }
}
