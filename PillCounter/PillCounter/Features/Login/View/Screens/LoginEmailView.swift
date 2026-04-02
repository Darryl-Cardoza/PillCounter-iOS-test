//
//  LoginEmailView.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import SwiftUI

struct LoginEmailView: View {
    // Environment objects
    @EnvironmentObject private var loginViewModel: LoginViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    // MARK: - STATES
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var errorMessage: String?
    let config = ConfigurationManager.shared

    var body: some View {
        ZStack {
            BaseView {
                LoginLogoView()
            } bottomContent: {
                VStack(spacing: 20) {
                    Spacer()
                    // Email
                    PillCounterInputField(
                        imageName: "profile_icon",
                        placeholder: NSLocalizedString(
                            "EMAIL_INPUT_FIELD_PLACEHOLDER", comment: ""),
                        disabled: false,
                        text: $loginViewModel.userEmail,
                        keyboardType: .emailAddress,
                        showDropdownMenu: true,
                        dropdownData: loginViewModel.userSavedEmails,
                        onSubmit: {
                            Task {
                                errorMessage = nil
                                guard
                                    Validation.isValidEmail(
                                        loginViewModel.userEmail)
                                else {
                                    errorMessage = NSLocalizedString(
                                        "EMAIL_ERROR_MESSAGE", comment: "")
                                    return
                                }

                                await loginViewModel.sendOTP()
                                if loginViewModel.isOtpSent {
                                    router.navigate(
                                        to: .authentication(
                                            .login(.otpVerificationLogin)))
                                }
                            }
                        },
                        validation: .email
                    )

                    // error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Color.red)
                            .font(.caption)
                            .frame(
                                maxWidth: .infinity, alignment: .leading
                            )
                            .padding(.top, -15)
                    }

                    // checkbox
                    PillCounterCheckbox(
                        isChecked: $loginViewModel.isChecked,
                        label: NSLocalizedString("REMEMBER_ME", comment: "")
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Login Button
                    Button(action: {
                        errorMessage = nil
                        if let validationKey = Validation.validateEmail(loginViewModel.userEmail) {
                            loginViewModel.errorMessage = NSLocalizedString(validationKey, comment: "")
                            return
                        }
                        Task {
                            await loginViewModel.sendOTP()
                            if loginViewModel.isOtpSent {
                                router.navigate(
                                    to: .authentication(
                                        .login(.otpVerificationLogin)))
                            }
                        }
                    }) {
                        Text("LOGIN_BUTTON")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                            .frame(
                                width: UIScreen.main.bounds.width * 0.15,
                                height: 0
                            )
                            .padding(25)
                            .background(.cyan)
                            .cornerRadius(30)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appColors.primaryBackground)
                .cornerRadius(24)
                .keyboardAdaptive()
            }

            if loginViewModel.isLoading {
                ZStack {

                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    PillCountingLoader()
                }
            }
        }
        .onChange(of: loginViewModel.errorMessage) { oldValue, newValue in
            errorMessage = newValue
        }
    }
}
