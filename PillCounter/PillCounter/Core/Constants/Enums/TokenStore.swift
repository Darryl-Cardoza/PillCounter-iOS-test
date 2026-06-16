//
//  TokenStore.swift
//  PillCounter
//
//  Seam over AppStorageManager so auth-related screens can be unit-tested
//  against an in-memory fake instead of the real Keychain/UserDefaults.
//

import Foundation

/// The subset of `AppStorageManager` that the login/auth flow needs.
/// Code depends on this protocol, not on `AppStorageManager.shared`,
/// so a mock can be injected in tests.
protocol TokenStore: AnyObject {
    var userSavedEmails: [String] { get set }
    var rememberMe: Bool { get set }
    var isNewUser: Bool { get set }

    var isLoggedIn: Bool { get set }
    var isHl7Enabled: Bool { get set }
    var accessToken: String? { get set }
    var refreshToken: String? { get set }
    var userEmail: String? { get set }
    var userId: String? { get set }
    var tokenExpiryTimestamp: Double? { get set }
}

// The real implementation already has every one of these members.
extension AppStorageManager: TokenStore {}
