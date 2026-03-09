//
//  CustomPopup.swift
//  PillCounter
//
//  Created by HC on 17/11/25.
//

import SwiftUI

struct CustomPopup<PopupContent: View>: ViewModifier {

    @EnvironmentObject private var appColors: AppColors

    @Binding var isPresented: Bool
    var dismissOnBackgroundTap: Bool = true
    let popupContent: () -> PopupContent

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {

                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if dismissOnBackgroundTap {
                            withAnimation {
                                isPresented = false
                            }
                        }
                    }

                popupContent()
                    .frame(maxWidth: 300)
                    .padding()
                    .background(appColors.primaryBackground)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .transition(.scale)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut, value: isPresented)
    }
}

extension View {
    func customPopup<PopupContent: View>(
        isPresented: Binding<Bool>,
        dismissOnBackgroundTap: Bool = true,
        @ViewBuilder content: @escaping () -> PopupContent
    ) -> some View {
        modifier(
            CustomPopup(
                isPresented: isPresented,
                dismissOnBackgroundTap: dismissOnBackgroundTap,
                popupContent: content
            )
        )
    }
}
