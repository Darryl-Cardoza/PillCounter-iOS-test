//
//  IsLandscapeEnvironmentKey.swift
//  PillCounter
//
//  ✅ Replace your existing isLandscape environment extension with this entire file.
//  Delete or clear whatever file currently declares `var isLandscape` in EnvironmentValues.
//

import SwiftUI

// MARK: - Environment Key (device-orientation based, keyboard-safe)

private struct IsLandscapeKey: EnvironmentKey {
    static let defaultValue: Bool = {
        let o = UIDevice.current.orientation
        if o.isValidInterfaceOrientation { return o.isLandscape }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }()
}

//extension EnvironmentValues {
//    // ⚠️ Make sure NO other file in the project declares `var isLandscape` here.
//    var isLandscape: Bool {
//        get { self[IsLandscapeKey.self] }
//        set { self[IsLandscapeKey.self] = newValue }
//    }
//}

// MARK: - OrientationObserver
//
// Add ONCE at your app root:
//
//   WindowGroup {
//       ContentView()
//           .modifier(OrientationObserver())
//   }

struct OrientationObserver: ViewModifier {
    @State private var isLandscape: Bool = {
        let o = UIDevice.current.orientation
        if o.isValidInterfaceOrientation { return o.isLandscape }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }()

    func body(content: Content) -> some View {
        content
            .environment(\.isLandscape, isLandscape)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIDevice.orientationDidChangeNotification
                )
            ) { _ in
                let o = UIDevice.current.orientation
                guard o.isValidInterfaceOrientation else { return }
                let newValue = o.isLandscape
                if isLandscape != newValue {
                    isLandscape = newValue
                }
            }
    }
}
