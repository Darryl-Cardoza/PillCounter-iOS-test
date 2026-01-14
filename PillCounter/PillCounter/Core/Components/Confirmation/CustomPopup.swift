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
    let popupContent: () -> PopupContent

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                // Dimmed background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isPresented = false
                        }
                    }

                // Popup Content
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
