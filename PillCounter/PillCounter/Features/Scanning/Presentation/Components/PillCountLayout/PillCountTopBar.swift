//
//  PillCountTopBar.swift
//  PillCounter
//
//  Top bar of the full-screen pill-count UI. Full-width, transparent dark bg:
//   back | NDC/drug name | glove | Strength/Bucket
//

import SwiftUI

struct PillCountTopBar: View {

    @EnvironmentObject private var appColors: AppColors

    let ndc: String
    let drugName: String
    let drugImagePath: String?
    let form: String
    let strength: String
    let bucket: String
    let instructionText: String
    let isLandscape: Bool
    let isIpad: Bool
    let cameraService: CameraService
    let showGloveIndicator: Bool
    let onBack: () -> Void

    /// iPhone in portrait — the single-row layout can't fit everything, so the
    /// Form/Strength/Bucket columns wrap onto a second row.
    private var isIphonePortrait: Bool { !isIpad && !isLandscape }

    var body: some View {
        ZStack {
            if isIphonePortrait {
                portraitContent
            } else {
                singleRowContent
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, isIpad ? 20 : 0)
        .padding(16)
        // Keep the bar clear of the notch / status bar on iPhone portrait.
        .padding(.top, isIphonePortrait ? safeAreaTop - 16 : 0)
    }

    private var safeAreaTop: CGFloat {
        let top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
        return top > 20 ? top : 0
    }
    
    /// iPad / iPhone-landscape: everything in one row.
    private var singleRowContent: some View {
        HStack(alignment: .center, spacing: isIpad ? 16 : 10) {
            backButton
            drugThumbnail
            ndcDrugColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            if showGloveIndicator {
                GloveStatusIndicator(cameraService: cameraService)
            }

            formStrengthBucketRow()
        }
        .padding(10)
    }

    /// iPhone-portrait: two rows — back + NDC/drug + glove, then Form/Strength/Bucket.
    private var portraitContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                backButton
                ndcDrugColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showGloveIndicator {
                    GloveStatusIndicator(cameraService: cameraService)
                }
            }

            formStrengthBucketRow(equalWidth: true)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
    }

    private var backButton: some View {
        Button(action: onBack) {
            PillCountingIconView(
                imageName: "back_icon",
                size: 24,
                padding: 0,
                foregroundColor: appColors.primary,
                backgroundColor: .clear,
                scaleOnIpad: true
            )
        }
    }

    private var drugThumbnail: some View {
        ThumbnailImageView(
            imagePath: nil,
            drugImagePath: drugImagePath,
            width: isIpad ? 70 : 50,
            height: isIpad ? 48 : 40,
            cornerRadius: 6,
            placeholderImageName: "dispense_placeholder",
            placeholderSize: CGSize(width: isIpad ? 20 : 16, height: isIpad ? 20 : 16),
            fillDrugImage: true
        )
    }

    private var ndcDrugColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NDC \(ndc)")
                .font(.system(size: isIpad ? 14 : 11, weight: .regular))
                .foregroundStyle(appColors.text.opacity(0.85))
            Text(drugName)
                .font(.system(size: isIpad ? 18 : 14, weight: .semibold))
                .foregroundStyle(appColors.text)
                .lineLimit(1)
        }
    }

    /// `equalWidth` (iPhone portrait) spreads the three columns evenly across the
    /// full width instead of packing them at their natural sizes.
    @ViewBuilder
    private func formStrengthBucketRow(equalWidth: Bool = false) -> some View {
        HStack(alignment: .top, spacing: equalWidth ? 0 : (isIpad ? 40 : 22)) {
            infoColumn(title: L10n.BarcodeScan.strength, value: strength)
                .frame(maxWidth: equalWidth ? .infinity : nil)
            infoColumn(title: L10n.BarcodeScan.bucket, value: bucket)
                .frame(maxWidth: equalWidth ? .infinity : nil)
        }
    }

    @ViewBuilder
    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: isIpad ? 14 : 11, weight: .regular))
                .foregroundStyle(appColors.text)
            Text(value)
                .font(.system(size: isIpad ? 18 : 15, weight: .semibold))
                .foregroundStyle(appColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
