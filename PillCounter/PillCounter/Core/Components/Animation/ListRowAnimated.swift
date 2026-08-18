//
//  ListRowAnimated.swift
//  PillCounter
//
//  Created by Bhushan Patil on 07/05/26.
//

// ListRowAnimated.swift

import SwiftUI

// MARK: — Modifier
struct ListRowAnimatedModifier: ViewModifier {
    let id: Int64
    let index: Int
    let isEditing: Bool
    let isSelected: Bool
    let isDeleting: Bool
    let highlightColor: Color

    @State private var appeared: Bool = false

    func body(content: Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(isDeleting ? 0.12 : 0))
                .animation(.easeIn(duration: 0.15), value: isDeleting)

            content
                .offset(x: appeared ? 0 : 60)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(isSelected ? 0.98 : 1)
                .animation(
                    .spring(response: 0.28, dampingFraction: 0.72),
                    value: isSelected
                )
        }
        .selectableEffect(isSelected: isSelected, highlightColor: highlightColor)
        .collapsible(isVisible: !isDeleting)
        .animation(
            .spring(response: 0.38, dampingFraction: 0.82),
            value: isDeleting
        )
        .onAppear {
            guard !appeared else { return }
            withAnimation(
                .spring(response: 0.42, dampingFraction: 0.78)
                .delay(Double(index) * 0.07)
            ) {
                appeared = true
            }
        }
    }
}

// MARK: — Extension
extension View {
    func listRowAnimated(
        id: Int64,
        index: Int,
        isEditing: Bool,
        isSelected: Bool,
        isDeleting: Bool,
        highlightColor: Color
    ) -> some View {
        self.modifier(
            ListRowAnimatedModifier(
                id: id,
                index: index,
                isEditing: isEditing,
                isSelected: isSelected,
                isDeleting: isDeleting,
                highlightColor: highlightColor
            )
        )
    }
}
