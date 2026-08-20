//
//  SessionActionButtonPair.swift
//  PillCounter
//
//  Outlined Cancel + filled confirm button, side by side. Used by the
//  session lock states that offer a retry (see SessionStatusScreen).
//

import SwiftUI

struct SessionActionButtonPair: View {

    @EnvironmentObject private var appColors: AppColors

    var cancelTitle: String = L10n.FaceAuth.cancel
    var confirmTitle: String = L10n.FaceAuth.retry
    var buttonWidth: CGFloat = 140
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PillCountingButton(
                title: cancelTitle,
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                action: onCancel,
                width: buttonWidth
            )
            .frame(width: buttonWidth)

            PillCountingButton(
                title: confirmTitle,
                textColor: .white,
                backgroundColor: appColors.primary,
                action: onConfirm,
                width: buttonWidth
            )
            .frame(width: buttonWidth)
        }
    }
}
