//
//  PillCountingIconView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 13/05/26.
//

import SwiftUI

struct PillCountingIconView: View {

    let imageName: String
    let size: CGFloat
    let padding: CGFloat
    let foregroundColor: Color
    let backgroundColor: Color
    let scaleOnIpad: Bool

    private var scale: CGFloat {
        scaleOnIpad && UIDevice.current.userInterfaceIdiom == .pad
        ? 1.5
        : 1.0
    }

    var body: some View {
        Image(imageName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(
                width: size * scale,
                height: size * scale
            )
            .foregroundStyle(foregroundColor)
            .padding(padding * scale)
            .background(backgroundColor)
            .clipShape(Circle())
    }
}
