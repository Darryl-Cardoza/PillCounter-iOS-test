//
//  FilterChip.swift
//  PillCounter
//
//  Created by Bhushan Patil on 22/04/26.
//

import SwiftUI

struct FilterChip<T: Hashable>: View {
    let label: String
    let count: Int?
    let value: T
    let selectedValue: T
    @EnvironmentObject private var appColors: AppColors
    let onSelect: (T) -> Void

    private var isActive: Bool {
        selectedValue == value
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                onSelect(value)
            }
        } label: {
            Text(count.map { "\(label) (\($0))" } ?? label)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : appColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isActive ? appColors.primary : appColors.secondaryBackground
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
