//
//  VerifyStockBottleSheetContent.swift
//  PillCounter
//
//  Hazardous-drug confirmation sheet shown when a scanned stock bottle's NDC
//  matches the expected drug AND the drug is hazardous. Mirrors the layout of
//  RxDetailsSheetContent so it shares the same look, width and height.
//

import SwiftUI

struct VerifyStockBottleSheetContent: View {

    @EnvironmentObject private var appColors: AppColors
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass
    @Environment(\.isLandscape) private var isLandscape

    var onCancel: () -> Void = {}
    var onProceed: () -> Void = {}

    var drugName: String
    var ndcNumber: String
    var bucket: String

    private var isPad: Bool {
        hSizeClass == .regular && vSizeClass == .regular
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isPad && isLandscape {
                iPadLandscapeLayout
                    .background(appColors.secondaryBackground)
            } else if isPad {
                iPadLayout
                    .background(appColors.secondaryBackground)
            } else if isLandscape {
                iPhoneLandscapeLayout
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedCorners(radius: 20, corners: [.topLeft, .bottomLeft]))
                    .background(
                        RoundedCorners(radius: 20, corners: [.topLeft, .bottomLeft])
                            .fill(appColors.secondaryBackground)
                    )
            } else {
                iPhoneLayout
                    .background(appColors.secondaryBackground)
            }
        }
    }

    // MARK: - iPhone Layout (portrait + landscape)

    private var iPhoneLayout: some View {
        iPhoneContent(
            badgeSize: 80,
            titleFontSize: 14,
            valueFontSize: 18,
            rowVerticalPadding: 10,
            buttonTopPadding: 10,
            buttonBottomPadding: 16,
            buttonHorizontalPadding: 80
        )
    }

    private var iPhoneLandscapeLayout: some View {
        iPhoneContent(
            badgeSize: 80,
            titleFontSize: 12,
            valueFontSize: 14,
            rowVerticalPadding: 8,
            buttonTopPadding: 6,
            buttonBottomPadding: 16,
            buttonHorizontalPadding: 80
        )
    }

    private func iPhoneContent(
        badgeSize: CGFloat,
        titleFontSize: CGFloat,
        valueFontSize: CGFloat,
        rowVerticalPadding: CGFloat,
        buttonTopPadding: CGFloat,
        buttonBottomPadding: CGFloat,
        buttonHorizontalPadding: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Text(L10n.BarcodeScan.qrScannedSuccessfully)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 12)
                .padding(.bottom, 6)

            iPhoneDetailRow(leading: VerifyFormBadge(isIpad: false),
                            title: L10n.BarcodeScan.drugName,
                            value: drugName,
                            badgeSize: badgeSize,
                            titleFontSize: titleFontSize,
                            valueFontSize: valueFontSize,
                            verticalPadding: rowVerticalPadding)

            Divider()
                .background(appColors.text.opacity(0.12))
                .padding(.horizontal, 16)

            iPhoneDetailRow(leading: VerifyValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: false),
                            title: L10n.BarcodeScan.ndcNumber,
                            value: ndcNumber,
                            badgeSize: badgeSize,
                            titleFontSize: titleFontSize,
                            valueFontSize: valueFontSize,
                            verticalPadding: rowVerticalPadding)

            iPhoneButtons
                .padding(.horizontal, buttonHorizontalPadding)
                .padding(.top, buttonTopPadding)
                .padding(.bottom, buttonBottomPadding)
        }
    }

    // MARK: - iPad Portrait Layout
    private var iPadLayout: some View {
        VStack(spacing: 32) {
            Text(L10n.BarcodeScan.qrScannedSuccessfully)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 32)

            HStack(alignment: .center, spacing: 32) {
                VStack(alignment: .leading, spacing: 20) {
                    VerifyLabeledText(title: L10n.BarcodeScan.drugName, value: drugName)

                    Divider().background(appColors.text.opacity(0.15))

                    VerifyLabeledText(title: L10n.BarcodeScan.ndcNumber, value: ndcNumber)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 14) {
                    VerifyFormBadge(isIpad: true).frame(width: 110, height: 140)
                    VerifyValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: true).frame(width: 110, height: 140)
                }
            }
            .padding(.horizontal, 32)

            iPadButtons
                .padding(.bottom, 32)
        }
    }

    // MARK: - iPad Landscape Layout

    private var iPadLandscapeLayout: some View {
        VStack(spacing: 16) {
            Text(L10n.BarcodeScan.qrScannedSuccessfully)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 50)

            Spacer(minLength: 0)

            VStack(spacing: 20) {
                iPadLandscapeDetailRow(leading: VerifyFormBadge(isIpad: true),
                                       title: L10n.BarcodeScan.drugName,
                                       value: drugName)

                Divider()
                    .background(appColors.text.opacity(0.12))
                    .padding(.horizontal, 20)

                iPadLandscapeDetailRow(leading: VerifyValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: true),
                                       title: L10n.BarcodeScan.ndcNumber,
                                       value: ndcNumber)
            }

            Spacer(minLength: 0)

            iPadButtons
                .padding(.bottom, 28)
        }
    }

    // MARK: - Reusable Row Builders

    @ViewBuilder
    private func iPhoneDetailRow<Leading: View>(
        leading: Leading,
        title: String,
        value: String,
        badgeSize: CGFloat,
        titleFontSize: CGFloat,
        valueFontSize: CGFloat,
        verticalPadding: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            leading.frame(width: badgeSize, height: badgeSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .regular))
                    .foregroundColor(appColors.text)
                Text(value)
                    .font(.system(size: valueFontSize, weight: .regular))
                    .foregroundColor(appColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPadding)
    }

    @ViewBuilder
    private func iPadLandscapeDetailRow<Leading: View>(leading: Leading, title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            leading.frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(appColors.text)
                Text(value)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(appColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Buttons

    private var iPhoneButtons: some View {
        HStack(spacing: 12) {
            PillCountingButton(
                title: L10n.Common.cancel,
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 13, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 18,
                verticalPadding: 11,
                action: onCancel
            )
            PillCountingButton(
                title: L10n.BarcodeScan.proceed,
                textColor: .white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 13, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 18,
                verticalPadding: 11,
                action: onProceed
            )
        }
    }

    private var iPadButtons: some View {
        HStack(spacing: 16) {
            PillCountingButton(
                title: L10n.Common.cancel,
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 40,
                verticalPadding: 12,
                action: onCancel
            )
            .fixedSize()
            PillCountingButton(
                title: L10n.BarcodeScan.proceed,
                textColor: .white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 40,
                verticalPadding: 12,
                action: onProceed
            )
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Labeled Text (iPad only)

private struct VerifyLabeledText: View {
    @EnvironmentObject private var appColors: AppColors
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(appColors.text)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Form Badge

private struct VerifyFormBadge: View {
    @EnvironmentObject private var appColors: AppColors

    let isIpad: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("Form")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(appColors.text)

            Image("dispense_dashboard_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(appColors.secondary)
                .frame(width: isIpad ? 30 : 24, height: isIpad ? 30 : 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColors.primaryBackground.opacity(0.5))
        )
    }
}

// MARK: - Value Badge

private struct VerifyValueBadge: View {
    @EnvironmentObject private var appColors: AppColors
    let label: String
    let value: String
    let isIpad: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(appColors.text)
            Text(value)
                .font(.system(size: isIpad ? 24 : 16, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColors.primaryBackground.opacity(0.5))
        )
    }
}
