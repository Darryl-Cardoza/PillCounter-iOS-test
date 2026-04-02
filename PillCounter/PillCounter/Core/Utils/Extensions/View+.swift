//
//  View+.swift
//  PillCounter
//
//  Created by HC on 17/11/25.
//

import SwiftUI

extension View {
    func customPopup<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(
            CustomPopup(isPresented: isPresented, popupContent: content))
    }
}

struct WidthReader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: MaxWidthPreferenceKey.self,
                            value: geo.size.width
                        )
                }
            )
    }
}

extension View {
    func readWidth() -> some View {
        self.modifier(WidthReader())
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        self.modifier(KeyboardAdaptive())
    }
}

struct MaxWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


extension UIImage {
    
    func fixOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}
