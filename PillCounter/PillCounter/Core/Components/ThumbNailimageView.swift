//
//  ThumbNailimageView.swift
//  PillCounter
//
//  Created by HC on 29/12/25.
//

import SwiftUI

struct ThumbnailImageView: View {

    // MARK: - INPUTS
    let imagePath: String?
    /// Drug-master catalog image (from the NDC API). Highest priority — shown
    /// above the barcode-scan image and any placeholder when present.
    let drugImagePath: String?

    // MARK: - CUSTOMIZATION (with defaults)
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let borderColor: Color
    let borderWidth: CGFloat
    let placeholderImageName: String
    let placeholderBackgroundColor: Color?
    let placeholderSize: CGSize
    let isFromPms: Bool
    let showImageBackground: Color?

    // MARK: - DOSAGE FORM (fixed-count flow)
    /// When provided, the view shows a dosage-form icon with the strength text
    /// below it instead of the image / regular placeholder.
    let dosageForm: String?
    let strength: String?

    /// When true, the drug catalog image fills the frame edge-to-edge (cropping
    /// as needed) instead of fitting inside it with letterbox bars.
    let fillDrugImage: Bool

    // MARK: - ENVIRONMENT
    @EnvironmentObject private var appColors: AppColors

    // Decrypting + reading the image file is expensive (AES-GCM + disk I/O).
    // Loaded asynchronously off the main thread so scrolling/filtering a list
    // of these views never blocks on it; PhotoFileManager's in-memory cache
    // makes repeat loads (re-render, scroll back) effectively free.
    @State private var resolvedImage: Image?
    @State private var loadedPath: String?

    private var showsDosageForm: Bool {
        dosageForm != nil
    }

    /// Whichever path actually determines what's shown, per the same
    /// priority as the body's branching (drug image wins over the regular
    /// image). nil when this row shows the dosage-form view or a placeholder
    /// — nothing to load.
    private var pathToLoad: String? {
        if let drugPath = drugImagePath, !drugPath.isEmpty { return drugPath }
        if showsDosageForm { return nil }
        if let path = imagePath, !path.isEmpty { return path }
        return nil
    }

    // MARK: - INIT
    init(
        imagePath: String?,
        drugImagePath: String? = nil,
        width: CGFloat = 70,
        height: CGFloat = 50,
        cornerRadius: CGFloat = 4,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        placeholderImageName: String = "placeholder_history",
        placeholderBackgroundColor: Color? = nil,
        placeholderSize: CGSize = CGSize(width: 25, height: 25),
        isFromPms: Bool = false,
        showImageBackground: Color? = nil,
        dosageForm: String? = nil,
        strength: String? = nil,
        fillDrugImage: Bool = false
    ) {
        self.imagePath = imagePath
        self.drugImagePath = drugImagePath
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor ?? Color.primary.opacity(0.1)
        self.borderWidth = borderWidth
        self.placeholderImageName = placeholderImageName
        self.placeholderBackgroundColor = placeholderBackgroundColor
        self.placeholderSize = placeholderSize
        self.isFromPms = isFromPms
        self.showImageBackground = showImageBackground
        self.dosageForm = dosageForm
        self.strength = strength
        self.fillDrugImage = fillDrugImage
    }

    // MARK: - BODY
    var body: some View {
        ZStack {
            if let drugPath = drugImagePath, !drugPath.isEmpty, let drugImage = resolvedImage {
                // Catalog image is a rectangular photo (pill inside) — scaledToFit so
                // it's never cropped/distorted, on a background fill so the box still
                // reads as a filled square/rect like the other thumbnail states.
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(showImageBackground ?? appColors.secondaryBackground)
                    drugImage
                        .resizable()
                        .aspectRatio(contentMode: fillDrugImage ? .fill : .fit)
                        .frame(width: fillDrugImage ? width : nil, height: fillDrugImage ? height : nil)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
            } else if showsDosageForm {
                dosageFormView
            } else if let path = imagePath, !path.isEmpty, let loadedImage = resolvedImage {
                loadedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: borderWidth)
                    )

            } else if pathToLoad != nil {
                // Path exists but decrypt/load hasn't resolved yet — neutral
                // placeholder box instead of a blank flash while `.task` loads it.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(showImageBackground ?? appColors.secondaryBackground)
                    .frame(width: width, height: height)
            } else {
                if isFromPms {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(appColors.text.opacity(0.8), lineWidth: borderWidth)
                        .frame(width: width, height: height)
                        .overlay(
                            Text(L10n.Common.pms)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(appColors.secondary)
                        )
                }else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(showImageBackground ?? appColors.secondaryBackground)
                        .stroke(showImageBackground ?? appColors.text.opacity(0.8), lineWidth: borderWidth)
                        .frame(width: width, height: height)
                        .overlay(
                            Image(placeholderImageName)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: placeholderSize.width,
                                    height: placeholderSize.height
                                )
                                .foregroundStyle(appColors.secondary)
                        )
                }
            }
        }
        .task(id: pathToLoad) {
            await loadImageIfNeeded()
        }
    }

    // MARK: - Async image loading

    private func loadImageIfNeeded() async {
        guard let path = pathToLoad else {
            resolvedImage = nil
            loadedPath = nil
            return
        }
        guard path != loadedPath else { return }

        let uiImage = await Task.detached(priority: .userInitiated) {
            PhotoFileManager.shared.loadUIImage(from: path)
        }.value

        guard !Task.isCancelled else { return }
        loadedPath = path
        resolvedImage = uiImage.map { Image(uiImage: $0) }
    }

    // MARK: - Dosage form layout (fixed-count flow)
    @ViewBuilder
    private var dosageFormView: some View {
        VStack(spacing: 6) {
            Image(DosageFormIcon.iconName(for: dosageForm))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: placeholderSize.width, height: placeholderSize.height)
                .foregroundStyle(appColors.secondary)

            if let strength, !strength.isEmpty {
                Text(strength)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(appColors.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: width, height: height)
        .background(showImageBackground ?? appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
