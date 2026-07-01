//
//  ConfirmationDialogue.swift
//  PillCounter
//
//  Created by HC on 13/11/25.
//

import SwiftUI

struct ConfirmationDialogue: View {

    @EnvironmentObject private var appColors: AppColors

    let title: String
    var secondTitle: String = ""
    let message: String?
    let cancelButtonText: String
    let confirmButtonText: String
    var showSecondTitle: Bool = false
    var showSingleConfirmButton: Bool = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    // Consistent button sizing across all popups — slightly larger on iPad.
    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var buttonFont: Font { .system(size: isIpad ? 17 : 14, weight: .semibold) }
    private var buttonHorizontalPadding: CGFloat { isIpad ? 16 : 8 }
    private var buttonVerticalPadding: CGFloat { isIpad ? 18 : 14 }

    var body: some View {
        VStack(spacing: 15) {

            Text(title)
                .font(showSecondTitle ? .title3 : .headline)
                .foregroundStyle(appColors.text)
                .multilineTextAlignment(.center)

            if message != nil {
                Text(message ?? "")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(appColors.text)
            }

            if showSecondTitle {
                Text(secondTitle)
                    .font(.headline)
                    .foregroundStyle(appColors.text)
                    .multilineTextAlignment(.center)
            }

            
            
            if showSingleConfirmButton {

                PillCountingButton(
                    iconName: nil,
                    title: confirmButtonText.uppercased(),
                    textColor: appColors.text,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: buttonFont,
                    cornerRadius: 30,
                    horizontalPadding: isIpad ? 48 : 40,
                    verticalPadding: buttonVerticalPadding,
                    iconSize: 0,
                    action: onConfirm
                )
                .fixedSize()
                .padding(.top, 10)

            } else {
 
                EqualWidthHStackButtons(spacing: 20) {
                    PillCountingButton(
                        iconName: nil,
                        title: cancelButtonText.uppercased(),
                        textColor: appColors.primary,
                        backgroundColor: .clear,
                        borderColor: appColors.primary,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 18,
                        iconSize: 0,
                        action: onCancel
                    )
                    PillCountingButton(
                        iconName: nil,
                        title: confirmButtonText.uppercased(),
                        textColor: .white,
                        backgroundColor: appColors.primary,
                        borderColor: .clear,
                        font: .system(size: 14, weight: .semibold),
                        cornerRadius: 30,
                        horizontalPadding: 32,
                        verticalPadding: 18,
                        iconSize: 0,
                        action: onConfirm
                    )
                }

//                EqualWidthHStackButtons(spacing: 16) {
//                    PillCountingButton(
//                        iconName: nil,
//                        title: cancelButtonText.uppercased(),
//                        textColor: appColors.primary,
//                        backgroundColor: appColors.primaryBackground,
//                        borderColor: appColors.primary,
//                        font: buttonFont,
//                        cornerRadius: 30,
//                        horizontalPadding: buttonHorizontalPadding,
//                        verticalPadding: buttonVerticalPadding,
//                        iconSize: 0,
//                        action: onCancel
//                    )
//                    PillCountingButton(
//                        iconName: nil,
//                        title: confirmButtonText.uppercased(),
//                        textColor: appColors.text,
//                        backgroundColor: appColors.primary,
//                        borderColor: .clear,
//                        font: buttonFont,
//                        cornerRadius: 30,
//                        horizontalPadding: buttonHorizontalPadding,
//                        verticalPadding: buttonVerticalPadding,
//                        iconSize: 0,
//                        action: onConfirm
//                    )
//                }
//                .frame(maxWidth: .infinity, alignment: .center)
//                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(appColors.primaryBackground)
        .cornerRadius(24)
    }
}

