//
//  FaceSessionTimeoutPickerView.swift
//  PillCounter
//
//  Session-lock idle-timeout picker, reached from Settings > Face Recognition
//  > Time Limit. Radio-list styled the same as UserSettingsView's
//  saveHistoryContent (this app's only existing "pick one of a fixed set of
//  durations" convention) — presented as its own sheet rather than another
//  case of SettingsSubScreen since the Face Recognition rows are otherwise
//  all flat sheets (Add User / Quick Access / Registered Faces).
//

import SwiftUI

struct FaceSessionTimeoutPickerView: View {

    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var appColors: AppColors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 45) {
                ForEach(FaceSessionTimeoutOption.allCases) { option in
                    Button {
                        settingsViewModel.commitFaceSessionTimeoutOption(option)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .stroke(
                                    option == settingsViewModel.faceSessionTimeoutOption
                                    ? appColors.primary
                                    : appColors.text,
                                    lineWidth: 2
                                )
                                .frame(width: 20, height: 20)
                                .overlay {
                                    if option == settingsViewModel.faceSessionTimeoutOption {
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
            .navigationTitle(L10n.Settings.timeLimitScreenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.cancel) { dismiss() }
                        .foregroundColor(appColors.primary)
                }
            }
        }
    }
}
