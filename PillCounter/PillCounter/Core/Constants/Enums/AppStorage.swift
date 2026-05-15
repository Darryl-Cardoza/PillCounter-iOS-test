//
//  AppStorage.swift
//  PillCounter
//

import Foundation

final class AppStorageManager {
    static let shared = AppStorageManager()
    private let defaults = UserDefaults.standard
    private init() {}

    // MARK: - AppStorageKeys
    public enum AppStorageKeys {
        // ── Keychain keys (sensitive) ─────────────────────────────────────
        static let accessToken          = "access_token"
        static let refreshToken         = "refresh_token"
        static let userId               = "user_id"
        static let userEmail            = "user_email"

        // ── UserDefaults keys (non-sensitive) ────────────────────────────
        static let rememberMe           = "remember_me"
        static let userSavedEmails      = "user_saved_emails"
        static let isLoggedIn           = "is_logged_in"
        static let drugIdCounter        = "drug_id_counter"
        static let isNewUser            = "is_new_user"
        static let tokenExpiryTimestamp = "token_expiry_timestamp"
        static let saveHistoryOption    = "save_history_option"
        static let isHl7Enable          = "is_hl7_enable"
        static let pmsHostName          = "pms_host_name"
        static let pillCounterHostName  = "pillcounter_host_name"
        static let barcodeFormat        = "barcode_format"
        static let bucketList           = "bucket_list"
        static let isPillCountingEnabled = "isPillCountingEnabled"
        static let isBackCountRequired  = "isBackCountRequired"
        static let isHapticEnabled      = "isHapticEnabled"
        static let isSoundEnabled       = "isSoundEnabled"
        static let isSpeechEnabled      = "isSpeechEnabled"
        static let selectedSchedules    = "selectedSchedules"
    }

    // MARK: - Access Token  (Keychain)
    var accessToken: String? {
        get { Keychain.getPassword(for: AppStorageKeys.accessToken) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.accessToken) }
            else                { Keychain.deletePassword(for: AppStorageKeys.accessToken) }
        }
    }

    // MARK: - Refresh Token  (Keychain)
    var refreshToken: String? {
        get { Keychain.getPassword(for: AppStorageKeys.refreshToken) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.refreshToken) }
            else                { Keychain.deletePassword(for: AppStorageKeys.refreshToken) }
        }
    }

    // MARK: - User ID  (Keychain)
    var userId: String? {
        get { Keychain.getPassword(for: AppStorageKeys.userId) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.userId) }
            else                { Keychain.deletePassword(for: AppStorageKeys.userId) }
        }
    }

    // MARK: - User Email  (Keychain)
    var userEmail: String? {
        get { Keychain.getPassword(for: AppStorageKeys.userEmail) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.userEmail) }
            else                { Keychain.deletePassword(for: AppStorageKeys.userEmail) }
        }
    }

    // MARK: - Drug ID Counter  (UserDefaults — not sensitive)
    var drugIdCounter: Int? {
        get { defaults.integer(forKey: AppStorageKeys.drugIdCounter) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.drugIdCounter) }
    }

    // MARK: - Is Logged In  (UserDefaults — boolean flag only, no credential)
    var isLoggedIn: Bool? {
        get { defaults.bool(forKey: AppStorageKeys.isLoggedIn) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isLoggedIn) }
    }

    // MARK: - Is New User
    var isNewUser: Bool? {
        get { defaults.bool(forKey: AppStorageKeys.isNewUser) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isNewUser) }
    }

    // MARK: - User Saved Emails  (UserDefaults — used for login autocomplete, not a credential)
    var userSavedEmails: [String] {
        get {
            if let data = defaults.data(forKey: AppStorageKeys.userSavedEmails),
               let emails = try? JSONDecoder().decode([String].self, from: data) {
                return emails
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.setValue(data, forKey: AppStorageKeys.userSavedEmails)
            }
        }
    }

    // MARK: - Pill Counting Toggle
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

    var barcodeFormat: String {
        get { defaults.string(forKey: AppStorageKeys.barcodeFormat) ?? "" }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.barcodeFormat) }
    }

    var bucket: [String] {
        get { defaults.stringArray(forKey: AppStorageKeys.bucketList) ?? [] }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.bucketList) }
    }

    var isHl7Enabled: Bool {
        get { defaults.bool(forKey: AppStorageKeys.isHl7Enable) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.isHl7Enable) }
    }

    var pmsHostName: String {
        get { defaults.string(forKey: AppStorageKeys.pmsHostName) ?? "" }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.pmsHostName) }
    }

    var pillCounterHostName: String {
        get { defaults.string(forKey: AppStorageKeys.pillCounterHostName) ?? "" }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.pillCounterHostName) }
    }

    // MARK: - Remember Me
    var rememberMe: Bool? {
        get { defaults.bool(forKey: AppStorageKeys.rememberMe) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.rememberMe) }
    }

    // MARK: - Save History Option
    var saveHistoryOption: SaveHistoryOption {
        get {
            guard let rawValue = defaults.string(forKey: AppStorageKeys.saveHistoryOption),
                  let option = SaveHistoryOption(rawValue: rawValue)
            else { return .default }
            return option
        }
        set { defaults.setValue(newValue.rawValue, forKey: AppStorageKeys.saveHistoryOption) }
    }

    // MARK: - Token Expiry  (UserDefaults — a timestamp, not a credential)
    var tokenExpiryTimestamp: Double? {
        get { defaults.double(forKey: AppStorageKeys.tokenExpiryTimestamp) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.tokenExpiryTimestamp) }
    }

    // MARK: - Email helpers
    func addEmail(_ email: String) {
        guard !userSavedEmails.contains(email) else { return }
        userSavedEmails.append(email)
    }

    func clearEmails() { userSavedEmails.removeAll() }

    // MARK: - Clear Session
    /// Wipes all credential data from both Keychain and UserDefaults.
    func clearUserSession() {
        // Keychain (sensitive)
        Keychain.deletePassword(for: AppStorageKeys.accessToken)
        Keychain.deletePassword(for: AppStorageKeys.refreshToken)
        Keychain.deletePassword(for: AppStorageKeys.userId)
        Keychain.deletePassword(for: AppStorageKeys.userEmail)
        // UserDefaults (non-sensitive session flags)
        defaults.removeObject(forKey: AppStorageKeys.rememberMe)
        defaults.removeObject(forKey: AppStorageKeys.userSavedEmails)
        defaults.removeObject(forKey: AppStorageKeys.isLoggedIn)
        defaults.removeObject(forKey: AppStorageKeys.tokenExpiryTimestamp)
    }

    // MARK: - Logout
    /// Full logout — wipes credentials and session-scoped settings.
    func logout() {
        // Keychain (sensitive)
        Keychain.deletePassword(for: AppStorageKeys.accessToken)
        Keychain.deletePassword(for: AppStorageKeys.refreshToken)
        Keychain.deletePassword(for: AppStorageKeys.userId)
        Keychain.deletePassword(for: AppStorageKeys.userEmail)
        // UserDefaults (session flags and server-driven config)
        [
            AppStorageKeys.rememberMe,
            AppStorageKeys.isLoggedIn,
            AppStorageKeys.tokenExpiryTimestamp,
            AppStorageKeys.isHl7Enable,
            AppStorageKeys.pmsHostName,
            AppStorageKeys.pillCounterHostName,
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}
