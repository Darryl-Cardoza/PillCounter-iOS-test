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
        static let isPmsIntegrated      = "is_pms_integrated"
        static let allowLocalStorage    = "allow_local_storage"
        static let hl7Version           = "hl7_version"
        static let pmsHostName          = "pms_host_name"
        static let pillCounterHostName  = "pillcounter_host_name"
        static let barcodeFormat        = "barcode_format"
        static let bucketList           = "bucket_list"
        static let userSavedEmails      = "user_saved_emails"
        static let hazardousTrayColors  = "hazardous_tray_colors"

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
        static let storedTerminals      = "stored_terminals"
        static let isHarzardousDrugSetting = "hazardous_pill_setting"
        static let deleteCompletedTransactions = "delete_completed_transactions"
        static let pillCountRingOffsetX = "pill_count_ring_offset_x"
        static let pillCountRingOffsetY = "pill_count_ring_offset_y"
        static let selectedPharmacyType = "selected_pharmacy_type"

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

    var isPmsIntegrated: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.isPmsIntegrated) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.isPmsIntegrated) }
    }

    var allowLocalStorage: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.allowLocalStorage) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.allowLocalStorage) }
    }

    /// HL7 version the PMS integration should speak, provided by the server
    /// (`auth/me` → `settings.hl7_version`, e.g. "2.3.1"). Falls back to "2.3"
    /// when never set (fresh install / no PMS integration yet).
    var hl7Version: String {
        get { Keychain.getPassword(for: AppStorageKeys.hl7Version) ?? "2.3" }
        set { Keychain.savePassword(newValue, for: AppStorageKeys.hl7Version) }
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

    /// Stored generic colour(s) of the hazardous tray. The hazardous-tray feature
    /// captures the colour exactly once, so this list holds at most one entry.
    /// Backed by Keychain using the same JSON pattern as `bucket` / `userSavedEmails`.
    var hazardousTrayColors: [String] {
        get {
            guard let json = Keychain.getPassword(for: AppStorageKeys.hazardousTrayColors),
                  let data = json.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                Keychain.savePassword(json, for: AppStorageKeys.hazardousTrayColors)
            }
        }
    }

    /// Convenience accessor for the single stored hazardous tray colour name.
    /// Setting a non-nil value stores it as the only entry; setting nil clears it.
    var hazardousTrayColor: String? {
        get { hazardousTrayColors.first }
        set { hazardousTrayColors = newValue.map { [$0] } ?? [] }
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

    /// When true, a transaction is deleted as soon as it is completed so the
    /// dispense is not retained in the app. Driven by the mobile settings API
    /// (server-provided flag), defaults to `true` when never set.
    var deleteCompletedTransactions: Bool {
        get {
            guard defaults.object(forKey: AppStorageKeys.deleteCompletedTransactions) != nil else { return true }
            return defaults.bool(forKey: AppStorageKeys.deleteCompletedTransactions)
        }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.deleteCompletedTransactions) }
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

    /// Locally cached terminal list for the current user. Persisted so the
    /// terminal picker still works if /auth/me fails or the device is offline.
    /// Cleared on logout via `logout()` / `clearTerminalCache()`.
    var storedTerminals: [UserTerminal] {
        get {
            guard let data = defaults.data(forKey: AppStorageKeys.storedTerminals),
                  let terminals = try? JSONDecoder().decode([UserTerminal].self, from: data)
            else { return [] }
            return terminals
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.setValue(data, forKey: AppStorageKeys.storedTerminals)
        }
    }

    
    /// Last position the operator dragged the pill-count ring to, stored as an
    /// offset (in points) from the screen centre. `nil` when never moved — the
    /// layout then falls back to its default right-side resting position.
    var pillCountRingOffset: CGSize? {
        get {
            guard defaults.object(forKey: AppStorageKeys.pillCountRingOffsetX) != nil,
                  defaults.object(forKey: AppStorageKeys.pillCountRingOffsetY) != nil
            else { return nil }
            return CGSize(
                width: defaults.double(forKey: AppStorageKeys.pillCountRingOffsetX),
                height: defaults.double(forKey: AppStorageKeys.pillCountRingOffsetY)
            )
        }
        set {
            if let size = newValue {
                defaults.setValue(size.width, forKey: AppStorageKeys.pillCountRingOffsetX)
                defaults.setValue(size.height, forKey: AppStorageKeys.pillCountRingOffsetY)
            } else {
                defaults.removeObject(forKey: AppStorageKeys.pillCountRingOffsetX)
                defaults.removeObject(forKey: AppStorageKeys.pillCountRingOffsetY)
            }
        }
    }

    var selectedPharmacyType: PharmacyType? {
        get {
            guard let raw = defaults.string(forKey: AppStorageKeys.selectedPharmacyType) else { return nil }
            return PharmacyType(rawValue: raw)
        }
        set { defaults.setValue(newValue?.rawValue, forKey: AppStorageKeys.selectedPharmacyType) }
    }

    /// Clears the cached terminal list + selected terminal name.
    /// Call on logout / user switch so the next user never sees stale terminals.
    func clearTerminalCache() {
        defaults.removeObject(forKey: AppStorageKeys.storedTerminals)
        defaults.removeObject(forKey: AppStorageKeys.selectedTerminalName)
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

        defaults.removeObject(forKey: AppStorageKeys.isNewUser)
        clearTerminalCache()
    }
}
