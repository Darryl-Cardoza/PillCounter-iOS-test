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
    @EnvironmentObject private var toastManager: ToastManager

    @State private var showDeleteConfirmation: Bool = false

    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true

    @State private var firstName: String = ""
    
    @State private var npiText: String = ""

    
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
                headerActions: { EmptyView() },
                showBackButton: true,
                showHamburgerMenu: false,
                title: L10n.Menu.profile,
                backgroundColor: appColors.primaryBackground,
                allowKeyboardResize: false,
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
            title: L10n.Profile.Popup.confirmDeleteTitle,
            message: L10n.Profile.Popup.confirmDeleteMessage,
            cancelButtonText: L10n.Common.cancel,
            confirmButtonText: L10n.Common.delete,
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
        VStack(alignment: .leading, spacing: 16) {

            FloatingLabelTextField(
                placeholder: L10n.Profile.firstName,
                text: $userViewModel.firstName,
                maxLength: 30
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.lastName,
                text: $userViewModel.lastName,
                maxLength: 30
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.pharmacyName,
                text: $userViewModel.pharmacyName,
                maxLength: 30
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.phoneNumber,
                text: $userViewModel.phoneNumber,
                keyboardType: .phonePad,
                maxLength: 10
            )

            FloatingLabelTextField(
                placeholder: L10n.Common.email,
                text: $userViewModel.email,
                disabled: true
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.npiId,
                text: $userViewModel.npiID,
                keyboardType: .phonePad,
                maxLength: 10
            )

            if !userViewModel.terminals.isEmpty {
                terminalDropdown
            }
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
            FloatingLabelTextField(
                placeholder: L10n.Profile.firstName,
                text: $userViewModel.firstName,
                maxLength: 30
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.pharmacyName,
                text: $userViewModel.pharmacyName,
                maxLength: 30
            )

            FloatingLabelTextField(
                placeholder: L10n.Common.email,
                text: $userViewModel.email,
                disabled: true
            )

            if !userViewModel.terminals.isEmpty {
                terminalDropdown
            }
        }
    }

    private var rightProfileColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            FloatingLabelTextField(
                placeholder: L10n.Profile.lastName,
                text: $userViewModel.lastName,
                maxLength: 30
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.phoneNumber,
                text: $userViewModel.phoneNumber,
                keyboardType: .phonePad,
                maxLength: 10
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.npiId,
                text: $userViewModel.npiID,
                keyboardType: .phonePad,
                maxLength: 10
            )
        }
    }

    private var terminalDropdown: some View {
        Menu {
            ForEach(userViewModel.terminals, id: \.terminalId) { terminal in
                Button {
                    guard terminal.terminalId != userViewModel.pendingTerminal?.terminalId else { return }
                    userViewModel.selectTerminal(terminal)
                } label: {
                    HStack {
                        Text(terminal.terminalName ?? "")
                        if terminal.terminalId == userViewModel.pendingTerminal?.terminalId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            ZStack(alignment: .leading) {
                Text(L10n.Profile.terminal)
                    .font(.caption)
                    .foregroundColor(appColors.text.opacity(0.75))
                    .offset(y: -16)
                    .padding(.leading, 16)

                HStack {
                    Text(userViewModel.pendingTerminal?.terminalName ?? "")
                        .font(.body)
                        .foregroundColor(appColors.text)
                        .padding(.leading, 16)
                        .padding(.top, 10)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(appColors.text.opacity(0.75))
                        .padding(.trailing, 16)
                        .padding(.top, 10)
                }
            }
            .frame(height: 64)
            .background(appColors.secondaryBackground)
            .cornerRadius(10)
        }
    }

    private var actionButtons: some View {
        EqualWidthHStackButtons(spacing: 16) {

            // DELETE
            PillCountingButton(
                iconName: nil,
                title: L10n.Common.delete,
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
//            PillCountingButton(
//                iconName: nil,
//                title: NSLocalizedString("SKIP", comment: ""),
//                textColor: appColors.primary,
//                backgroundColor: .clear,
//                borderColor: appColors.primary,
//                font: .system(size: 16, weight: .semibold),
//                cornerRadius: 40,
//                horizontalPadding: 22,
//                verticalPadding: 15,
//                iconSize: 24,
//                action: onSkipTapped
//            )

            // SAVE
            PillCountingButton(
                iconName: nil,
                title: L10n.Common.save,
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
            if !userViewModel.phoneNumber.isEmpty {
                if userViewModel.phoneNumber.count != 10 {
                    toastManager.show(message: L10n.Profile.Error.errorPhoneLengthMessage)
                    return
                }

                if !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: userViewModel.phoneNumber)) {
                    toastManager.show(message: L10n.Profile.Error.errorPhoneDigitsMessage)
                    return
                }
            }

            // Update terminal if selection changed
            let terminalChanged = userViewModel.pendingTerminal?.terminalId != userViewModel.selectedTerminal?.terminalId
            if let pending = userViewModel.pendingTerminal, terminalChanged {
                let terminalSuccess = await userViewModel.updateTerminal(pending)
                if !terminalSuccess {
                    toastManager.show(message: L10n.Profile.Error.errorUpdateTerminalMessage)
                    return
                }
                Hl7ServiceController.shared.restartForTerminalChange()
            }

            let profileChanged = userViewModel.hasProfileChanged()
            if profileChanged {
                await userViewModel.updateUserProfile()
                if !userViewModel.isProfileUpdated {
                    toastManager.show(message: L10n.Profile.Error.errorUpdateProfileMessage)
                    return
                }
                userViewModel.isProfileUpdated = false
            }

            toastManager.show(message: L10n.Profile.successUpdateMessage)
            isNewUser = false
            router.navigateBack()
        }
    }

    private func profileScreenLandscape() -> some View {
        VStack(spacing: 0) {

//            profileHeader

            ScrollView {
                VStack(spacing: 20) {

                    HStack(alignment: .top, spacing: 20) {
                        leftProfileColumn
                            .frame(maxWidth: .infinity, alignment: .leading)

                        rightProfileColumn
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                   
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                actionButtons
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .padding(.top, 65 )
        .background(appColors.primaryBackground)
    }
    
    private func profileScreenPotrait() -> some View {
        VStack(spacing: 0) {

//            profileHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    potraitProfileColums
                }
            }
            .padding(.horizontal)

            Spacer()
            
            HStack {
                Spacer()
                actionButtons
                Spacer()
            }
            .padding(.vertical)
        }
        .padding(.top, 65)
    }
    
//    private var profileHeader: some View {
//        HStack {
//            if !isNewUser {
//                Button {
//                    router.navigateBack()
//                } label: {
//                    HStack {
//                        Image("back_icon")
//                            .resizable()
//                            .scaledToFit()
//                            .frame(width: 24, height: 24)
//
//                        Text(NSLocalizedString("PROFILE", comment: ""))
//                            .font(.headline)
//                            .foregroundStyle(appColors.text)
//                    }
//                }
//            }
//
//            Spacer()
//        }
//        .padding(.horizontal)
//        .padding(.vertical,10)
//        .padding(.bottom, 30)
//    }
}
