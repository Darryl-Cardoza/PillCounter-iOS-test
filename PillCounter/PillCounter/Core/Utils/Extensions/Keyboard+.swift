//
//  Keyboard.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import Combine
import SwiftUI

struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                // The keyboard height notification already includes the home-indicator
                // safe area at the bottom of the screen; the view's own safe-area inset
                // covers that same strip, so subtracting it avoids double-counting and
                // the resulting dead gap between the keyboard and the content above it.
                .padding(.bottom, max(0, keyboardHeight - proxy.safeAreaInsets.bottom))
        }
        .onReceive(Publishers.keyboardHeight) { height in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = height
            }
        }
    }
}

extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { $0.keyboardHeight }
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        return MergeMany(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

private extension Notification {
    var keyboardHeight: CGFloat {
        (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
    }
}

extension UIApplication {
    static func hideKeyboard() {
        shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
