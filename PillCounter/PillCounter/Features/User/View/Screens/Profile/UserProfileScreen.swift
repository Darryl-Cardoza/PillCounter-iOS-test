//
//  UserProfileScreen.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct UserProfileScreen: View {

    @Environment(\.isLandscape) var isLandscape
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors

    @State private var showDeleteConfirmation: Bool = false

    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true

    @State private var firstName: String = ""
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    if !isLandscape {
                        profileScreenPotrait()
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .leading
                            )
                            .background(appColors.primaryBackground)
                    } else {
                        profileScreenLandscape()
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .leading
                            )
                            .background(appColors.primaryBackground)
                    }
                },
                bottomContent: {
                    EmptyView()
                },
                showBackButton: !isNewUser,
                showHamburgerMenu: false,
                title: NSLocalizedString("PROFILE", comment: "")
            )

            if userViewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    PillCountingLoader()
                }
            }
        }
        .onAppear {
            Task {
                await userViewModel.getUser()
            }
        }
        .onTapGesture {
            //            hideKeyboard()
            UIApplication.hideKeyboard()
        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            deleteConfirmation
        }
    }

    private var deleteConfirmation: some View {
        ConfirmationDialogue(
            title: NSLocalizedString("CONFIRM DELETE", comment: ""),
            message: NSLocalizedString(
                "Are you sure you want to delete your profile? This action cannot be undone.",
                comment: ""
            ),
            cancelButtonText: NSLocalizedString("CANCEL", comment: ""),
            confirmButtonText: NSLocalizedString("DELETE", comment: ""),
            onCancel: {
                showDeleteConfirmation = false
            },
            onConfirm: {
                showDeleteConfirmation = false
                Task {
                    await userViewModel.deleteUserProfile()

                    router.setRoot(to: .authentication(.login(.LoginEmail)))
                }
            }
        )
    }

    private var potraitProfileColums: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("FIRST_NAME", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.firstName,
                validation: .name,
                maxLength: 30
            )

            Text(NSLocalizedString("LAST_NAME", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.lastName,
                validation: .name,
                maxLength: 30
            )

            Text(NSLocalizedString("PHARMACY_NAME", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.pharmacyName,
                validation: .none,
                maxLength: nil
            )

            Text(NSLocalizedString("PHONE_NUMBER", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.phoneNumber,
                keyboardType: .phonePad,
                validation: .phone,
                maxLength: nil
            )

            Text(NSLocalizedString("EMAIL", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: true,
                text: $userViewModel.email,
                maxLength: nil
            )

            Text(NSLocalizedString("NPI_ID", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.npiID,
                keyboardType: .phonePad,
                validation: .phone,
                maxLength: nil
            )
        }
    }

    private var landscapeProfileColums: some View {
        HStack(alignment: .top, spacing: 12) {
            leftProfileColumn
            rightProfileColumn
        }
    }

    private var leftProfileColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("FIRST_NAME", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.firstName,
                validation: .name,
                maxLength: 30
            )

            Text(NSLocalizedString("PHARMACY_NAME", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.pharmacyName,
                validation: .none,
                maxLength: nil
            )

            Text(NSLocalizedString("EMAIL", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: true,
                text: $userViewModel.email,
                maxLength: nil      
            )
        }
    }

    private var rightProfileColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("LAST_NAME", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.lastName,
                validation: .name,
                maxLength: 30
            )

            Text(NSLocalizedString("PHONE_NUMBER", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.phoneNumber,
                keyboardType: .phonePad,
                validation: .phone,
                maxLength: 10
            )

            Text(NSLocalizedString("NPI_ID", comment: ""))
                .foregroundStyle(appColors.text)

            PillCounterInputField(
                imageName: nil,
                placeholder: "",
                disabled: false,
                text: $userViewModel.npiID,
                keyboardType: .phonePad,
                validation: .npi,
                maxLength: 10
            )
        }
    }

    private var actionButtons: some View {
        EqualWidthHStackButtons(spacing: 16) {

            // DELETE
            PillCountingButton(
                iconName: nil,
                title: NSLocalizedString("DELETE", comment: ""),
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 16, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 22,
                verticalPadding: 15,
                iconSize: 24,
                action: onDeleteTapped
            )

            // SKIP
            PillCountingButton(
                iconName: nil,
                title: NSLocalizedString("SKIP", comment: ""),
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 16, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 22,
                verticalPadding: 15,
                iconSize: 24,
                action: onSkipTapped
            )

            // SAVE
            PillCountingButton(
                iconName: nil,
                title: NSLocalizedString("SAVE", comment: ""),
                textColor: Color.white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 16, weight: .semibold),
                cornerRadius: 40,
                horizontalPadding: 22,
                verticalPadding: 15,
                iconSize: 24,
                action: onSaveTapped
            )
        }
    }

    private func onDeleteTapped() {
        showDeleteConfirmation = true
    }

    private func onSkipTapped() {
        router.navigateBack()
    }

    private func onSaveTapped() {
        Task {
            await userViewModel.updateUserProfile()

            if userViewModel.isProfileUpdated {
                // New user flow completed
                isNewUser = false
                userViewModel.isProfileUpdated = false
                router.navigateBack()
            }
        }
    }

    private func profileScreenLandscape() -> some View {
        VStack(spacing: 20) {
            Spacer().frame(height: SafeAreaInsets.top + 20)
            landscapeProfileColums
                .padding(.horizontal)

            HStack {
                Spacer()
                actionButtons
                Spacer()
            }
            .padding(.horizontal)

        }
        .padding(.horizontal, SafeAreaInsets.leading)
        .keyboardAdaptive()
    }

    private func profileScreenPotrait() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer().frame(height: 100)

            potraitProfileColums

            Spacer()

            HStack {
                Spacer()
                actionButtons
                Spacer()
            }
            .padding(.bottom)
        }
        .padding(.horizontal)
        .background(appColors.primaryBackground)
        .keyboardAdaptive()
    }

}

#Preview {
    let userViewModel = UserViewModel()
    UserProfileScreen()
        .preferredColorScheme(.dark)
        .environmentObject(userViewModel)
}
