//
//  PillCountingButton.swift
//  PillCounter
//
//  Created by HC on 04/11/25.
//

import SwiftUI

struct PillCountingButton: View {
    // MARK: - Properties

    let iconName: String?
    let title: String
    let action: () -> Void
    let textColor: Color
    let backgroundColor: Color
    let borderColor: Color

    // Changed from let frameWidth: CGFloat? to be more flexible
    let width: CGFloat?

    // icon color
    let iconColor: Color?

    // Customizable appearance parameters
    var font: Font
    var cornerRadius: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var iconSize: CGFloat

    // MARK: - Init

    init(
        iconName: String? = nil,
        title: String,
        textColor: Color = .white,
        backgroundColor: Color = .blue,
        borderColor: Color = .clear,
        font: Font = .system(size: 16, weight: .medium),
        cornerRadius: CGFloat = 32,
        horizontalPadding: CGFloat = 20,
        verticalPadding: CGFloat = 14,
        iconSize: CGFloat = 20,
        action: @escaping () -> Void,
        width: CGFloat? = nil, // Renamed for clarity
        iconColor: Color? = nil
    ) {
        self.iconName = iconName
        self.title = title
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.font = font
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.iconSize = iconSize
        self.action = action
        self.width = width
        self.iconColor = iconColor
    }

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = iconName, !iconName.isEmpty {
                    Group {
                        if let iconColor = iconColor {
                            Image(iconName)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(iconColor)
                        } else {
                            Image(iconName)
                                .resizable()
                        }
                    }
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                }

                Text(title)
                    .font(font)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: width, maxWidth: width == nil ? .infinity : nil,  alignment: .center)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .cornerRadius(cornerRadius)
            .contentShape(Rectangle()) 
        }
        .buttonStyle(.plain)
    }
}



struct PillCountingTextButtonWithoutBg: View {

    let iconName: String?
    let title: String
    let action: () -> Void
    let textColor: Color
    let iconColor: Color?

    var font: Font
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var iconSize: CGFloat

    init(
        iconName: String? = nil,
        title: String,
        textColor: Color = .primary,
        font: Font = .system(size: 16, weight: .medium),
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 14,
        iconSize: CGFloat = 20,
        action: @escaping () -> Void,
        iconColor: Color? = nil
    ) {
        self.iconName = iconName
        self.title = title
        self.textColor = textColor
        self.font = font
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.iconSize = iconSize
        self.action = action
        self.iconColor = iconColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let iconName = iconName, !iconName.isEmpty {
                    Group {
                        if let iconColor = iconColor {
                            Image(iconName)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(iconColor)
                        } else {
                            Image(iconName)
                                .resizable()
                        }
                    }
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                }

                Text(title)
                    .font(font)
                    .foregroundColor(textColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle()) // tap area preserved
        }
        .buttonStyle(.plain)
    }
}
