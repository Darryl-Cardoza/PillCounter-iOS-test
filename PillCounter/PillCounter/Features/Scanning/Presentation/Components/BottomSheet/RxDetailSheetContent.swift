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
    var strength: String
    var form: String
    var drugImagePath: String?

    private var isPad: Bool {
        hSizeClass == .regular && vSizeClass == .regular
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isPad && isLandscape {
                iPadLandscapeLayout
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(spacing: 16) {
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 10) {
                iPhoneLabeledText(title: L10n.BarcodeScan.drugName, value: drugName)

                Divider().background(appColors.text.opacity(0.12))

                iPhoneLabeledText(title: L10n.BarcodeScan.ndcNumber, value: ndcNumber)

                Divider().background(appColors.text.opacity(0.12))

                iPhoneLabeledText(title: L10n.BarcodeScan.rxNumber, value: rxNumber)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity, isIpad: false)
                    .frame(maxWidth: .infinity)
                DrugImageBadge(isIpad: false, drugImagePath: drugImagePath, dosageForm: form)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.strength, value: strength, isIpad: false)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: false)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 64)
            .padding(.horizontal, 16)

            iPhoneButtons
                .padding(.horizontal, 40)
                .padding(.top, 4)
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func iPhoneLabeledText(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(appColors.text)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iPhoneLandscapeLayout: some View {
        VStack(spacing: 12) {
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 12)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                iPhoneLabeledText(title: L10n.BarcodeScan.drugName, value: drugName)

                Divider().background(appColors.text.opacity(0.12))

                iPhoneLabeledText(title: L10n.BarcodeScan.ndcNumber, value: ndcNumber)

                iPhoneLabeledText(title: L10n.BarcodeScan.rxNumber, value: rxNumber)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                DrugImageBadge(isIpad: false, drugImagePath: drugImagePath, dosageForm: form)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity, isIpad: false)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.strength, value: strength, isIpad: false)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: false)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 60)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            iPhoneButtons
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - iPad Portrait Layout
    private var iPadLayout: some View {
        VStack(spacing: 28) {
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.top, 28)

            HStack(alignment: .top, spacing: 40) {
                LabeledText(title: L10n.BarcodeScan.drugName, value: drugName)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 40) {
                    LabeledText(title: L10n.BarcodeScan.rxNumber,  value: rxNumber)
                    LabeledText(title: L10n.BarcodeScan.ndcNumber, value: ndcNumber)
                }
            }
            .padding(.horizontal, 28)

            HStack(spacing: 16) {
                ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity, isIpad: true)
                    .frame(maxWidth: .infinity)
                DrugImageBadge(isIpad: true, drugImagePath: drugImagePath, dosageForm: form)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.strength, value: strength, isIpad: true)
                    .frame(maxWidth: .infinity)
                ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 110)
            .padding(.horizontal, 28)

            iPhoneButtons
                .padding(.bottom, 20)
        }
    }

    // MARK: - iPad Landscape Layout

    private var iPadLandscapeLayout: some View {
        VStack(spacing: 48) {
            Text(L10n.BarcodeScan.labelScannedSuccessfully)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appColors.text)
                .padding(.bottom, 20)
            

            VStack(alignment: .leading, spacing: 24) {
                LabeledText(title: L10n.BarcodeScan.drugName, value: drugName)
                
                Divider()

                HStack(alignment: .top) {
                    LabeledText(title: L10n.BarcodeScan.rxNumber,  value: rxNumber)
                    Spacer()
                    LabeledText(title: L10n.BarcodeScan.ndcNumber, value: ndcNumber)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            let columns = [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ]
            LazyVGrid(columns: columns, spacing: 16) {
                ValueBadge(label: L10n.BarcodeScan.quantity, value: quantity, isIpad: true)
                    .frame(height: 160)
                DrugImageBadge(isIpad: true, drugImagePath: drugImagePath, dosageForm: form)
                    .frame(height: 160)
                ValueBadge(label: L10n.BarcodeScan.strength, value: strength, isIpad: true)
                    .frame(height: 160)
                ValueBadge(label: L10n.BarcodeScan.bucket, value: bucket, isIpad: true)
                    .frame(height: 160)
            }
            .padding(.horizontal, 28)

            iPhoneButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Buttons

    private var iPhoneButtons: some View {
        EqualWidthHStackButtons(spacing: 8) {
            PillCountingButton(
                iconName: nil, title: L10n.Common.cancel,
                textColor: appColors.primary, backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onCancel
            )
            PillCountingButton(
                iconName: nil, title: L10n.BarcodeScan.proceed,
                textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onProceed
            )
        }
    }
    

//    private var iPadButtons: some View {
//        EqualWidthHStackButtons(spacing: 8) {
//            PillCountingButton(
//                title: L10n.Common.cancel,
//                textColor: appColors.primary,
//                backgroundColor: .clear,
//                borderColor: appColors.primary,
//                font: .system(size: 14, weight: .semibold),
//                cornerRadius: 40,
//                horizontalPadding: 40,
//                verticalPadding: 12,
//                action: onCancel
//            )
//            PillCountingButton(
//                title: L10n.BarcodeScan.proceed,
//                textColor: .white,
//                backgroundColor: appColors.primary,
//                borderColor: .clear,
//                font: .system(size: 14, weight: .semibold),
//                cornerRadius: 40,
//                horizontalPadding: 40,
//                verticalPadding: 12,
//                action: onProceed
//            )
//        }
//        .frame(maxWidth: .infinity, alignment: .center)
//    }
}

// MARK: - Labeled Text (iPad only)

private struct LabeledText: View {
    @EnvironmentObject private var appColors: AppColors
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .regular)) //15
                .foregroundColor(appColors.text)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Drug Image Badge

/// Replaces the old Form badge — shows the drug catalog image (falls back to
/// the dosage-form icon when no image is available) filling the badge box.
/// `isSquare` distinguishes the iPad landscape grid cell (square) from the
/// iPad portrait / iPhone row cell (rectangular).
private struct DrugImageBadge: View {
    @EnvironmentObject private var appColors: AppColors

    let isIpad: Bool
    let drugImagePath: String?
    let dosageForm: String

    var body: some View {
        GeometryReader { geo in
            ThumbnailImageView(
                imagePath: nil,
                drugImagePath: drugImagePath,
                width: geo.size.width,
                height: geo.size.height,
                cornerRadius: 12,
                placeholderBackgroundColor: appColors.primaryBackground.opacity(0.5),
                placeholderSize: CGSize(width: isIpad ? 30 : 20, height: isIpad ? 30 : 20),
                showImageBackground: appColors.primaryBackground.opacity(0.5),
                dosageForm: dosageForm,
                strength: nil,
                fillDrugImage: false
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Value Badge

private struct ValueBadge: View {
    @EnvironmentObject private var appColors: AppColors
    let label: String
    let value: String
    let isIpad: Bool
    
    var body: some View {
        VStack(spacing: isIpad ? 10 : 6) {
            Text(label)
                .font(.system(size: isIpad ? 18 : 11, weight: .regular))
                .foregroundColor(appColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: isIpad ? 24 : 14, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isIpad ? 4 : 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(appColors.primaryBackground.opacity(0.5))
        )
    }
}
