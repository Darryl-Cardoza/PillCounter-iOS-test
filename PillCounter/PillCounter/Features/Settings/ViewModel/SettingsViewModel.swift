//
//  SettingsViewModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//
//  Single source of truth for the Settings screen. Previously the settings
//  toggles were scattered across `UserSettingsView` as ~10 `@State` values
//  each reading/writing `AppStorageManager.shared` directly, the "clear local
//  data" action lived on `UserViewModel`, and the Save-History display + the
//  unsynced count in `HamburgerMenuView` came from yet more sources. This view
//  model owns all of it so both settings views bind to one object.
//

import Foundation
import Combine

// MARK: - Settings storage seam
//
// Narrow protocol over the settings-related members of `AppStorageManager`,
// so the view model can be unit-tested against an in-memory fake.

protocol SettingsStore: AnyObject {
    var isPillCountingEnabled: Bool { get set }
    var isBackCountRequired: Bool { get set }
    var isHapticEnabled: Bool { get set }
    var isSoundEnabled: Bool { get set }
    var isSpeechEnabled: Bool { get set }
    var selectedSchedules: Set<DrugSchedule> { get set }
    var isHazardousDrugSetting: Bool { get set }
    var hazardousTrayColor: String? { get set }
    var saveHistoryOption: SaveHistoryOption { get set }
    var faceSessionTimeoutOption: FaceSessionTimeoutOption { get set }
}

extension AppStorageManager: SettingsStore {}

// MARK: - Local-data cleaner seam

protocol LocalDataClearing: AnyObject {
    func clearAll()
}

extension LocalDataCleaner: LocalDataClearing {}

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published settings (UI binds to these)
    @Published var isPillCountingEnabled: Bool
    @Published var isBackCountRequired: Bool
    @Published var isHapticEnabled: Bool
    @Published var isSoundEnabled: Bool
    @Published var isSpeechEnabled: Bool
    @Published var isHazardousDrugSettingEnabled: Bool
    @Published var selectedSchedules: Set<DrugSchedule>
    @Published var hazardousTrayColor: String?
    @Published var saveHistoryOption: SaveHistoryOption
    @Published var faceSessionTimeoutOption: FaceSessionTimeoutOption

    // MARK: - Menu-facing state (formerly in HamburgerMenuView)
    @Published var unsyncedCount: Int = 0

    /// Display string for the current save-history option (used by the menu row).
    var saveHistoryDisplayText: String { saveHistoryOption.displayText }

    // MARK: - Injected dependencies
    private let store: SettingsStore
    private let dataCleaner: LocalDataClearing
    private let batchStore: BatchDataSource
    private let transactionStore: TransactionDataSource
    private var cancellables = Set<AnyCancellable>()

    /// Dependencies default to the production singletons, so views can create
    /// `SettingsViewModel()` unchanged. Tests pass mocks.
    init(
        store: SettingsStore = AppStorageManager.shared,
        dataCleaner: LocalDataClearing = LocalDataCleaner.shared,
        batchStore: BatchDataSource = BatchStore.shared,
        transactionStore: TransactionDataSource = TransactionStore.shared
    ) {
        self.store = store
        self.dataCleaner = dataCleaner
        self.batchStore = batchStore
        self.transactionStore = transactionStore

        // Seed published state from persisted values.
        self.isPillCountingEnabled        = store.isPillCountingEnabled
        self.isBackCountRequired          = store.isBackCountRequired
        self.isHapticEnabled              = store.isHapticEnabled
        self.isSoundEnabled               = store.isSoundEnabled
        self.isSpeechEnabled              = store.isSpeechEnabled
        self.isHazardousDrugSettingEnabled = store.isHazardousDrugSetting
        self.selectedSchedules            = store.selectedSchedules
        self.hazardousTrayColor           = store.hazardousTrayColor
        self.saveHistoryOption            = store.saveHistoryOption
        self.faceSessionTimeoutOption     = store.faceSessionTimeoutOption

        // Keep the unsynced count live for the menu badge. Debounced so a
        // burst of writes (bulk generation, sync catching up) triggers one
        // refresh instead of one per write.
        batchStore.transactionsDidChange
            .merge(with: transactionStore.transactionsDidChange)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refreshUnsyncedCount() }
            .store(in: &cancellables)

        refreshUnsyncedCount()
    }

    // MARK: - Toggle setters (persist on change)

    func setPillCountingEnabled(_ value: Bool) {
        isPillCountingEnabled = value
        store.isPillCountingEnabled = value
    }

    func setBackCountRequired(_ value: Bool) {
        isBackCountRequired = value
        store.isBackCountRequired = value
    }

    func setSoundEnabled(_ value: Bool) {
        isSoundEnabled = value
        store.isSoundEnabled = value
    }

    func setHapticEnabled(_ value: Bool) {
        isHapticEnabled = value
        store.isHapticEnabled = value
    }

    func setSpeechEnabled(_ value: Bool) {
        isSpeechEnabled = value
        store.isSpeechEnabled = value
    }

    func setHazardousDrugSetting(_ value: Bool) {
        isHazardousDrugSettingEnabled = value
        store.isHazardousDrugSetting = value
    }

    // MARK: - Schedules

    func toggleSchedule(_ schedule: DrugSchedule) {
        if selectedSchedules.contains(schedule) {
            selectedSchedules.remove(schedule)
        } else {
            selectedSchedules.insert(schedule)
        }
        store.selectedSchedules = selectedSchedules
    }

    func isScheduleSelected(_ schedule: DrugSchedule) -> Bool {
        selectedSchedules.contains(schedule)
    }

    // MARK: - Save history

    func commitSaveHistoryOption(_ option: SaveHistoryOption) {
        saveHistoryOption = option
        store.saveHistoryOption = option
    }

    // MARK: - Session lock timeout

    func commitFaceSessionTimeoutOption(_ option: FaceSessionTimeoutOption) {
        faceSessionTimeoutOption = option
        store.faceSessionTimeoutOption = option
        FaceSessionManager.shared.inactivityTimeout = option.seconds
    }

    // MARK: - Hazardous tray color

    func resetHazardousTrayColor() {
        store.hazardousTrayColor = nil
        hazardousTrayColor = nil
    }

    // MARK: - PMS-gated settings

    /// Reset the PMS-integration-gated settings to their defaults (off / empty).
    /// Called when PMS integration is off so a stale "on" value can't take effect:
    /// Back Count, Hazardous Drug, Require Double Count (schedules) and the
    /// Hazardous Tray Color. No-op when everything is already at default.
    func resetPmsGatedSettings() {
        if isBackCountRequired { setBackCountRequired(false) }
        if isHazardousDrugSettingEnabled { setHazardousDrugSetting(false) }
        if !selectedSchedules.isEmpty {
            selectedSchedules = []
            store.selectedSchedules = []
        }
        if hazardousTrayColor != nil { resetHazardousTrayColor() }
    }

    // MARK: - Clear local data

    func clearLocalData() {
        dataCleaner.clearAll()
    }

    // MARK: - Unsynced count (menu badge)

    private func refreshUnsyncedCount() {
        unsyncedCount = batchStore.countCompletedUnsynced()
            + transactionStore.countCompletedUnsynced()
    }
}
