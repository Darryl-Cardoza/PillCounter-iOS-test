//
//  AppLogoutManager.swift
//  PillCounter
//
//  Created by Bhushan Patil on 18/02/26.
//

import SwiftUI

final class AppLogoutManager {

    static func performLogout(
        userVM: UserViewModel,
        pillScanVM: PillScanViewModel,
        loginViewModel: LoginViewModel
    ) {
        // Wipe Keychain credentials only — local CoreData is preserved so returning
        // users find their history intact on next login.
        AppStorageManager.shared.logout()

        Task { @MainActor in
            userVM.resetState()
            pillScanVM.resetState()
        }
    }
}
