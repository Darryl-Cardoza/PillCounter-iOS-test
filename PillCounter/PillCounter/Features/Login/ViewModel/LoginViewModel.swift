//
//  LoginViewModel.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import SwiftUI

@MainActor
class LoginViewModel: ObservableObject {
    // MARK: PROPERTIES
    @Published var userEmail: String = ""
    @Published var isChecked: Bool = false
    @Published var userSavedEmails: [String] = []  // saved emaiils should be in the database ? or because it is small we can keep it in app storage or shared prefs.
    @Published var otp: [String] = Array(repeating: "", count: 4)

    // error message
    @Published var errorMessage: String?

    @Published var resendOTPSent: Bool = false

    // App storage values -- used when after logging
    @AppStorage(AppStorageManager.AppStorageKeys.accessToken) var accessToken:
        String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.refreshToken) var refreshToken:
        String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.userEmail)
    var userEmailToSaveInUserDefaults: String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.rememberMe) var isRememberMe:
        Bool = false
    @AppStorage(AppStorageManager.AppStorageKeys.isLoggedIn) var isLoggedIn:
        Bool = false
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = false
    
    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable)
    

    
    var isHl7Enabled: Bool = false

    // for successful sending of the otp and navigate to the next screen.
    // successful otp sent to the email.
    @Published var isOtpSent: Bool = false

    // for successful verification of otp
    @Published var isOtpVerificationSuccess: Bool = false

    // for loading handling of the api calls.
    @Published var isLoading: Bool = false

    // for logout
    @Published var isLogoutSucces: Bool = false

    // MARK: - RESEND TIMER
    @Published var resendCooldown: Int = 60
    @Published var isResendDisabled: Bool = true

    private var resendTimer: Timer?

    // MARK: - DERVIED
    var resendTimerText: String {
        "\(resendCooldown) s"
    }

    var isOtpComplete: Bool {
        otp.joined().count == 4
    }
    
    // MARK: - TIMER CONTROL
    func startResendTimer() {
        resendTimer?.invalidate()
        
        resendCooldown = 60
        isResendDisabled = true
        
        resendTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] timer in
            guard let self else { return }
            
            if self.resendCooldown > 0 {
                self.resendCooldown -= 1
            } else {
                timer.invalidate()
                self.isResendDisabled = false
            }
        }
    }

    // MARK: INIT
    init() {
        // initialise this with the user defaults saved emails.
        userSavedEmails = AppStorageManager.shared.userSavedEmails
    }

    // repo
    private let loginrepo = LoginRepository.shared

    // MARK: REMEMBER ME
    func rememberMe() {

        // one more if remember me then user stays logged in always.

        // For now saving the emails into the userSavedEmails, the last 5 emails.
        // This function to be called at the time of login only if the user has set the isChecked boolean to true.

        // Trim whitespace just in case.
        let trimmedEmail = userEmail.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        DispatchQueue.main.async {
            if let index = self.userSavedEmails.firstIndex(of: trimmedEmail) {
                self.userSavedEmails.remove(at: index)
            }
        }

        DispatchQueue.main.async {
            self.userSavedEmails.append(trimmedEmail)
        }

        if userSavedEmails.count > 5 {
            userSavedEmails.removeFirst(userSavedEmails.count - 5)
        }

        AppStorageManager.shared.userSavedEmails = userSavedEmails

    }

    // MARK: SEND OTP
    func sendOTP() async {

        isLoading = true
        errorMessage = nil

        if isChecked {
            rememberMe()
            DispatchQueue.main.async {
                self.isRememberMe = true
            }
        }
        // calling the sendOTP repo call and accordingly updating the state of the ui.

        defer { isLoading = false }

        do {
            let sendOTPResult = try await loginrepo.sendOTP(email: userEmail)

            if sendOTPResult.isSuccess ?? false {
                errorMessage = nil
                // isOtpSent becomes true only when the sendOTPResult has a success.
                isOtpSent = true
                isNewUser = sendOTPResult.data?.isNewUser ?? true
            } else {
                resendOTPSent = false
                errorMessage =
                    sendOTPResult.message
                    ?? "Something went wrong. Please try again later."
            }

        } catch let error {
            isLoading = false
            isOtpSent = false
            resendOTPSent = false
            errorMessage = "Something went wrong."
            print("Error: \(error)")
        }
    }

    // MARK: VERIFY OTP
    func verifyOTP() async {
        errorMessage = nil
        let otpString = otp.joined()

        if otpString.isEmpty {
            errorMessage = "Please enter the OTP."
            return
        }

        if otpString.count < 4 {
            errorMessage = "Invalid OTP."
            return
        }

        isLoading = true

        do {

            defer { isLoading = false }

            let verifyOTPresult = try await loginrepo.verifyOTP(
                email: userEmail, otp: otpString)

            otp = ["", "", "", ""]

            if verifyOTPresult.isSuccess ?? false {
                errorMessage = nil
                isOtpVerificationSuccess = true
                isLoggedIn = true
                isHl7Enabled = verifyOTPresult.data?.user?.isHl7Enabled ?? false
                // store the access token and refresh token to the app storage or user defaults.
                // saving the user email to user defaults too.
                accessToken = verifyOTPresult.data?.accessToken ?? ""
                refreshToken = verifyOTPresult.data?.refreshToken ?? ""
                userEmailToSaveInUserDefaults = userEmail

                let expiresInSeconds = TimeInterval(
                    verifyOTPresult.data?.expiresIn ?? 86400)
                let expiryDate = Date().addingTimeInterval(expiresInSeconds)
                AppStorageManager.shared.tokenExpiryTimestamp =
                    expiryDate.timeIntervalSince1970
                
                
                await MainActor.run {
                    Hl7ServiceController.shared.evaluate()
                }
            } else {
                errorMessage =
                    verifyOTPresult.message
                    ?? "Something went wrong. Please try again later."
            }
            userEmail = ""
        } catch let error {
            isLoading = false
            isOtpVerificationSuccess = false
            errorMessage = "Something went wrong."
            print("Error: \(error)")
            userEmail = ""
        }
    }

    // MARK: LOGOUT
    func logout() async {
        isLoading = true

        defer { isLoading = false }
        do {
            let logoutResult = try await loginrepo.logout(
                refreshToken: refreshToken)

            if logoutResult.isSuccess ?? false {
                errorMessage = nil
                isLogoutSucces = true
            }

            Task { @MainActor in
                Hl7ServiceController.shared.evaluate()
            }
        } catch let error {
            isLoading = false
            print("Error: \(error)")
        }
    }

    // MARK: RESEND OTP
    func resendOTP() async {

        isLoading = true

        errorMessage = nil

        otp = ["", "", "", ""]

        defer { isLoading = false }
        // show some toast message to user to confirm that otp was resent.
        do {
            let result = try await loginrepo.resendOTP(email: userEmail)

            if result.isSuccess ?? false {
                resendOTPSent = true
                errorMessage = nil
                startResendTimer()
                // show toast message to user
            } else {
                errorMessage = result.message ?? "Something went wrong!"
            }
        } catch _ {
            errorMessage = "Something went wrong!"
        }
    }
    
    @MainActor
    func resetState() {

        // Stop timers
        resendTimer?.invalidate()
        resendTimer = nil

        // User input
        userEmail = ""
        otp = ["", "", "", ""]
        isChecked = false

        // Flags
        errorMessage = nil
        resendOTPSent = false
        isOtpSent = false
        isOtpVerificationSuccess = false
        isLoading = false
        isLogoutSucces = false

        // Cooldown
        resendCooldown = 60
        isResendDisabled = true
    
        userEmailToSaveInUserDefaults = ""
        isRememberMe = false
        isLoggedIn = false
        isNewUser = false
        isHl7Enabled = false

        // Reload saved emails from storage (after logout cleared them)
        userSavedEmails = AppStorageManager.shared.userSavedEmails
    }
}
