//
//  PillCountTargetProgressBar.swift
//  PillCounter
//
//  Horizontal bar showing how much of the target has been counted.
//  Always visible; shows "current / target" and fills left-to-right.
//

import SwiftUI

struct PillCountTargetProgressBar: View {

    @EnvironmentObject private var appColors: AppColors

    let current: Int
    let target: Int
    let isIpad: Bool
    let isLandscape: Bool

    private var fraction: CGFloat {
        guard target > 0 else { return 0 }
        return min(max(CGFloat(current) / CGFloat(target), 0), 1)
    }

    private var trackHeight: CGFloat { isIpad ? 4 : 10 }
    /// Lower bound so the track never collapses to nothing when steps are crowded.
    private var minTrackWidth: CGFloat { isIpad ? 80 : 60 }

    var body: some View {
        HStack(spacing: 16) {
            // Flexible track — fills whatever horizontal space is left after the
            // count text, so it shrinks gracefully when there are many steps.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(appColors.primaryBackground)
                        .frame(width: geo.size.width, height: trackHeight)

                    Capsule()
                        .fill(appColors.secondary)
                        .frame(width: geo.size.width * fraction, height: trackHeight)
                        .animation(.easeInOut(duration: 0.25), value: fraction)
                }
                .frame(height: geo.size.height, alignment: .center)
            }
            .frame(minWidth: minTrackWidth, maxWidth: .infinity)
            .frame(height: trackHeight)

            // Count text — never compressed, so it stays readable.
            (Text("\(current)").foregroundStyle(appColors.secondary) + Text("/\(target)").foregroundStyle(appColors.text))
                .font(.system(size: isIpad ? 20 : 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }
}
