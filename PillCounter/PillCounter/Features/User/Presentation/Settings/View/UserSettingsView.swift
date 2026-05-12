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
    
    
    // 1. Source of Truth (The actual saved setting)
    @State private var selectedSaveHistoryOption: SaveHistoryOption =
    AppStorageManager.shared.saveHistoryOption
    
    // 2. Temporary State (The option the user *wants* to switch to)
    @State private var pendingOption: SaveHistoryOption? = nil
    
    // 3. UI State for Popup
    @State private var showConfirmationPopup: Bool = false
    @State private var showClearDataConfirmationPopup: Bool = false
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
                    title: NSLocalizedString("SETTINGS", comment: "")
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
    }
    
    private var confirmationPopUp: some View {
        ConfirmationDialogue(
            title: "Are you sure want to keep history for \(pendingOption?.displayText ?? selectedSaveHistoryOption.displayText)",
            message:
                "Note: Data older than this period will be permanently deleted.",
            cancelButtonText: "NO",
            confirmButtonText: "YES"
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
            title: "Are you sure want to clear all history?",
            message: "This will delete all your saved data permanently.",
            cancelButtonText: "NO",
            confirmButtonText: "YES"
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
            VStack(alignment: .leading, spacing: 30) {
                
                // MARK: Pill Counting
                ToggleRowView(
                    title: NSLocalizedString("TOGGLE_BUTTON_TEXT", comment: ""),
                    isOn: $isPillCountingEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isPillCountingEnabled = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                VStack (spacing: 15){
                    Text(NSLocalizedString("REQUIRED_DOUBLE_COUNT", comment: ""))
                        .foregroundStyle(appColors.text)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !selectedSchedules.isEmpty{
                        Text(
                            selectedSchedules
                                .map { $0.rawValue }
                                .sorted()
                                .joined(separator: ", ")
                        )
                        .foregroundColor(appColors.secondary)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
                    title: NSLocalizedString("REQUIRED_BACK_COUNT", comment: ""),
                    isOn: $isBackCountRequired,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isBackCountRequired = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                
                
                // MARK: Save History Title
                VStack (spacing: 15){
                    Text(NSLocalizedString("SAVE_HISTORY", comment: ""))
                        .foregroundStyle(appColors.text)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    
                    Text(selectedSaveHistoryOption.displayText)
                        .foregroundColor(appColors.secondary)
                        .fontWeight(.semibold)
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
                    title: NSLocalizedString("SOUND_FEEDBACK", comment: ""),
                    isOn: $isSoundEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isSoundEnabled = newValue
                }
                
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Haptic
                ToggleRowView(
                    title: NSLocalizedString("HAPTIC_FEEDBACK", comment: ""),
                    isOn: $isHapticEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isHapticEnabled = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                // MARK: Speech Instruction
                ToggleRowView(
                    title: NSLocalizedString("VOICE_INSTRUCTIONS", comment: ""),
                    isOn: $isSpeechEnabled,
                    onColor: appColors.primary
                ) { newValue in
                    AppStorageManager.shared.isSpeechEnabled = newValue
                }
                
                Divider().background(appColors.primaryBackground)
                
                HStack{
                    Text(NSLocalizedString("CLEAR_ALL_LOCAL_DATA", comment: ""))
                        .foregroundStyle(appColors.text)
                        .padding(.horizontal)
                        .fontWeight(Font.Weight.semibold)
                    
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
        .padding(
            .top,
            isLandscape ? SafeAreaInsets.top + 80 : SafeAreaInsets.top + 50
        )
        .padding(.horizontal, isLandscape ? SafeAreaInsets.leading : 10)
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
            onBack: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    activeSubScreen = nil
                }
            }
        )
    }
    
    private func screenTitle(_ screen: SettingsSubScreen) -> String {
        switch screen {
        case .saveHistory: return "SAVE HISTORY FOR"
        case .schedule: return "SELECT SCHEDULE"
        }
    }
    
    private var saveHistoryContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            VStack(alignment: .leading, spacing: 30) {
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

            VStack(alignment: .leading, spacing: 30) {
                ForEach(DrugSchedule.allCases) { schedule in

                    Button {
                        // toggle selection
                        if selectedSchedules.contains(schedule) {
                            selectedSchedules.remove(schedule)
                        } else {
                            selectedSchedules.insert(schedule)
                        }

                        AppStorageManager.shared.selectedSchedules = selectedSchedules

                        activeSubScreen = nil

                    } label: {
                        HStack(spacing: 8) {

                            Circle()
                                .stroke(
                                    selectedSchedules.contains(schedule)
                                    ? appColors.primary
                                    : appColors.text,
                                    lineWidth: 2
                                )
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if selectedSchedules.contains(schedule) {
                                        Circle()
                                            .fill(appColors.primary)
                                            .frame(width: 10, height: 10)
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
    }}


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
                .fontWeight(Font.Weight.semibold)
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


