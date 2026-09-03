//
//  SessionLockWindow.swift
//  PillCounter
//
//  SessionLockOverlay must block every screen, including content presented
//  via .sheet/.fullScreenCover (e.g. UnifiedCameraView's grid/full-image
//  cover) — those render inside the key window's own hierarchy, above the
//  app's root view, so no zIndex inside that root view can ever draw above
//  them, and presenting the lock screen as a cover of its own just queues
//  behind whatever's already presented instead of jumping the line. A
//  separate UIWindow above the key window's level sits outside that
//  hierarchy entirely, so it stays on top unconditionally — the same
//  mechanism iOS itself uses to draw system alerts above app UI.
//
//  The window itself is created once (so there's no per-lock creation delay
//  or launch-time flash), but the SwiftUI content it hosts is rebuilt fresh
//  on every show — matching exactly how the old in-ZStack overlay behaved
//  (`if isOverlayVisible { SessionLockOverlay() }` tore the view, its
//  FaceAuthenticationViewModel, and its camera session down and rebuilt them
//  from scratch every lock/unlock cycle). Reusing one long-lived instance
//  instead left camera/session state stuck from a previous cycle.
//

import SwiftUI
import UIKit

@MainActor
final class SessionLockWindowController {

    static let shared = SessionLockWindowController()

    private var window: UIWindow?
    private var appColors: AppColors?

    /// The app's normal key window, restored when the lock window hides.
    /// Without this, hiding the lock window leaves no window key, and
    /// touches/camera focus underneath become inconsistent.
    private weak var mainWindow: UIWindow?

    private init() {}

    /// Call once at launch, before the initial `isOverlayVisible` value is
    /// read, so the window exists and is already showing/hiding the correct
    /// state by the first frame — attaching after a frame has rendered lets
    /// the dashboard flash through before the lock window appears.
    func attach(appColors: AppColors, initiallyVisible: Bool) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        self.appColors = appColors
        mainWindow = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first

        let window = UIWindow(windowScene: scene)
        // Above alerts/action sheets/fullScreenCover/sheet presentation
        // layers so nothing else in the app can ever cover it.
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        self.window = window
        setVisible(initiallyVisible)
    }

    func setVisible(_ visible: Bool) {
        guard let window, let appColors else { return }
        if visible {
            // Fresh instance every time — same lifecycle the old
            // `if isOverlayVisible { SessionLockOverlay() }` gave it, so
            // FaceAuthenticationViewModel/camera state always starts clean.
            let hostingController = UIHostingController(
                rootView: SessionLockOverlay().environmentObject(appColors)
            )
            hostingController.view.backgroundColor = .clear
            window.rootViewController = hostingController

            window.isHidden = false
            // Key, not just visible — otherwise the tap-catching layer in
            // SessionLockOverlay doesn't reliably intercept touches, and
            // camera focus/responder state underneath (e.g. UnifiedCameraView)
            // can stay attached to the covered window.
            window.makeKeyAndVisible()
        } else {
            window.isHidden = true
            window.rootViewController = nil
            mainWindow?.makeKeyAndVisible()
        }
    }
}
