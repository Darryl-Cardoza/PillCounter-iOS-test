//
//  OrientationLock.swift
//  PillCounter
//
//  Lets a specific screen (e.g. face enrollment/authentication) temporarily
//  restrict which interface orientations the app allows, on top of the
//  app-wide portrait+landscape support declared in the build settings
//  (INFOPLIST_KEY_UISupportedInterfaceOrientations*).
//
//  UIKit only consults `AppDelegate.application(_:supportedInterfaceOrientationsFor:)`
//  when it re-evaluates rotation (backgrounding, a new window, or an explicit
//  attemptRotationToDeviceOrientation() call) — so callers MUST call
//  `apply()` after changing `current`, not just set the property.
//

import UIKit

final class OrientationLock {
    static let shared = OrientationLock()
    private init() {}

    /// nil = defer to the app-wide default (whatever the build settings allow).
    var current: UIInterfaceOrientationMask?

    /// Locks to portrait on iPhone, landscape on iPad — the orientation a
    /// face-capture camera preview should always render in, regardless of
    /// how the app's other screens behave. Call on screen appear.
    func lockForFaceCapture() {
        current = UIDevice.current.userInterfaceIdiom == .pad ? .landscape : .portrait
        apply()
    }

    /// Releases back to the app-wide default. Call on screen disappear.
    func unlock() {
        current = nil
        apply()
    }

    /// Forces UIKit to re-query `supportedInterfaceOrientationsFor:` and
    /// rotate to match `current` if the device isn't already in an allowed
    /// orientation. Without this, setting `current` alone has no visible
    /// effect until some other event happens to trigger a re-evaluation.
    private func apply() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        let mask = current ?? (UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            Log("OrientationLock: geometry update failed — \(error)")
        }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
