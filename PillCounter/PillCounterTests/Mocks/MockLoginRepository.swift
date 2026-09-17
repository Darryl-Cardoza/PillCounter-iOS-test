//
//  MockLoginRepository.swift
//  PillCounterTests
//
//  Scriptable fake for LoginViewModel tests — no network, no Keychain.
//

import Foundation
@testable import PillCounter

final class MockLoginRepository: LoginRepositoryProtocol {

    var sendOTPResult: Result<SendOTPResponse, Error> = .success(SendOTPResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil))
    var resendOTPResult: Result<SendOTPResponse, Error> = .success(SendOTPResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil))
    var verifyOTPResult: Result<VerifyOTPResponse, Error> = .success(VerifyOTPResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil))
    var logoutResult: Result<LogoutResponse, Error> = .success(LogoutResponse(status: 200, isSuccess: true, message: nil))

    private(set) var logoutCallCount = 0

    func sendOTP(email: String) async throws -> SendOTPResponse {
        try sendOTPResult.get()
    }

    func resendOTP(email: String) async throws -> SendOTPResponse {
        try resendOTPResult.get()
    }

    func verifyOTP(email: String, otp: String, fcmToken: String, deviceKey: String, appVersion: String) async throws -> VerifyOTPResponse {
        try verifyOTPResult.get()
    }

    func logout(refreshToken: String, deviceKey: String) async throws -> LogoutResponse {
        logoutCallCount += 1
        return try logoutResult.get()
    }
}

/// In-memory `TokenStore` — the login flow's seam over `AppStorageManager`,
/// so tests never touch the real Keychain/UserDefaults.
final class MockTokenStore: TokenStore {
    var userSavedEmails: [String] = []
    var rememberMe: Bool = false
    var isNewUser: Bool = false
    var isLoggedIn: Bool = false
    var isPmsIntegrated: Bool = false
    var isStandalone: Bool = false
    var allowLocalStorage: Bool = false
    var accessToken: String?
    var refreshToken: String?
    var userEmail: String?
    var userId: String?
    var tokenExpiryTimestamp: Double?
}
