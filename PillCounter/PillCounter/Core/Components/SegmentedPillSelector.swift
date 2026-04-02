//
//  SegmentedPillSelector.swift
//  PillCounter
//
//  Created by Bhushan Patil on 31/03/26.
//

import SwiftUI

struct SegmentedPillSelector<Option: Hashable>: View {

    let options: [Option]
    @Binding var selected: Option
    let title: (Option) -> String

    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                
                let isSelected = selected == option
                let isFirst = index == 0
                let isLast = index == options.count - 1
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : appColors.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected
                            ? appColors.secondary
                            : appColors.inputBackground
                        )
                        .clipShape(
                            RoundedCorner(
                                radius: 30,
                                corners: corners(isFirst: isFirst, isLast: isLast)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(appColors.primary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
    
    private func corners(isFirst: Bool, isLast: Bool) -> UIRectCorner {
        if isFirst { return [.topLeft, .bottomLeft] }
        if isLast { return [.topRight, .bottomRight] }
        return []
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = 0
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
