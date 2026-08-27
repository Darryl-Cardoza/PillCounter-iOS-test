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
            // isLoggedIn is already false by this point (cleared above), so
            // evaluate() sees shouldStartService == false and tears the HL7
            // connection down — otherwise it stays connected in the background
            // after logout.
            Hl7ServiceController.shared.evaluate()
        }
    }
}
