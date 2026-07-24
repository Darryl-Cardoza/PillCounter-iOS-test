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
    @State private var selectedPharmacyType: PharmacyTypeOption? = nil
    @State private var selectedCountry: CountryOption? = nil
    @State private var selectedState: StateOption? = nil

//    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
//        Bool = true

    @State private var firstName: String = ""

    @State private var npiText: String = ""

    /// Terminal selection is a PMS-integration-only concept — disable the
    /// dropdown when PMS integration is off for this account.
    private var isPmsDisabled: Bool { !AppStorageManager.shared.isPmsIntegrated }

    
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
            // App launch already hydrated user/terminals/pharmacy-type from
            // auth/me into local storage — just read the cached data, no
            // network call on every profile visit.
            Task { await userViewModel.getUser(forceRemote: false) }
            Task {
                await userViewModel.fetchCountries()
                resolveSelectedCountryAndState()
            }
            let savedCode = AppStorageManager.shared.selectedPharmacyTypeCode
            selectedPharmacyType = userViewModel.pharmacyTypeOptions.first {
                $0.code == (savedCode ?? userViewModel.userProfileDetails?.pharmacyType)
            }
            resolveSelectedCountryAndState()
        }
        .onTapGesture {
            //            hideKeyboard()
            UIApplication.hideKeyboard()
        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            deleteConfirmation
        }
    }

    private func resolveSelectedCountryAndState() {
        let savedCountryCode = AppStorageManager.shared.selectedCountryCode
        selectedCountry = userViewModel.countryOptions.first { $0.code == savedCountryCode }

        let savedStateCode = AppStorageManager.shared.selectedStateCode
        selectedState = selectedCountry?.states?.first { $0.code == savedStateCode }
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
                maxLength: 10,
                usPhoneFormat: true
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

            pharmacyTypeDropdown
            countryDropdown
            stateDropdown
        }
    }

    private var landscapeProfileColums: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                leftProfileColumn
                rightProfileColumn
            }
            HStack(spacing: 12) {
                if !userViewModel.terminals.isEmpty {
                    terminalDropdown
                }
                pharmacyTypeDropdown
            }
            HStack(spacing: 12) {
                countryDropdown
                stateDropdown
            }
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
                maxLength: 10,
                usPhoneFormat: true
            )

            FloatingLabelTextField(
                placeholder: L10n.Profile.npiId,
                text: $userViewModel.npiID,
                keyboardType: .phonePad,
                maxLength: 10
            )
        }
    }

    private var pharmacyTypeDropdown: some View {
        FloatingLabelDropdown(
            placeholder: L10n.Profile.pharmacyType,
            selection: $selectedPharmacyType,
            options: userViewModel.pharmacyTypeOptions,
            labelText: { $0.label }
        )
    }

    private var countryDropdown: some View {
        FloatingLabelDropdown(
            placeholder: L10n.Profile.country,
            selection: $selectedCountry,
            options: userViewModel.countryOptions,
            labelText: { $0.name },
            onSelect: { _ in selectedState = nil }
        )
    }

    private var isStateDropdownDisabled: Bool {
        (selectedCountry?.states ?? []).isEmpty
    }

    private var stateDropdown: some View {
        FloatingLabelDropdown(
            placeholder: L10n.Profile.state,
            selection: $selectedState,
            options: selectedCountry?.states ?? [],
            labelText: { $0.name },
            disabled: isStateDropdownDisabled,
            searchable: true,
            searchPlaceholder: L10n.Profile.searchState
        )
    }

    private var terminalDropdown: some View {
        FloatingLabelDropdown(
            placeholder: L10n.Profile.terminal,
            selection: $userViewModel.pendingTerminal,
            options: userViewModel.terminals,
            labelText: { $0.terminalName ?? "" },
            disabled: isPmsDisabled,
            onSelect: { terminal in userViewModel.selectTerminal(terminal) }
        )
        // When PMS is off the dropdown is disabled (inert); overlay a tap target so
        // the tap still surfaces the "feature not available" toast instead of nothing.
        .overlay {
            if isPmsDisabled {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toastManager.show(message: L10n.Menu.featureNotAvailableMessage)
                    }
            }
        }
    }

    private var actionButtons: some View {
        EqualWidthHStackButtons(spacing: 16) {

            if AppStorageManager.shared.isNewUser {
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
            } else {
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
            }

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
        AppStorageManager.shared.isNewUser = false
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

            let profileChanged = userViewModel.hasProfileChanged(
                pharmacyTypeCode: selectedPharmacyType?.code,
                countryCode: selectedCountry?.code,
                stateCode: selectedState?.code
            )
            if profileChanged {
                await userViewModel.updateUserProfile(
                    pharmacyTypeCode: selectedPharmacyType?.code,
                    countryCode: selectedCountry?.code,
                    stateCode: selectedState?.code
                )
                if !userViewModel.isProfileUpdated {
                    toastManager.show(message: L10n.Profile.Error.errorUpdateProfileMessage)
                    return
                }
                AppStorageManager.shared.isNewUser = false
                userViewModel.isProfileUpdated = false
            }

            toastManager.show(message: L10n.Profile.successUpdateMessage)
            AppStorageManager.shared.isNewUser = false
            router.navigateBack()
        }
    }

    private func profileScreenLandscape() -> some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 20) {
                    landscapeProfileColums
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
}
