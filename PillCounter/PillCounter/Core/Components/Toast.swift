//
//  Toast.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/02/26.
//

import SwiftUI

final class ToastManager: ObservableObject {

    /// Shared instance so non-View types (e.g. view models) can surface the single
    /// global toast without dependency-injection plumbing. The app injects this same
    /// instance as an environment object.
    static let shared = ToastManager()

    @Published var message: String = ""
    @Published var isShowing: Bool = false

    private var dismissWorkItem: DispatchWorkItem?

    func show(message: String, duration: Double = 2.0) {
        // Ensure UI mutation happens on the main thread regardless of caller.
        DispatchQueue.main.async {
            self.dismissWorkItem?.cancel()
            self.message = message

            withAnimation {
                self.isShowing = true
            }

            let work = DispatchWorkItem {
                withAnimation {
                    self.isShowing = false
                }
            }
            self.dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }
}
