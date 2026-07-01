//
//  TootlTipBubble.swift
//  PillCounter
//
//  Created by Bhushan Patil on 25/06/26.
//

import SwiftUI

// MARK: - TOOLTIP BUBBLE

/// Speech-bubble tooltip matching the supplied design: a rounded body whose
/// corner radius is 40% of its height, with a downward-pointing tail centred
/// on the bottom edge so it appears to spring from the step icon below it.
struct TooltipBubble: View {

    let text: String
    let isIpad: Bool
    let background: Color

    private var fontSize: CGFloat { isIpad ? 15 : 13 }
    private var tailSize: CGSize { isIpad ? CGSize(width: 18, height: 10) : CGSize(width: 14, height: 8) }
    private var cornerRadius: CGFloat { isIpad ? 18 : 14 }

    var body: some View {
        // The text + its padding defines the rounded BODY only; the tail is
        // overlaid below so it doesn't affect the text's vertical centring.
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, isIpad ? 16 : 12)
            .padding(.vertical, isIpad ? 14 : 11)
            .frame(minHeight: cornerRadius * 2)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            )
            // Tail attached to the body's bottom edge, pointing down.
            .overlay(alignment: .bottom) {
                DownTriangle()
                    .fill(background)
                    .frame(width: tailSize.width, height: tailSize.height)
                    // Overlap the body by ~1pt so there is no seam between them.
                    .offset(y: tailSize.height - 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
            // Reserve room for the overlaid tail (overlay doesn't grow the frame).
            .padding(.bottom, tailSize.height)
    }
}

/// Simple downward-pointing triangle (apex at bottom centre).
private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
