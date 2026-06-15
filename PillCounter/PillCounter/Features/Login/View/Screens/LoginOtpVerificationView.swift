//
//  LoginOtpVerificationView.swift
//  PillCounter
//
//  Created by HC on 03/11/25.
//

import SwiftUI

struct LoginOtpVerificationView: View {
    // MARK: PROPERTIES
    // environment objects
    @FocusState private var isKeyboardActive: Bool
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject var loginViewModel: LoginViewModel

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 0.5,
                topContent: {
                    LoginLogoView()
                },
                bottomContent: {
                    OtpVerification()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(appColors.primaryBackground)
                        .cornerRadius(24)
                        .keyboardAdaptive()
                },
                showBackButton: true,
                confirmBack: true
            )
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil,
                    from: nil,
                    for: nil)
            }

            if loginViewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    PillCountingLoader()
                }
            }
        }
        .onAppear {
            loginViewModel.startResendTimer()
        }
    }
}

// MARK: OTP VERIFICATION
struct OtpVerification: View {

    // Properties
    @EnvironmentObject var loginViewModel: LoginViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 35) {
            VStack(spacing: 0) {
                Text(L10n.OTP.codeSentText)
                    .foregroundStyle(appColors.text)
                    .font(.system(size: 18))

                Text(Formatter.maskEmail(loginViewModel.userEmail))
                    .foregroundStyle(appColors.text)
                    .font(.system(size: 18))
            }

            BoxesInputField(otp: $loginViewModel.otp, length: 4)
            
            if let errorMessage = loginViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(loginViewModel.resendOTPSent ? Color.green : Color.red)
                    .font(.system(size: 14))
            }

            HStack(spacing: 6) {
                Text(L10n.OTP.resendCode)
                    .foregroundStyle(
                        loginViewModel.isResendDisabled
                        ? Color.gray
                        : Color.pink
                    )
                
                if loginViewModel.isResendDisabled {
                    Text(loginViewModel.resendTimerText)
                        .foregroundStyle(Color.gray)
                        .font(.system(size: 14))
                }
            }
            .onTapGesture {
                guard !loginViewModel.isResendDisabled else { return }
                
                Task {
                    await loginViewModel.resendOTP()
                }
            }

            Button {
                // some action to be taken to verify the otp with the backend.
                // so here we will have to call the view model function and from the view model function we will call the respository api.
                
                Task {
                    await loginViewModel.verifyOTP()
                    
                    // after successfull otp verification need to call the get user.
                    // also if the user is new then directly load the profile screen to the user.
                    
                    if loginViewModel.isOtpVerificationSuccess {
                        router.setRoot(
                            to: .authentication(
                                .login(.dashboard(.dashboardHome))))
                    }
                }
                
            } label: {
                Text(L10n.OTP.verifyButton)
                    .foregroundColor(appColors.text)
                    .fontWeight(.semibold)
                    .padding(18)
                    .padding(.horizontal)
                    .background(
                        (!loginViewModel.isOtpComplete || loginViewModel.isLoading)
                        ? Color.gray.opacity(0.3)
                        : appColors.primary
                    )
                    .cornerRadius(50)
                    .frame(maxWidth: .infinity)
            }
            .disabled(loginViewModel.otp.joined().count < 4 || loginViewModel.isLoading)

        }
        .padding(.vertical, 32)
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil,
                for: nil)
        }

    }
}
