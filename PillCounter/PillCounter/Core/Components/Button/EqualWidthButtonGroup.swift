//
//  EqualWidthButtonGroup.swift
//  PillCounter
//
//  Created by HC on 26/12/25.
//

import SwiftUI

struct EqualWidthHStackButtons: Layout {

    var spacing: CGFloat = 8

    // MARK: - Size Calculation
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {

        guard !subviews.isEmpty else { return .zero }

        // Measure all subviews
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        // Find max width & height
        let maxWidth = sizes.map(\.width).max() ?? 0
        let maxHeight = sizes.map(\.height).max() ?? 0

        let totalWidth =
            (maxWidth * CGFloat(subviews.count)) +
            (spacing * CGFloat(subviews.count - 1))

        return CGSize(
            width: totalWidth,
            height: maxHeight
        )
    }

    // MARK: - Placement
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {

        guard !subviews.isEmpty else { return }

        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = sizes.map(\.width).max() ?? 0
        let maxHeight = sizes.map(\.height).max() ?? 0

        var xOffset = bounds.minX

        for subview in subviews {
            subview.place(
                at: CGPoint(
                    x: xOffset,
                    y: bounds.midY - maxHeight / 2
                ),
                proposal: ProposedViewSize(
                    width: maxWidth,
                    height: maxHeight
                )
            )

            xOffset += maxWidth + spacing
        }
    }
}

