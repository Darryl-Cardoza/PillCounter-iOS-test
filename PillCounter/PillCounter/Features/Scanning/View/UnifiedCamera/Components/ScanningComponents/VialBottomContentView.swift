//
//  VialBottomContentView.swift
//  PillCounter
//

import SwiftUI

struct VialBottomContentView: View {

    let appColors: AppColors
    let isCaptured: Bool
    var onRedo: () -> Void
    var onCapture: () -> Void
    var onDone: () -> Void

    @Environment(\.isLandscape) private var isLandscape

    var body: some View {
        let layout = isLandscape
            ? AnyLayout(VStackLayout(spacing: 70))
            : AnyLayout(HStackLayout(spacing: 90))

        layout {
            VStack(spacing: 10) {
                Image("redo_icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isCaptured ? appColors.primary : appColors.primaryBackground)
                Text(L10n.PillCount.redo)
                    .font(.caption)
                    .foregroundColor(appColors.text)
            }
            .onTapGesture { guard isCaptured else { return }; onRedo() }

            ZStack {
                Circle().fill(appColors.primary).frame(width: 70, height: 70)
                Image(systemName: "camera").font(.system(size: 28, weight: .medium)).foregroundColor(.white)
            }
            .onTapGesture { onCapture() }

            VStack(spacing: 10) {
                Image("done_icon").foregroundColor(isCaptured ? appColors.primary : .gray)
                Text(L10n.PillCount.done)
                    .font(.caption)
                    .foregroundColor(isCaptured ? appColors.text : .gray)
            }
            .onTapGesture { guard isCaptured else { return }; onDone() }
        }
        .padding(.vertical, 25)
        .padding(.horizontal)
    }
}
