//
//  AppStorage.swift
//  PillCounter
//

import Foundation

final class AppStorageManager {
    static let shared = AppStorageManager()
    private let defaults = UserDefaults.standard
    private init() {
        clearKeychainOnFreshInstall()
    }

    private func clearKeychainOnFreshInstall() {
        guard !defaults.bool(forKey: AppStorageKeys.hasLaunchedBefore) else { return }
        Keychain.deleteAll()
        defaults.set(true, forKey: AppStorageKeys.hasLaunchedBefore)
    }

    // MARK: - Key constants
    public enum AppStorageKeys {
        // Keychain-backed (sensitive)
        static let accessToken          = "access_token"
        static let refreshToken         = "refresh_token"
        static let userId               = "user_id"
        static let userEmail            = "user_email"
        static let isLoggedIn           = "is_logged_in"
        static let rememberMe           = "remember_me"
        static let tokenExpiryTimestamp = "token_expiry_timestamp"
        static let isHl7Enable          = "is_hl7_enable"
        static let pmsHostName          = "pms_host_name"
        static let pillCounterHostName  = "pillcounter_host_name"
        static let barcodeFormat        = "barcode_format"
        static let bucketList           = "bucket_list"
        static let userSavedEmails      = "user_saved_emails"

        // UserDefaults-backed (non-sensitive)
        static let drugIdCounter        = "drug_id_counter"
        static let isNewUser            = "is_new_user"
        static let saveHistoryOption    = "save_history_option"
        static let isPillCountingEnabled = "isPillCountingEnabled"
        static let isBackCountRequired  = "isBackCountRequired"
        static let isHapticEnabled      = "isHapticEnabled"
        static let isSoundEnabled       = "isSoundEnabled"
        static let isSpeechEnabled      = "isSpeechEnabled"
        static let selectedSchedules    = "selectedSchedules"
        static let selectedTerminalName = "selected_terminal_name"
        static let isHarzardousDrugSetting = "hazardous_pill_setting"

        // Fresh-install sentinel (UserDefaults only — cleared on app deletion)
        static let hasLaunchedBefore    = "has_launched_before"
    }

    // =========================================================================
    // MARK: - KEYCHAIN-BACKED
    // =========================================================================

    var accessToken: String? {
        get { Keychain.getPassword(for: AppStorageKeys.accessToken) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.accessToken) }
            else                { Keychain.deletePassword(for: AppStorageKeys.accessToken) }
        }
    }

    var refreshToken: String? {
        get { Keychain.getPassword(for: AppStorageKeys.refreshToken) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.refreshToken) }
            else                { Keychain.deletePassword(for: AppStorageKeys.refreshToken) }
        }
    }

    var userId: String? {
        get { Keychain.getPassword(for: AppStorageKeys.userId) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.userId) }
            else                { Keychain.deletePassword(for: AppStorageKeys.userId) }
        }
    }

    var userEmail: String? {
        get { Keychain.getPassword(for: AppStorageKeys.userEmail) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.userEmail) }
            else                { Keychain.deletePassword(for: AppStorageKeys.userEmail) }
        }
    }

    var isLoggedIn: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.isLoggedIn) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.isLoggedIn) }
    }

    var rememberMe: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.rememberMe) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.rememberMe) }
    }

    var tokenExpiryTimestamp: Double? {
        get {
            guard let s = Keychain.getPassword(for: AppStorageKeys.tokenExpiryTimestamp) else { return nil }
            return Double(s)
        }
        set {
            if let v = newValue { Keychain.savePassword(String(v), for: AppStorageKeys.tokenExpiryTimestamp) }
            else                { Keychain.deletePassword(for: AppStorageKeys.tokenExpiryTimestamp) }
        }
    }

    var isHl7Enabled: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.isHl7Enable) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.isHl7Enable) }
    }

    var pmsHostName: String {
        get { Keychain.getPassword(for: AppStorageKeys.pmsHostName) ?? "" }
        set { Keychain.savePassword(newValue, for: AppStorageKeys.pmsHostName) }
    }

    var pillCounterHostName: String {
        get { Keychain.getPassword(for: AppStorageKeys.pillCounterHostName) ?? "" }
        set { Keychain.savePassword(newValue, for: AppStorageKeys.pillCounterHostName) }
    }

    var barcodeFormat: String {
        get { Keychain.getPassword(for: AppStorageKeys.barcodeFormat) ?? "" }
        set { Keychain.savePassword(newValue, for: AppStorageKeys.barcodeFormat) }
    }

    var bucket: [String] {
        get {
            guard let json = Keychain.getPassword(for: AppStorageKeys.bucketList),
                  let data = json.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                Keychain.savePassword(json, for: AppStorageKeys.bucketList)
            }
        }
    }

    var userSavedEmails: [String] {
        get {
            guard let json = Keychain.getPassword(for: AppStorageKeys.userSavedEmails),
                  let data = json.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                Keychain.savePassword(json, for: AppStorageKeys.userSavedEmails)
            }
        }
    }

    func addEmail(_ email: String) {
        guard !userSavedEmails.contains(email) else { return }
        userSavedEmails.append(email)
    }

    func clearEmails() { userSavedEmails = [] }

    // =========================================================================
    // MARK: - USERDEFAULTS-BACKED (non-sensitive)
    // =========================================================================

    var drugIdCounter: Int? {
        get { defaults.integer(forKey: AppStorageKeys.drugIdCounter) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.drugIdCounter) }
    }

    var isNewUser: Bool {
        get { defaults.bool(forKey: AppStorageKeys.isNewUser) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isNewUser) }
    }
    
    var isHazardousDrugSetting: Bool {
        get { defaults.bool(forKey: AppStorageKeys.isHarzardousDrugSetting) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isHarzardousDrugSetting) }
    }

    var isPillCountingEnabled: Bool {
        get { defaults.bool(forKey: AppStorageKeys.isPillCountingEnabled) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isPillCountingEnabled) }
    }

    var isBackCountRequired: Bool {
        get {
            guard defaults.object(forKey: AppStorageKeys.isBackCountRequired) != nil else { return true }
            return defaults.bool(forKey: AppStorageKeys.isBackCountRequired)
        }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isBackCountRequired) }
    }

    var isHapticEnabled: Bool {
        get {
            guard defaults.object(forKey: AppStorageKeys.isHapticEnabled) != nil else { return true }
            return defaults.bool(forKey: AppStorageKeys.isHapticEnabled)
        }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isHapticEnabled) }
    }

    var isSoundEnabled: Bool {
        get {
            guard defaults.object(forKey: AppStorageKeys.isSoundEnabled) != nil else { return true }
            return defaults.bool(forKey: AppStorageKeys.isSoundEnabled)
        }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isSoundEnabled) }
    }

    var isSpeechEnabled: Bool {
        get {
            guard defaults.object(forKey: AppStorageKeys.isSpeechEnabled) != nil else { return true }
            return defaults.bool(forKey: AppStorageKeys.isSpeechEnabled)
        }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isSpeechEnabled) }
    }

    var selectedSchedules: Set<DrugSchedule> {
        get {
            let stored = defaults.stringArray(forKey: AppStorageKeys.selectedSchedules) ?? []
            return Set(stored.compactMap { DrugSchedule(rawValue: $0) })
        }
        set { defaults.setValue(newValue.map { $0.rawValue }, forKey: AppStorageKeys.selectedSchedules) }
    }

    var saveHistoryOption: SaveHistoryOption {
        get {
            guard let raw = defaults.string(forKey: AppStorageKeys.saveHistoryOption),
                  let opt = SaveHistoryOption(rawValue: raw) else { return .default }
            return opt
        }
        set { defaults.setValue(newValue.rawValue, forKey: AppStorageKeys.saveHistoryOption) }
    }

    var selectedTerminalName: String {
        get {
            defaults.string(forKey: AppStorageKeys.selectedTerminalName) ?? ""
        }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.selectedTerminalName)
        }
    }

    // =========================================================================
    // MARK: - SESSION MANAGEMENT
    // =========================================================================

    /// Clears auth credentials only — used on 401 / forced re-login.
    func clearUserSession() {
        Keychain.deletePassword(for: AppStorageKeys.accessToken)
        Keychain.deletePassword(for: AppStorageKeys.refreshToken)
        Keychain.deletePassword(for: AppStorageKeys.userId)
        Keychain.deletePassword(for: AppStorageKeys.userEmail)
        Keychain.deletePassword(for: AppStorageKeys.isLoggedIn)
        Keychain.deletePassword(for: AppStorageKeys.tokenExpiryTimestamp)
    }

    /// Full logout — atomically wipes every Keychain item for this app,
    /// then clears non-sensitive UserDefaults session flags.
    func logout() {
        // Single call removes all Keychain items — no risk of missing a key.
        Keychain.deleteAll()

        // Clear any residual UserDefaults session flags.
        defaults.removeObject(forKey: AppStorageKeys.isNewUser)
    }
}
