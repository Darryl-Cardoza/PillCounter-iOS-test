//
//  DrugSchedulePickerView.swift
//  PillCounter
//
//  Controlled-drug schedule multi-select, reached from Settings > Dispense
//  Controlled Drug > Require Double Count for CS. Native sheet replacing the
//  former full-screen SettingsSubScreen overlay. Each tap toggles live;
//  dismissed via the native swipe-down gesture.
//

import SwiftUI

struct DrugSchedulePickerView: View {

    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        NavigationStack {
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
            .padding(.top, 30)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(appColors.primaryBackground)
            .navigationTitle(L10n.Settings.scheduleScreenTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
