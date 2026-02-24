//
//  Toast.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/02/26.
//

import SwiftUI

final class ToastManager: ObservableObject {

    @Published var message: String = ""
    @Published var isShowing: Bool = false

    func show(message: String, duration: Double = 2.0) {
        self.message = message

        withAnimation {
            isShowing = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation {
                self.isShowing = false
            }
        }
    }
}
