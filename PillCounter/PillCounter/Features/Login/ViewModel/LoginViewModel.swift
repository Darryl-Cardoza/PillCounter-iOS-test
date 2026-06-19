//
//  LoginViewModel.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import SwiftUI

@MainActor
class LoginViewModel: ObservableObject {

    // MARK: - Published UI state
    @Published var userEmail: String = ""
    @Published var isChecked: Bool = false
    @Published var userSavedEmails: [String] = []
    @Published var otp: [String] = Array(repeating: "", count: 4)
    @Published var errorMessage: String?
    @Published var resendOTPSent: Bool = false
    @Published var isOtpSent: Bool = false
    @Published var isOtpVerificationSuccess: Bool = false
    @Published var isLoading: Bool = false
    @Published var isLogoutSucces: Bool = false

    // MARK: - Resend timer
    @Published var resendCooldown: Int = 60
    @Published var isResendDisabled: Bool = true
    private var resendTimer: Timer?

    // MARK: - Derived
    var resendTimerText: String { "\(resendCooldown) s" }
    var isOtpComplete: Bool { otp.joined().count == 4 }

    // MARK: - Injected dependencies
    private let loginrepo: LoginRepositoryProtocol
    private let store: TokenStore

    // MARK: - Init
    /// Dependencies default to the production singletons, so existing call
    /// sites (`LoginViewModel()`) keep working unchanged. Tests pass mocks.
    init(
        loginRepository: LoginRepositoryProtocol = LoginRepository.shared,
        store: TokenStore = AppStorageManager.shared
    ) {
        self.loginrepo = loginRepository
        self.store = store
        userSavedEmails = store.userSavedEmails
    }

    // MARK: - Timer
    func startResendTimer() {
        resendTimer?.invalidate()
        resendCooldown = 60
        isResendDisabled = true
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            if self.resendCooldown > 0 {
                self.resendCooldown -= 1
            } else {
                timer.invalidate()
                self.isResendDisabled = false
            }
        }
    }

    // MARK: - Remember Me
    func rememberMe() {
        let trimmedEmail = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        if let index = userSavedEmails.firstIndex(of: trimmedEmail) {
            userSavedEmails.remove(at: index)
        }
        userSavedEmails.append(trimmedEmail)

        if userSavedEmails.count > 5 {
            userSavedEmails.removeFirst(userSavedEmails.count - 5)
        }

        store.userSavedEmails = userSavedEmails
    }

    // MARK: - Send OTP
    func sendOTP() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if isChecked {
            rememberMe()
            store.rememberMe = true
        }

        do {
            let result = try await loginrepo.sendOTP(email: userEmail)
            if result.isSuccess ?? false {
                errorMessage = nil
                isOtpSent = true
                store.isNewUser = result.data?.isNewUser ?? true
            } else {
                resendOTPSent = false
                errorMessage = result.message ?? "Something went wrong. Please try again later."
            }
        } catch {
            isOtpSent = false
            resendOTPSent = false
            errorMessage = "Something went wrong."
            Log("sendOTP error: \(error)")
        }
    }

    // MARK: - Verify OTP
    func verifyOTP() async {
        errorMessage = nil
        let otpString = otp.joined()

        guard !otpString.isEmpty else { errorMessage = "Please enter the OTP."; return }
        guard otpString.count == 4 else { errorMessage = "Invalid OTP."; return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await loginrepo.verifyOTP(
                email: userEmail,
                otp: otpString,
                fcmToken: ""
            )

            if result.isSuccess ?? false {
                otp = ["", "", "", ""]
                isOtpVerificationSuccess = true

                // All sensitive values written to Keychain via AppStorageManager
                store.isLoggedIn   = true
                store.isPmsIntegrated = result.data?.user?.isPmsIntegrated ?? false
                store.allowLocalStorage = result.data?.user?.allowLocalStorage ?? false
                store.accessToken  = result.data?.accessToken ?? ""
                store.refreshToken = result.data?.refreshToken ?? ""
                store.userEmail    = userEmail
                store.userId       = result.data?.user?.userId ?? ""

                let expiresIn = TimeInterval(result.data?.expiresIn ?? 86400)
                store.tokenExpiryTimestamp =
                    Date().addingTimeInterval(expiresIn).timeIntervalSince1970

                await MainActor.run {
                    SessionManager.shared.reset()
                    Hl7ServiceController.shared.evaluate()
                }
                print("IsPmsIntegrated \(store.isPmsIntegrated)")
                print("allowLocalStorage \(store.allowLocalStorage)")
            } else {
                errorMessage = result.message ?? "Invalid OTP. Please try again."
            }

        } catch {
            isOtpVerificationSuccess = false
            errorMessage = "Unable to verify OTP. Please try again."
        }
    }

    // MARK: - Logout
    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await loginrepo.logout(
                refreshToken: store.refreshToken ?? ""
            )

            if result.isSuccess ?? false {
                errorMessage = nil
                isLogoutSucces = true
            }

            Task { @MainActor in
                Hl7ServiceController.shared.evaluate()
            }
        } catch {
            Log("logout error: \(error)")
        }
    }

    // MARK: - Resend OTP
    func resendOTP() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await loginrepo.resendOTP(email: userEmail)
            if result.isSuccess ?? false {
                resendOTPSent = true
                errorMessage = "A new OTP has been sent."
                startResendTimer()
                otp = ["", "", "", ""]
            } else {
                errorMessage = result.message ?? "Something went wrong!"
            }
        } catch {
            errorMessage = "Something went wrong!"
        }
    }
}
