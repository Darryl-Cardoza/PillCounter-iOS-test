//
//  PillCountTopBar.swift
//  PillCounter
//
//  Top bar of the full-screen pill-count UI. Full-width, transparent dark bg:
//   back | NDC/drug name | glove | Form/Strength/Bucket
//

import SwiftUI

struct PillCountTopBar: View {

    @EnvironmentObject private var appColors: AppColors

    let ndc: String
    let drugName: String
    let form: String
    let strength: String
    let bucket: String
    let instructionText: String
    let isLandscape: Bool
    let isIpad: Bool
    let cameraService: CameraService
    let showGloveIndicator: Bool
    let onBack: () -> Void

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: isIpad ? 16 : 10) {
                // Back button — leading
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

                // NDC + drug name
                VStack(alignment: .leading, spacing: 8) {
                    Text("NDC \(ndc)")
                        .font(.system(size: isIpad ? 14 : 11, weight: .regular))
                        .foregroundStyle(appColors.text.opacity(0.85))
                    Text(drugName)
                        .font(.system(size: isIpad ? 18 : 14, weight: .semibold))
                        .foregroundStyle(appColors.text)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showGloveIndicator {
                    GloveStatusIndicator(cameraService: cameraService)
                }

                // Form / Strength / Bucket
                HStack(alignment: .top, spacing: isIpad ? 40 : 22) {
                    formIconColumn(title: L10n.BarcodeScan.form, dosageForm: form)
                    infoColumn(title: L10n.BarcodeScan.strength, value: strength)
                    infoColumn(title: L10n.BarcodeScan.bucket, value: bucket)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 20)
        .padding(16)
    }

    /// Form column — shows the dosage-form icon (same utility as the thumbnail)
    /// instead of the raw form text.
    @ViewBuilder
    private func formIconColumn(title: String, dosageForm: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: isIpad ? 14 : 11, weight: .regular))
                .foregroundStyle(appColors.text)
            Image(DosageFormIcon.iconName(for: dosageForm))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: isIpad ? 22 : 18, height: isIpad ? 22 : 18)
                .foregroundStyle(appColors.text)
        }
    }

    @ViewBuilder
    private func infoColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: isIpad ? 14 : 11, weight: .regular))
                .foregroundStyle(appColors.text)
            Text(value)
                .font(.system(size: isIpad ? 16 : 15, weight: .semibold))
                .foregroundStyle(appColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
