//
//  UserSettingsView.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct UserSettingsView: View {
    
    
    // All persisted settings now live in SettingsViewModel — the single
    // source of truth for this screen.
    @StateObject private var settingsViewModel = SettingsViewModel()

    // Temporary state: the save-history option the user *wants* to switch to.
    @State private var pendingOption: SaveHistoryOption? = nil

    // UI State for popups / sub-screens
    @State private var showConfirmationPopup: Bool = false
    @State private var showClearDataConfirmationPopup: Bool = false
    @State private var showResetHazardousTrayColorPopup: Bool = false
    @State private var activeSubScreen: SettingsSubScreen? = nil
    @State private var showAddFaceUser: Bool = false
    @State private var showQuickAccess: Bool = false
    @State private var showRegisteredFaces: Bool = false
    @State private var showTimeLimitPicker: Bool = false

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    
    
    private var isPmsIntegrated: Bool { AppStorageManager.shared.isPmsIntegrated }
    /// PMS-gated rows are disabled when PMS integration is off for this account.
    private var isPmsDisabled: Bool { !isPmsIntegrated }

    /// Surface the "feature not available" toast when a PMS-gated row is tapped.
    private func showFeatureUnavailableToast() {
        ToastManager.shared.show(message: L10n.Menu.featureNotAvailableMessage)
    }


    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BaseView(
                    topRatio: 1.0,
                    topContent: {
                        userSettingsContent(geometry: geometry)
                    },
                    bottomContent: {
                        EmptyView()
                    },
                    headerActions: { EmptyView() },
                    showBackButton: true,
                    showHamburgerMenu: false,
                    title: L10n.Menu.settings
                )
            }
        }
        .overlay {
            if let screen = activeSubScreen {
                subScreenView(screen)
                    .transition(.move(edge: .trailing))
                    .zIndex(1000)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeSubScreen)
        .customPopup(isPresented: $showConfirmationPopup) {
            confirmationPopUp
        }
        .customPopup(isPresented: $showClearDataConfirmationPopup) {
            clearHistoryConfirmatioDialog
        }
        .customPopup(isPresented: $showResetHazardousTrayColorPopup) {
            resetHazardousTrayColorDialog
        }
        .sheet(isPresented: $showAddFaceUser) {
            FaceEnrollmentView()
                .environmentObject(appColors)
        }
        .sheet(isPresented: $showQuickAccess) {
            FaceAuthenticationView()
                .environmentObject(appColors)
        }
        .sheet(isPresented: $showRegisteredFaces) {
            NavigationStack {
                FaceRegisteredUsersView()
                    .environmentObject(appColors)
            }
        }
        .sheet(isPresented: $showTimeLimitPicker) {
            FaceSessionTimeoutPickerView(settingsViewModel: settingsViewModel)
                .environmentObject(appColors)
        }
        .onAppear {
            // PMS off → the gated features are unavailable; reset them to their
            // defaults (off / empty) so a stale "on" value can't take effect.
            if isPmsDisabled {
                settingsViewModel.resetPmsGatedSettings()
            }
        }
    }

    private var resetHazardousTrayColorDialog: some View {
        ConfirmationDialogue(
            title: L10n.Settings.resetHazardousTrayColorTitle,
            message: L10n.Settings.resetHazardousTrayColorMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes
        ) {
            showResetHazardousTrayColorPopup = false
        } onConfirm: {
            settingsViewModel.resetHazardousTrayColor()
            showResetHazardousTrayColorPopup = false
        }
    }

    private var confirmationPopUp: some View {
        ConfirmationDialogue(
            title: String(format: L10n.Settings.confirmHistoryTitle, pendingOption?.displayText ?? settingsViewModel.saveHistoryOption.displayText),
            message: L10n.Settings.confirmHistoryMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes
        ) {
            pendingOption = nil
            showConfirmationPopup = false
        } onConfirm: {
            // Confirm Action: Commit the change
            if let newOption = pendingOption {
                settingsViewModel.commitSaveHistoryOption(newOption)
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                activeSubScreen = nil
            }
            showConfirmationPopup = false
        }
    }
    
    private var clearHistoryConfirmatioDialog: some View {
        ConfirmationDialogue(
            title: L10n.Settings.clearHistoryTitle,
            message: L10n.Settings.clearHistoryMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes
        ) {
            showClearDataConfirmationPopup = false
        } onConfirm: {
            showClearDataConfirmationPopup = false
            settingsViewModel.clearLocalData()
        }
    }
    
    private func userSettingsContent(geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        
        
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                
                // MARK: Pill Counting
                ToggleRowView(
                    title: L10n.Settings.alwaysAskNotes,
                    isOn: $settingsViewModel.isPillCountingEnabled,
                    onColor: appColors.primary,
                    onToggle: { newValue in
                        settingsViewModel.setPillCountingEnabled(newValue)
                    }
                )
                
                Divider().background(appColors.primaryBackground)
                
                VStack (spacing: 15){
                    Text(L10n.Settings.requireDoubleCount)
                        .foregroundStyle(appColors.text)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 4) {
                        ForEach(Array(DrugSchedule.allCases.enumerated()), id: \.element.id) { index, schedule in
                            Text(schedule.rawValue)
                                .foregroundColor(
                                    settingsViewModel.isScheduleSelected(schedule)
                                    ? appColors.secondary
                                    : appColors.text.opacity(0.35)
                                )
                                .fontWeight(.regular)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
                .opacity(isPmsDisabled ? 0.6 : 1.0)
                .onTapGesture {
                    if isPmsDisabled {
                        showFeatureUnavailableToast()
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeSubScreen = .schedule
                    }
                }
                
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Back Count
                ToggleRowView(
                    title: L10n.Settings.requireBackCount,
                    isOn: $settingsViewModel.isBackCountRequired,
                    onColor: appColors.primary,
                    isDisabled: isPmsDisabled,
                    onDisabledTap: { showFeatureUnavailableToast() },
                    onToggle: { newValue in
                        settingsViewModel.setBackCountRequired(newValue)
                    }
                )
                
                Divider().background(appColors.primaryBackground)
                
                
                
                // MARK: Save History Title
                VStack (spacing: 15){
                    Text(L10n.Settings.saveHistory)
                        .foregroundStyle(appColors.text)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    
                    Text(settingsViewModel.saveHistoryOption.displayText)
                        .foregroundColor(appColors.secondary)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeSubScreen = .saveHistory
                    }
                }
                
                
                Divider().background(appColors.primaryBackground)

                // MARK: Face Recognition
                HStack {
                    Text(L10n.Settings.faceRecognition)
                        .foregroundStyle(appColors.text)
                        .fontWeight(.regular)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeSubScreen = .faceRecognition
                    }
                }

                Divider().background(appColors.primaryBackground)

                // MARK: Sound
                ToggleRowView(
                    title: L10n.Settings.soundFeedback,
                    isOn: $settingsViewModel.isSoundEnabled,
                    onColor: appColors.primary,
                    onToggle: { newValue in
                        settingsViewModel.setSoundEnabled(newValue)
                    }
                )
                
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Haptic
                ToggleRowView(
                    title: L10n.Settings.hapticFeedback,
                    isOn: $settingsViewModel.isHapticEnabled,
                    onColor: appColors.primary,
                    onToggle: { newValue in
                        settingsViewModel.setHapticEnabled(newValue)
                    }
                )
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Speech Instruction
                ToggleRowView(
                    title: L10n.Settings.voiceInstructions,
                    isOn: $settingsViewModel.isSpeechEnabled,
                    onColor: appColors.primary,
                    onToggle: { newValue in
                        settingsViewModel.setSpeechEnabled(newValue)
                    }
                )
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: HAZARDOUS DRUG
                ToggleRowView(
                    title: L10n.Settings.hazardousPillSetting,
                    isOn: $settingsViewModel.isHazardousDrugSettingEnabled,
                    onColor: appColors.primary,
                    isDisabled: isPmsDisabled,
                    onDisabledTap: { showFeatureUnavailableToast() },
                    onToggle: { newValue in
                        settingsViewModel.setHazardousDrugSetting(newValue)
                    }
                )

                Divider().background(appColors.primaryBackground)

                // MARK: Hazardous Tray Color
                VStack(spacing: 15) {
                    Text(L10n.Settings.hazardousTrayColor)
                        .foregroundStyle(appColors.text)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(settingsViewModel.hazardousTrayColor ?? "—")
                        .foregroundColor(appColors.secondary)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
                .opacity(isPmsDisabled ? 0.6 : 1.0)
                .onTapGesture {
                    if isPmsDisabled {
                        showFeatureUnavailableToast()
                        return
                    }
                    // Only offer to reset when a hazardous tray color is set.
                    if settingsViewModel.hazardousTrayColor != nil {
                        showResetHazardousTrayColorPopup = true
                    }
                }

                Divider().background(appColors.primaryBackground)

                HStack{
                    Text(L10n.Settings.clearLocalData)
                        .foregroundStyle(appColors.text)
                        .padding(.horizontal)
                        .fontWeight(Font.Weight.regular)
                    
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    showClearDataConfirmationPopup = true
                }
                
                Divider().background(appColors.primaryBackground)
                
                Spacer(minLength: 40)
                
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal,10)
        .background(appColors.secondaryBackground)
    }
    
    @ViewBuilder
    private func subScreenView(_ screen: SettingsSubScreen) -> some View {
        BaseView(
            topRatio: 1.0,
            topContent: {
                switch screen {
                case .saveHistory:
                    saveHistoryContent
                case .schedule:
                    scheduleContent
                case .faceRecognition:
                    faceRecognitionContent
                }
            },
            bottomContent: { EmptyView() },
            headerActions: { EmptyView() },
            showBackButton: true,
            showHamburgerMenu: false,
            title: screenTitle(screen),
            backgroundColor: appColors.primaryBackground,
            onBack: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeSubScreen = nil
                }
            }
        )
    }
    
    private func screenTitle(_ screen: SettingsSubScreen) -> String {
        switch screen {
        case .saveHistory: return L10n.Settings.saveHistoryScreenTitle
        case .schedule: return L10n.Settings.scheduleScreenTitle
        case .faceRecognition: return L10n.Settings.faceRecognitionScreenTitle
        }
    }
    
    private var saveHistoryContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            VStack(alignment: .leading, spacing: 45) {
                ForEach(SaveHistoryOption.allCases) { option in
                    Button {
                        pendingOption = option
                        showConfirmationPopup = true
                    } label: {
                        HStack (spacing:8){
                            Circle()
                                .stroke(
                                    option == settingsViewModel.saveHistoryOption
                                    ? appColors.primary
                                    : appColors.text,
                                    lineWidth: 2
                                )
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if option == settingsViewModel.saveHistoryOption {
                                        Circle()
                                            .fill(appColors.primary)
                                            .frame(width: 10, height: 10)
                                    }
                                }
                            
                            Text(option.displayText)
                                .foregroundColor(appColors.text)
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(.leading, 30)
            
            Spacer()
        }
        .padding(.top, SafeAreaInsets.top + 60)
        .background(appColors.primaryBackground)
    }
    
    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            
            VStack(alignment: .leading, spacing: 45) {
                ForEach(DrugSchedule.allCases) { schedule in
                    
                    Button {
                        settingsViewModel.toggleSchedule(schedule)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    settingsViewModel.isScheduleSelected(schedule)
                                    ? appColors.primary
                                    : appColors.text.opacity(0.6),
                                    lineWidth: 2
                                )
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(
                                            settingsViewModel.isScheduleSelected(schedule)
                                            ? appColors.primary
                                            : Color.clear
                                        )
                                )
                                .overlay {
                                    if settingsViewModel.isScheduleSelected(schedule) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            
                            Text(schedule.rawValue)
                                .foregroundColor(appColors.text)
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(.leading, 30)
            
            Spacer()
        }
        .padding(.top, SafeAreaInsets.top + 60)
        .background(appColors.primaryBackground)
    }

    private var faceRecognitionContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            VStack(alignment: .leading, spacing: 45) {
                faceRecognitionRow(title: L10n.Settings.lockNow)
                faceRecognitionRow(title: L10n.Settings.addUser) {
                    showAddFaceUser = true
                }
                faceRecognitionRow(title: L10n.Settings.quickAccess) {
                    showQuickAccess = true
                }
                faceRecognitionRow(
                    title: L10n.Settings.timeLimit,
                    value: settingsViewModel.faceSessionTimeoutOption.displayText
                ) {
                    showTimeLimitPicker = true
                }
                faceRecognitionRow(title: L10n.FaceAuth.registeredUsersTitle) {
                    showRegisteredFaces = true
                }
            }
            .padding(.leading, 30)

            Spacer()
        }
        .padding(.top, SafeAreaInsets.top + 60)
        .background(appColors.primaryBackground)
    }

    private func faceRecognitionRow(title: String, value: String? = nil, onTap: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundColor(appColors.text)
            Spacer()
            if let value {
                Text(value)
                    .foregroundColor(appColors.text.opacity(0.6))
                    .padding(.trailing, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}


private func alignmentFor(_ index: Int) -> Alignment {
    switch index {
    case 0: return .leading
    case 1: return .center
    case 2: return .trailing
    default: return .leading
    }
}

struct ToggleRowView: View {

    let title: String
    @Binding var isOn: Bool

    var onColor: Color = .pink
    var horizontalPadding: CGFloat = 16
    /// When true the row is grayed out, the toggle is inert, and a tap anywhere
    /// on the row routes to `onDisabledTap` instead of flipping the toggle.
    var isDisabled: Bool = false
    var onDisabledTap: (() -> Void)? = nil
    var onToggle: ((Bool) -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(Font.Weight.regular)
                .foregroundColor(AppColors.shared.text)
            Spacer()
            PillCountingToggleButton(
                isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        guard !isDisabled else { return }
                        isOn = newValue
                        onToggle?(newValue)
                    }
                ),
                onColor: onColor
            )
            .scaleEffect(0.8)
            // Block the toggle's own hit-testing when disabled so the row-level
            // tap below is what fires (showing the "not available" popup).
            .allowsHitTesting(!isDisabled)
        }
        .padding(.horizontal, horizontalPadding)
        .opacity(isDisabled ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDisabled { onDisabledTap?() }
        }
    }
}


