//
//  RxDetailsSheetContent.swift
//  PillCounter
//
//  Created by Bhushan Patil on 18/05/26.
//

import SwiftUI

struct RxDetailsSheetContent: View {

    @EnvironmentObject private var appColors: AppColors
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass
    @Environment(\.isLandscape) private var isLandscape

    var onCancel: () -> Void = {}
    var onProceed: () -> Void = {}

    var drugName: String
    var quantity: String
    var ndcNumber: String
    var bucket: String
    var rxNumber: String

    private var isPad: Bool {
        hSizeClass == .regular && vSizeClass == .regular
    }

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
                    .background(appColors.secondaryBackground)
                    .clipShape(RoundedCorners(radius: 20, corners: [.topLeft, .bottomLeft]))
            } else {
                iPhoneLayout
                    .background(appColors.secondaryBackground)
            }
        }
    }

    // MARK: - iPhone Layout (unchanged)
    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 20)
                .padding(.bottom, 16)

            DetailRow(
                leading: FormBadge(),
                title: L10n.BarcodeScan.drugName,
                value: drugName
            )

            Divider().background(appColors.text.opacity(0.12))
                .padding(.horizontal, 20)

            DetailRow(
                leading: ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity),
                title: L10n.BarcodeScan.ndcNumber,
                value: ndcNumber
            )

            Divider().background(appColors.text.opacity(0.12))
                .padding(.horizontal, 20)

            DetailRow(
                leading: ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket),
                title: L10n.BarcodeScan.rxNumber,
                value: rxNumber
            )

            buttons
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - iPhone Landscape Layout
    private var iPhoneLandscapeLayout: some View {
        VStack(spacing: 0) {
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                iPhoneLandscapeDetailRow(
                    leading: FormBadge(),
                    title: L10n.BarcodeScan.drugName,
                    value: drugName
                )

                Divider().background(appColors.text.opacity(0.12))
                    .padding(.horizontal, 20)

                iPhoneLandscapeDetailRow(
                    leading: ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity),
                    title: L10n.BarcodeScan.ndcNumber,
                    value: ndcNumber
                )

                Divider().background(appColors.text.opacity(0.12))
                    .padding(.horizontal, 20)

                iPhoneLandscapeDetailRow(
                    leading: ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket),
                    title: L10n.BarcodeScan.rxNumber,
                    value: rxNumber
                )
            }

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                PillCountingButton(
                    title: L10n.Common.cancel,
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 40,
                    horizontalPadding: 28,
                    verticalPadding: 14,
                    action: onCancel
                )
                PillCountingButton(
                    title: L10n.BarcodeScan.proceed,
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 40,
                    horizontalPadding: 28,
                    verticalPadding: 14,
                    action: onProceed
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct iPhoneLandscapeDetailRow<Leading: View>: View {
        @EnvironmentObject private var appColors: AppColors

        let leading: Leading
        let title: String
        let value: String

        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                leading
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(appColors.text)
                    Text(value)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(appColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - iPad Layout (matches target mockup)
    private var iPadLayout: some View {
        VStack(spacing: 32) {

            // Title
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 32)

            // Main content row — text on left, badges on right
            HStack(alignment: .center, spacing: 32) {

                // Left: drug name on top, Rx + NDC below with divider between
                VStack(alignment: .leading, spacing: 20) {
                    LabeledText(title: L10n.BarcodeScan.drugName, value: drugName)

                    Divider().background(appColors.text.opacity(0.15))

                    HStack(alignment: .top, spacing: 40) {
                        LabeledText(title: L10n.BarcodeScan.rxNumber,  value: rxNumber)
                        LabeledText(title: L10n.BarcodeScan.ndcNumber, value: ndcNumber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: three square-ish badges in a row
                HStack(spacing: 14) {
                    FormBadge()
                        .frame(width: 110, height: 140)
                    ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity)
                        .frame(width: 110, height: 140)
                    ValueBadge(label: L10n.BarcodeScan.bucket,   value: bucket)
                        .frame(width: 110, height: 140)
                }
            }
            .padding(.horizontal, 32)

            // Buttons — centered, not stretched
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
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - iPad Landscape Layout
    private var iPadLandscapeLayout: some View {
        VStack(spacing: 16) {

            // Title — stays pinned at top
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Spacer(minLength: 0)

            // Three rows grouped together — vertically centered
            VStack(spacing: 20) {
                iPadLandscapeDetailRow(
                    leading: FormBadge(),
                    title: L10n.BarcodeScan.drugName,
                    value: drugName
                )

                Divider().background(appColors.text.opacity(0.12))
                    .padding(.horizontal, 20)

                iPadLandscapeDetailRow(
                    leading: ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity),
                    title: L10n.BarcodeScan.ndcNumber,
                    value: ndcNumber
                )

                Divider().background(appColors.text.opacity(0.12))
                    .padding(.horizontal, 20)

                iPadLandscapeDetailRow(
                    leading: ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket),
                    title: L10n.BarcodeScan.rxNumber,
                    value: rxNumber
                )
            }

            Spacer(minLength: 0)

            // Buttons — pinned at bottom
            HStack(spacing: 16) {
                PillCountingButton(
                    title: L10n.Common.cancel,
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 40,
                    horizontalPadding: 32,
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
                    horizontalPadding: 32,
                    verticalPadding: 12,
                    action: onProceed
                )
                .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
        }
    }
    
    
    // MARK: - iPad Landscape Detail Row (bigger badge, more breathing room)
     
    private struct iPadLandscapeDetailRow<Leading: View>: View {
        @EnvironmentObject private var appColors: AppColors
     
        let leading: Leading
        let title: String
        let value: String
     
        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                leading
                    .frame(width: 120, height: 120)
     
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
    }
     
     

    // MARK: - Buttons (iPhone)
    private var buttons: some View {
        HStack(spacing: 16) {
            PillCountingButton(
                title: L10n.Common.cancel,
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 22,
                verticalPadding: 14,
                action: onCancel
            )

            PillCountingButton(
                title: L10n.BarcodeScan.proceed,
                textColor: .white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 22,
                verticalPadding: 14,
                action: onProceed
            )
        }
        .padding(.horizontal, 36)
    }
}

// MARK: - Labeled Text (iPad)

private struct LabeledText: View {
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

// MARK: - Detail Row (iPhone)

private struct DetailRow<Leading: View>: View {
    @EnvironmentObject private var appColors: AppColors

    let leading: Leading
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leading
                .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(appColors.text)
                Text(value)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(appColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Form Badge
private struct FormBadge: View {
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 10) {
            Text("Form")
                .font(.system(size: 12))
                .foregroundColor(appColors.text)

            Image("dispense_dashboard_icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(appColors.secondary)
                .frame(width: 32, height: 32)
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
private struct ValueBadge: View {
    @EnvironmentObject private var appColors: AppColors

    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(appColors.text)
            Text(value)
                .font(.system(size: 24, weight: .semibold))
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






// MARK: - Configurable Landscape Detail Row
private struct LandscapeDetailRow<Leading: View>: View {
    @EnvironmentObject private var appColors: AppColors

    let leading: Leading
    let title: String
    let value: String
    let badgeSize: CGFloat          // ← parameter
    let titleFont: Font             // ← parameter
    let valueFont: Font             // ← parameter
    let horizontalPadding: CGFloat  // ← parameter

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leading
                .frame(width: badgeSize, height: badgeSize)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(titleFont)
                    .foregroundColor(appColors.text)
                Text(value)
                    .font(valueFont)
                    .foregroundColor(appColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
    }
}
