//
//  Login.swift
//  PillCounter
//
//  Created by HC on 31/10/25.
//

import SwiftUI

struct LoginLogoView: View {
    
    @EnvironmentObject private var appColors: AppColors
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                appColors.secondaryBackground
                    .ignoresSafeArea()

                VStack {
                    Spacer(minLength: geometry.safeAreaInsets.top)

                    Spacer()

                    Image("icon_app")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width * 0.25,
                            height: geometry.size.width * 0.25
                        )

                    Text(L10n.Common.appName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "#01BBD3"))

                    Spacer()

                    VStack(spacing: 8) {
                        Text(L10n.Common.companyName)
                            .font(.subheadline)
                            .foregroundColor(appColors.text)
                        Text("\(L10n.Common.version) 1.0.0")
                            .font(.subheadline)
                            .foregroundColor(appColors.text)
                    }
                    .padding(.vertical)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
