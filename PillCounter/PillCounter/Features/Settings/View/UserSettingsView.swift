//
//  UserSettingsView.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct UserSettingsView: View {
    
    
    @State private var isPillCountingEnabled =
    AppStorageManager.shared.isPillCountingEnabled
    
    @State private var isBackCountRequired =
    AppStorageManager.shared.isBackCountRequired
    
    @State private var isHapticEnabled =
    AppStorageManager.shared.isHapticEnabled
    
    @State private var isSoundEnabled =
    AppStorageManager.shared.isSoundEnabled
    
    @State private var isSpeechEnabled =
    AppStorageManager.shared.isSpeechEnabled
    
    @State private var selectedSchedules =
    AppStorageManager.shared.selectedSchedules
    
    @State private var isHazardousDrugSettingEnabled =
    AppStorageManager.shared.isHazardousDrugSetting

    @State private var hazardousTrayColor =
    AppStorageManager.shared.hazardousTrayColor

    
    // 1. Source of Truth (The actual saved setting)
    @State private var selectedSaveHistoryOption: SaveHistoryOption =
    AppStorageManager.shared.saveHistoryOption
    
    // 2. Temporary State (The option the user *wants* to switch to)
    @State private var pendingOption: SaveHistoryOption? = nil
    
    // 3. UI State for Popup
    @State private var showConfirmationPopup: Bool = false
    @State private var showClearDataConfirmationPopup: Bool = false
    @State private var showResetHazardousTrayColorPopup: Bool = false
    @State private var activeSubScreen: SettingsSubScreen? = nil
    
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userviewmodel: UserViewModel
    @EnvironmentObject private var router: Router
    
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
            AppStorageManager.shared.hazardousTrayColor = nil
            hazardousTrayColor = nil
            showResetHazardousTrayColorPopup = false
        }
    }
    
    private var confirmationPopUp: some View {
        ConfirmationDialogue(
            title: String(format: L10n.Settings.confirmHistoryTitle, pendingOption?.displayText ?? selectedSaveHistoryOption.displayText),
            message: L10n.Settings.confirmHistoryMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes
        ) {
            pendingOption = nil
            showConfirmationPopup = false
        } onConfirm: {
            // Confirm Action: Commit the change
            if let newOption = pendingOption {
                selectedSaveHistoryOption = newOption
                AppStorageManager.shared.saveHistoryOption =
                newOption
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
            userviewmodel.clearLocalData()
        }
    }
    
    private func userSettingsContent(geometry: GeometryProxy) -> some View {
        let isLandscape = geometry.size.width > geometry.size.height
        
        
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                
                // MARK: Pill Counting
                ToggleRowView(
                    title: L10n.Settings.alwaysAskNotes,
                    isOn: $isPillCountingEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isPillCountingEnabled = newValue
                }
                
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
                                    selectedSchedules.contains(schedule)
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
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeSubScreen = .schedule
                    }
                }
                
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Back Count
                ToggleRowView(
                    title: L10n.Settings.requireBackCount,
                    isOn: $isBackCountRequired,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isBackCountRequired = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                
                
                // MARK: Save History Title
                VStack (spacing: 15){
                    Text(L10n.Settings.saveHistory)
                        .foregroundStyle(appColors.text)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    
                    Text(selectedSaveHistoryOption.displayText)
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
                
                // MARK: Sound
                ToggleRowView(
                    title: L10n.Settings.soundFeedback,
                    isOn: $isSoundEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isSoundEnabled = newValue
                }
                
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Haptic
                ToggleRowView(
                    title: L10n.Settings.hapticFeedback,
                    isOn: $isHapticEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isHapticEnabled = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Speech Instruction
                ToggleRowView(
                    title: L10n.Settings.voiceInstructions,
                    isOn: $isSpeechEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isSpeechEnabled = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: HAZARDOUS DRUG
                ToggleRowView(
                    title: L10n.Settings.hazardousPillSetting,
                    isOn: $isHazardousDrugSettingEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isHazardousDrugSetting = newValue
                }

                Divider().background(appColors.primaryBackground)

                // MARK: Hazardous Tray Color
                VStack(spacing: 15) {
                    Text(L10n.Settings.hazardousTrayColor)
                        .foregroundStyle(appColors.text)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(hazardousTrayColor ?? "—")
                        .foregroundColor(appColors.secondary)
                        .fontWeight(.regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Only offer to reset when a hazardous tray color is set.
                    if hazardousTrayColor != nil {
                        showResetHazardousTrayColorPopup = true
                    }
                    // TODO: No hazardous tray color set yet — nothing to reset.
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
                                    option == selectedSaveHistoryOption
                                    ? appColors.primary
                                    : appColors.text,
                                    lineWidth: 2
                                )
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if option == selectedSaveHistoryOption {
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
                        // toggle selection
                        if selectedSchedules.contains(schedule) {
                            selectedSchedules.remove(schedule)
                        } else {
                            selectedSchedules.insert(schedule)
                        }
                        
                        AppStorageManager.shared.selectedSchedules = selectedSchedules
                        
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    selectedSchedules.contains(schedule)
                                    ? appColors.primary
                                    : appColors.text.opacity(0.6),
                                    lineWidth: 2
                                )
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(
                                            selectedSchedules.contains(schedule)
                                            ? appColors.primary
                                            : Color.clear
                                        )
                                )
                                .overlay {
                                    if selectedSchedules.contains(schedule) {
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
                        isOn = newValue
                        onToggle?(newValue)
                    }
                ),
                onColor: onColor
            )
            .scaleEffect(0.8)
        }
        .padding(.horizontal, horizontalPadding)
    }
}


