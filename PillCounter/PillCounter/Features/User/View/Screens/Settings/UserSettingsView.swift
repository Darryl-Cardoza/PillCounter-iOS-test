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

    @State private var isDoubleCountRequired =
        AppStorageManager.shared.isDoubleCountRequired

    @State private var isBackCountRequired =
        AppStorageManager.shared.isBackCountRequired

    @State private var isAdjustReasonRequired =
        AppStorageManager.shared.isAdjustReasonRequired

    @State private var isHapticEnabled =
        AppStorageManager.shared.isHapticEnabled

    @State private var isSoundEnabled =
        AppStorageManager.shared.isSoundEnabled
    
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

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userviewmodel: UserViewModel

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
            // Cancel Action: Reset pending and hide popup
            pendingOption = nil
            showConfirmationPopup = false
        } onConfirm: {
            // Confirm Action: Commit the change
            if let newOption = pendingOption {
                selectedSaveHistoryOption = newOption
                AppStorageManager.shared.saveHistoryOption =
                    newOption
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
        
        // 5. Custom Binding to Intercept Taps
        // This acts as a proxy. When the radio button tries to set the value,
        // we stop it, check if it's different, and show the popup instead.
        let radioBinding = Binding<SaveHistoryOption>(
            get: { self.selectedSaveHistoryOption },
            set: { newValue in
                if newValue != self.selectedSaveHistoryOption {
                    self.pendingOption = newValue
                    self.showConfirmationPopup = true
                }
            }
        )
        
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {

                // MARK: Pill Counting
                ToggleRowView(
                    title: NSLocalizedString("TOGGLE_BUTTON_TEXT", comment: ""),
                    isOn: $isPillCountingEnabled,
                    onColor: Color(hex: "#FF699B")
                ) { newValue in
                    AppStorageManager.shared.isPillCountingEnabled = newValue
                }

                Divider().background(appColors.text)

                VStack{
                    // MARK: Double Count
                    ToggleRowView(
                        title: NSLocalizedString("REQUIRED_DOUBLE_COUNT", comment: ""),
                        isOn: $isDoubleCountRequired,
                        onColor: Color(hex: "#FF699B")
                    ) { newValue in
                        AppStorageManager.shared.isDoubleCountRequired = newValue
                    }
                    
                    
                    if isDoubleCountRequired {
                        VStack(alignment: .leading, spacing: 30) {
                            // MARK: Schedule Title
                            Spacer()

                            Text("Select Schedule Codes")
                                .foregroundStyle(appColors.text)
                                .font(.subheadline)
                                .padding(.horizontal)
                            
                            // MARK: Drug Schedule Row
                            VStack(spacing: 30) {

                                let schedules = DrugSchedule.allCases
                                let rows = stride(from: 0, to: schedules.count, by: 3).map {
                                    Array(schedules[$0..<min($0 + 3, schedules.count)])
                                }

                                ForEach(rows.indices, id: \.self) { rowIndex in
                                    HStack {
                                        ForEach(0..<3) { columnIndex in
                                            if columnIndex < rows[rowIndex].count {
                                                let schedule = rows[rowIndex][columnIndex]

                                                HStack {
                                                    PillCounterCheckbox(
                                                        isChecked: Binding(
                                                            get: {
                                                                selectedSchedules.contains(schedule)
                                                            },
                                                            set: { newValue in
                                                                if newValue {
                                                                    selectedSchedules.insert(schedule)
                                                                } else {
                                                                    selectedSchedules.remove(schedule)
                                                                }
                                                                AppStorageManager.shared.selectedSchedules = selectedSchedules
                                                            }
                                                        ),
                                                        size: 18,
                                                        tintColor: appColors.text,
                                                        selectedCheckmarkColor: appColors.secondary
                                                    )
                                                    .padding(.trailing, 5)

                                                    Text(schedule.rawValue)
                                                        .foregroundStyle(appColors.text)
                                                        .frame(width: 50, alignment: .leading)
                                                }
                                                .frame(maxWidth: .infinity, alignment: alignmentFor(columnIndex))
                                            } else {
                                                Spacer()
                                                    .frame(maxWidth: .infinity)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .transition(
                            .move(edge: .top)
                            .combined(with: .opacity)
                        )
                    }

                }

                Divider().background(appColors.text)

                // MARK: Back Count
                ToggleRowView(
                    title: NSLocalizedString("REQUIRED_BACK_COUNT", comment: ""),
                    isOn: $isBackCountRequired,
                    onColor: Color(hex: "#FF699B")
                ) { newValue in
                    AppStorageManager.shared.isBackCountRequired = newValue
                }

                Divider().background(appColors.text)

                // MARK: Adjust Reason
                ToggleRowView(
                    title: NSLocalizedString("REQUIRED_ADJUST_REASON", comment: ""),
                    isOn: $isAdjustReasonRequired,
                    onColor: Color(hex: "#FF699B")
                ) { newValue in
                    AppStorageManager.shared.isAdjustReasonRequired = newValue
                }

                Divider().background(appColors.text)

                // MARK: Save History Title
                Text(NSLocalizedString("SAVE_HISTORY", comment: ""))
                    .foregroundStyle(appColors.text)
                    .padding(.horizontal)

                if isLandscape {
                    HStack(spacing: 20) {
                        ForEach(SaveHistoryOption.allCases) { option in
                            PillCountingRadioButton(
                                option: option,
                                selectedOption: radioBinding,
                                label: option.displayText,
                                selectedColor: Color(hex: "#FF699B"),
                                unselectedColor: .gray.opacity(0.5),
                                size: 20,
                                lineWidth: 2,
                                textColor: appColors.text
                            )
                        }
                    }
                    .padding(.horizontal)
                } else {
                    VStack(alignment: .leading, spacing: 45) {
                        ForEach(SaveHistoryOption.allCases) { option in
                            PillCountingRadioButton(
                                option: option,
                                selectedOption: radioBinding,
                                label: option.displayText,
                                selectedColor: Color(hex: "#FF699B"),
                                unselectedColor: .gray.opacity(0.5),
                                size: 20,
                                lineWidth: 2,
                                textColor: appColors.text
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.leading, 5)
                }

                Divider().background(appColors.text)

                // MARK: Sound
                ToggleRowView(
                    title: NSLocalizedString("SOUND_FEEDBACK", comment: ""),
                    isOn: $isSoundEnabled,
                    onColor: Color(hex: "#FF699B")
                ) { newValue in
                    AppStorageManager.shared.isSoundEnabled = newValue
                }


                Divider().background(appColors.text)

                // MARK: Haptic
                ToggleRowView(
                    title: NSLocalizedString("HAPTIC_FEEDBACK", comment: ""),
                    isOn: $isHapticEnabled,
                    onColor: Color(hex: "#FF699B")
                ) { newValue in
                    AppStorageManager.shared.isHapticEnabled = newValue
                }
                
                Divider().background(appColors.text)
                
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
                
                Divider().background(appColors.text)
                
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
}

#Preview {
    UserSettingsView()
        .preferredColorScheme(.dark)
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


enum DrugSchedule: String, CaseIterable, Identifiable {
    case cii = "CII"
    case ciii = "CIII"
    case civ = "CIV"
    case cv = "CV"
    case cvi = "CVI"

    var id: String { rawValue }
}
