//
//  SaveHistoryOptionPickerView.swift
//  PillCounter
//
//  Save-history duration picker, reached from Settings > General > Save
//  History. Native sheet replacing the former full-screen SettingsSubScreen
//  overlay, styled the same as FaceSessionTimeoutPickerView. Selecting an
//  option still asks for confirmation before committing — unlike the
//  auto-lock timeout picker — since changing this can affect what history
//  gets kept.
//

import SwiftUI

struct SaveHistoryOptionPickerView: View {

    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.dismiss) private var dismiss

    @State private var pendingOption: SaveHistoryOption? = nil
    @State private var showConfirmationPopup: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 45) {
                ForEach(SaveHistoryOption.allCases) { option in
                    Button {
                        pendingOption = option
                        showConfirmationPopup = true
                    } label: {
                        HStack(spacing: 8) {
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
            .padding(.top, 30)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(appColors.primaryBackground)
            .navigationTitle(L10n.Settings.saveHistoryScreenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .customPopup(isPresented: $showConfirmationPopup) {
                confirmationPopUp
            }
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
            if let newOption = pendingOption {
                settingsViewModel.commitSaveHistoryOption(newOption)
            }
            showConfirmationPopup = false
            dismiss()
        }
    }
}
