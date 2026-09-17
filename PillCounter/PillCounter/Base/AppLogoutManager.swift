//
//  AppLogoutManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 18/02/26.
//

import SwiftUI

@MainActor
final class AppLogoutManager {

    /// Synchronous and `@MainActor` (not a fire-and-forget `Task`) so a
    /// caller that navigates right after this call — e.g.
    /// `router.navigateToRoot()` — is guaranteed `FaceSessionManager` has
    /// already been reset by the time the new screen renders. Wrapping this
    /// in a `Task` previously let navigation race `resetOnLogout()`, risking
    /// a one-frame flash of the stale face-lock overlay over the login screen.
    ///
    /// Returns the refresh token captured *before* the Keychain wipe below,
    /// for the caller to pass to `LoginViewModel.logout(refreshToken:)` —
    /// capturing it here, structurally ahead of the wipe, means a future
    /// call site can't regress the ordering by reading the token itself
    /// after calling this.
    @discardableResult
    static func performLogout(
        userVM: UserViewModel,
        pillScanVM: PillScanViewModel,
        loginViewModel: LoginViewModel
    ) -> String {
        let refreshToken = AppStorageManager.shared.refreshToken ?? ""

        // Wipe Keychain credentials only — local CoreData is preserved so returning
        // users find their history intact on next login.
        AppStorageManager.shared.logout()

        userVM.resetState()
        pillScanVM.resetState()
        FaceSessionManager.shared.resetOnLogout()
        // isLoggedIn is already false by this point (cleared above), so
        // evaluate() sees shouldStartService == false and tears the HL7
        // connection down — otherwise it stays connected in the background
        // after logout.
        Hl7ServiceController.shared.evaluate()

        return refreshToken
    }
}
