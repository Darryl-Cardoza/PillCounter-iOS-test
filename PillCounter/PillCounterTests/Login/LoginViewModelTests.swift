//
//  LoginViewModelTests.swift
//  PillCounterTests
//
//  logout() regression coverage — a real bug found in review: typed-in form
//  state, the resend timer, and errorMessage were left behind across a
//  logout->login cycle since LoginViewModel is a single app-scoped instance
//  (see PillCounterApp.swift), not recreated per session.
//

import Testing
import Foundation
@testable import PillCounter

/// Captures the exact `refreshToken` passed to `logout`, so a test can prove
/// the caller-supplied token reaches the network call unmodified.
private final class RefreshTokenCapturingLoginRepository: LoginRepositoryProtocol {
    private(set) var capturedRefreshToken: String?
    var logoutResult: Result<LogoutResponse, Error> = .success(LogoutResponse(status: 200, isSuccess: true, message: nil))

    func sendOTP(email: String) async throws -> SendOTPResponse { SendOTPResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil) }
    func resendOTP(email: String) async throws -> SendOTPResponse { SendOTPResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil) }
    func verifyOTP(email: String, otp: String, fcmToken: String, deviceKey: String, appVersion: String) async throws -> VerifyOTPResponse {
        VerifyOTPResponse(status: 200, isSuccess: true, message: nil, token: nil, data: nil)
    }
    func logout(refreshToken: String, deviceKey: String) async throws -> LogoutResponse {
        capturedRefreshToken = refreshToken
        return try logoutResult.get()
    }
}

@MainActor
@Suite
struct LoginViewModelTests {

    private func makeSUT(logoutResult: Result<LogoutResponse, Error> = .success(LogoutResponse(status: 200, isSuccess: true, message: nil))) -> (LoginViewModel, MockLoginRepository, MockTokenStore) {
        let repo = MockLoginRepository()
        repo.logoutResult = logoutResult
        let store = MockTokenStore()
        let sut = LoginViewModel(loginRepository: repo, store: store)
        return (sut, repo, store)
    }

    @Test func logoutClearsTypedFormStateOnSuccess() async {
        let (sut, _, _) = makeSUT()
        sut.userEmail = "someone@example.com"
        sut.isChecked = true
        sut.otp = ["1", "2", "3", "4", "5", "6"]
        sut.isOtpSent = true
        sut.isOtpVerificationSuccess = true
        sut.resendOTPSent = true

        await sut.logout(refreshToken: "test-refresh-token")

        #expect(sut.userEmail == "")
        #expect(sut.isChecked == false)
        #expect(sut.otp == Array(repeating: "", count: 6))
        #expect(sut.isOtpSent == false)
        #expect(sut.isOtpVerificationSuccess == false)
        #expect(sut.resendOTPSent == false)
    }

    @Test func logoutClearsErrorMessageEvenWhenTheServerCallFails() async {
        let (sut, _, _) = makeSUT(logoutResult: .failure(URLError(.notConnectedToInternet)))
        sut.errorMessage = "Invalid OTP. Please try again."

        await sut.logout(refreshToken: "test-refresh-token")

        #expect(sut.errorMessage == nil)
    }

    @Test func logoutInvalidatesTheResendTimerSoItStopsTicking() async throws {
        let (sut, _, _) = makeSUT()
        sut.startResendTimer()
        #expect(sut.resendCooldown == 60)

        await sut.logout(refreshToken: "test-refresh-token")

        // Sentinel value the running timer would overwrite within 1s if it
        // were still ticking — proves logout() actually invalidated it
        // instead of merely being a documented-but-unverified contract.
        sut.resendCooldown = -1
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(sut.resendCooldown == -1)
    }

    @Test func logoutSetsIsLogoutSuccesOnlyWhenServerCallSucceeds() async {
        let (sut, _, _) = makeSUT(logoutResult: .success(LogoutResponse(status: 200, isSuccess: false, message: "nope")))

        await sut.logout(refreshToken: "test-refresh-token")

        #expect(sut.isLogoutSucces == false)
    }

    /// Regression test for a real bug found in review: the caller
    /// (HamburgerMenuView) must capture the refresh token BEFORE wiping the
    /// Keychain, since `logout()` no longer reads `store.refreshToken`
    /// itself — this proves whatever the caller passes in is exactly what
    /// reaches the network call, unmodified.
    @Test func logoutSendsTheCallerSuppliedRefreshTokenUnmodified() async {
        let repo = RefreshTokenCapturingLoginRepository()
        let sut = LoginViewModel(loginRepository: repo, store: MockTokenStore())

        await sut.logout(refreshToken: "captured-before-wipe")

        #expect(repo.capturedRefreshToken == "captured-before-wipe")
    }
}
