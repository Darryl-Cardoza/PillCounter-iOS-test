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

    // MARK: - ENVIRONMENT
    @EnvironmentObject private var appColors: AppColors

    // MARK: - INIT
    init(
        imagePath: String?,
        width: CGFloat = 70,
        height: CGFloat = 50,
        cornerRadius: CGFloat = 4,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        placeholderImageName: String = "placeholder_history",
        placeholderBackgroundColor: Color? = nil,
        placeholderSize: CGSize = CGSize(width: 25, height: 25),
        isFromPms: Bool = false,
        showImageBackground: Color? = nil
    ) {
        self.imagePath = imagePath
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
    }

    // MARK: - BODY
    var body: some View {
        ZStack {
            if let path = imagePath,
                !path.isEmpty,
                let loadedImage = PhotoFileManager.shared.loadImage(from: path)
            {
                loadedImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: borderWidth)
                    )

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
                                .foregroundStyle(placeholderBackgroundColor ?? appColors.secondary)
                        )
                }
            }
        }
    }
}
