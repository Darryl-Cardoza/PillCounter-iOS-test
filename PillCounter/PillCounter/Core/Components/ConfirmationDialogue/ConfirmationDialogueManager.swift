//
//  ConfirmationDialogueManager.swift
//  PillCounter
//
//  Created by HC on 13/11/25.
//

import SwiftUI

class ConfirmationDialogueManager: ObservableObject {
    @Published var isShowing = false
    @Published var popupView: AnyView = AnyView(EmptyView())
    
    private var onConfirm: (() -> Void)? = nil

    func showConfirmation<Content: View>(
        @ViewBuilder content: () -> Content,
        onConfirm: @escaping () -> Void
    ) {
        self.popupView = AnyView(content())
        self.onConfirm = onConfirm
        self.isShowing = true
    }

    func confirm() {
        onConfirm?()
        hide()
    }

    func hide() {
        isShowing = false
        popupView = AnyView(EmptyView())
        onConfirm = nil
    }
}
