//
//  AppStorage.swift
//  PillCounter
//

import Foundation

/// HL7 spec dialect selection, driven by `auth/me` → `settings.hl7_message_spec`.
/// Sets MSH-3 sending application and which custom Z-segment (if any) gets
/// emitted on outbound dispense messages.
enum Hl7Format: String, Codable {
    case dispensesure = "DISPENSESURE"
    case eyecon = "EYECON"
    case vivid = "VIVID"

    /// `sendingApplication` is the MSH-3 wire value, which is this enum's own rawValue.
    static func fromSendingApplication(_ value: String?) -> Hl7Format {
        guard let value, let format = Hl7Format(rawValue: value.uppercased()) else {
            return .dispensesure
        }
        return format
    }
}

final class AppStorageManager {
    static let shared = AppStorageManager()
    private let defaults = UserDefaults.standard
    private init() {
        clearKeychainOnFreshInstall()
    }

    /// Set by `clearKeychainOnFreshInstall` when this launch wiped the
    /// Keychain, and consumed by `purgeFaceEnrollmentsIfKeychainWasWiped()`.
    /// Backed by UserDefaults rather than an in-memory flag so a crash between
    /// the wipe and the purge still leaves the orphaned rows scheduled for
    /// deletion on the next launch.
    private var faceEnrollmentPurgePending: Bool {
        get { defaults.bool(forKey: AppStorageKeys.faceEnrollmentPurgePending) }
        set { defaults.set(newValue, forKey: AppStorageKeys.faceEnrollmentPurgePending) }
    }

    /// Keychain accounts that must survive any blanket wipe (logout,
    /// fresh-install cleanup) — the wrapped DEK/KEK bookkeeping. Deleting
    /// these would silently make every already-encrypted CoreData field and
    /// photo file permanently unreadable, contradicting the explicit "local
    /// data is preserved" contract those wipes are meant to honor for
    /// everything else. The Secure Enclave KEK keypair itself is a
    /// `kSecClassKey` item, not `kSecClassGenericPassword`, so it's already
    /// untouched by `Keychain.deleteAll` regardless — only the bookkeeping
    /// strings below (and any server KEK's raw bytes, addressed by alias,
    /// not by these fixed account names) need explicit preservation here.
    private static let dekBookkeepingAccounts: Set<String> = [
        AppStorageKeys.dekWrapped,
        AppStorageKeys.dekKekId,
        AppStorageKeys.dekKekVersion,
        AppStorageKeys.imageDekWrapped,
        AppStorageKeys.imageDekKekId,
        AppStorageKeys.imageDekKekVersion,
    ]

    private func clearKeychainOnFreshInstall() {
        guard !defaults.bool(forKey: AppStorageKeys.hasLaunchedBefore) else { return }
        Keychain.deleteAll(preservedAccounts: Self.dekBookkeepingAccounts)
        // Core Data is deliberately NOT touched here. This initializer can run
        // before CoreDataManager.shared has loaded the managed object model —
        // AppStorageManager.shared is reachable from view model default
        // arguments, which SwiftUI evaluates as stored-property initializers
        // before PillCounterApp.init's body runs. Fetching an entity at that
        // point crashes with "could not locate an NSEntityDescription".
        faceEnrollmentPurgePending = true
        defaults.set(true, forKey: AppStorageKeys.hasLaunchedBefore)
    }

    /// Wiping the Keychain destroys the field-encryption key. Any
    /// FaceEmbeddingEntity/FaceUserEntity rows already on disk were
    /// encrypted with the now-gone key and can never be decrypted again —
    /// leaving orphaned ciphertext that silently fails "quick access"
    /// forever. Purge them so a wiped key never outlives its data.
    ///
    /// Must be called only once the Core Data stack is up — see
    /// `PillCounterApp.init`.
    func purgeFaceEnrollmentsIfKeychainWasWiped() {
        guard faceEnrollmentPurgePending else { return }
        FaceEmbeddingStore.shared.deleteAll()
        FaceUserStore.shared.deleteAll()
        faceEnrollmentPurgePending = false
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
        static let isStandalone         = "is_standalone"
        static let allowLocalStorage    = "allow_local_storage"
        static let hl7Version           = "hl7_version"
        static let pmsHostName          = "pms_host_name"
        static let pillCounterHostName  = "pillcounter_host_name"
        static let barcodeFormat        = "barcode_format"
        static let bucketList           = "bucket_list"
        static let userSavedEmails      = "user_saved_emails"
        static let hazardousTrayColors  = "hazardous_tray_colors"
        static let bypassSSL            = "bypass_ssl"
        static let hl7MessageSpec       = "hl7_message_spec"
        static let useStaticPMSConnection = "use_static_pms_connection"
        static let pmsIpAddress         = "pms_ip_address"
        static let pmsPort              = "pms_port"
        static let dekWrapped           = "dek_wrapped"
        static let dekKekId             = "dek_kek_id"
        static let dekKekVersion        = "dek_kek_version"
        static let imageDekWrapped      = "image_dek_wrapped"
        static let imageDekKekId        = "image_dek_kek_id"
        static let imageDekKekVersion   = "image_dek_kek_version"

        // UserDefaults-backed (non-sensitive)
        static let faceEnrollmentPurgePending = "face_enrollment_purge_pending"
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
        static let deviceKey            = "device_key"
        static let isHarzardousDrugSetting = "hazardous_pill_setting"
        static let deleteCompletedTransactions = "delete_completed_transactions"
        static let pillCountRingOffsetX = "pill_count_ring_offset_x"
        static let pillCountRingOffsetY = "pill_count_ring_offset_y"
        static let selectedPharmacyType = "selected_pharmacy_type"
        static let pharmacyTypeOptions  = "pharmacy_type_options"
        static let faceLockCurrentUserId   = "face_lock_current_user_id"
        static let faceLockCurrentUserName = "face_lock_current_user_name"
        static let faceSessionTimeoutOption = "face_session_timeout_option"
        static let selectedCountryCode  = "selected_country_code"
        static let selectedStateCode    = "selected_state_code"
        static let countryOptions       = "country_options"

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

    /// When true, HL7 server runs regardless of `isPmsIntegrated` — server-driven
    /// (`auth/me` → `settings.is_standalone`).
    var isStandalone: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.isStandalone) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.isStandalone) }
    }

    /// Server-driven PMS discovery gate (`auth/me` → `settings.use_static_pms_connection`).
    /// false → Bonjour discovery (current default). true → connect direct via `pmsIpAddress`/`pmsPort`.
    /// Defaults to false until `auth/me` returns a value.
    var useStaticPMSConnection: Bool {
        get { Keychain.getPassword(for: AppStorageKeys.useStaticPMSConnection) == "true" }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.useStaticPMSConnection) }
    }

    /// PMS computer's direct IP address, server-provided (`auth/me` → `settings.pms_ip_address`).
    var pmsIpAddress: String? {
        get { Keychain.getPassword(for: AppStorageKeys.pmsIpAddress) }
        set {
            if let v = newValue { Keychain.savePassword(v, for: AppStorageKeys.pmsIpAddress) }
            else                { Keychain.deletePassword(for: AppStorageKeys.pmsIpAddress) }
        }
    }

    /// PMS computer's direct port, server-provided (`auth/me` → `settings.pms_port`).
    var pmsPort: Int? {
        get {
            guard let s = Keychain.getPassword(for: AppStorageKeys.pmsPort) else { return nil }
            return Int(s)
        }
        set {
            if let v = newValue { Keychain.savePassword(String(v), for: AppStorageKeys.pmsPort) }
            else                { Keychain.deletePassword(for: AppStorageKeys.pmsPort) }
        }
    }

    /// HL7 version the PMS integration should speak, provided by the server
    /// (`auth/me` → `settings.hl7_version`, e.g. "2.3.1"). Falls back to "2.3"
    /// when never set (fresh install / no PMS integration yet).
    var hl7Version: String {
        get {
            let stored = Keychain.getPassword(for: AppStorageKeys.hl7Version)
            return (stored?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? "2.3" : stored!
        }
        set { Keychain.savePassword(newValue, for: AppStorageKeys.hl7Version) }
    }

    /// When true, HL7 MLLP and the image server skip TLS/cert trust entirely.
    /// Server-driven (`auth/me` → `settings.bypass_ssl`), defaults to `true`
    /// (matches Android's default) when never set.
    var bypassSSL: Bool {
        get {
            guard let raw = Keychain.getPassword(for: AppStorageKeys.bypassSSL) else { return true }
            return raw == "true"
        }
        set { Keychain.savePassword(newValue ? "true" : "false", for: AppStorageKeys.bypassSSL) }
    }

    /// HL7 spec dialect the PMS integration should speak, provided by the server
    /// (`auth/me` → `settings.hl7_message_spec`). Falls back to `.dispensesure`.
    var hl7MessageSpec: Hl7Format {
        get { Hl7Format(rawValue: Keychain.getPassword(for: AppStorageKeys.hl7MessageSpec) ?? "") ?? .dispensesure }
        set { Keychain.savePassword(newValue.rawValue, for: AppStorageKeys.hl7MessageSpec) }
    }

    // Generic Keychain-backed accessors used by `DatabaseKeyProvider` for its
    // per-slot DEK bookkeeping (wrapped blob, KEK id, KEK version) — one pair
    // of key names per `DekSlot` (see `AppStorageKeys.dekWrapped` /
    // `.imageDekWrapped` and friends), same underlying storage/behavior as
    // every other Keychain-backed property on this type.
    func string(forKey key: String) -> String? {
        Keychain.getPassword(for: key)
    }

    func setString(_ value: String?, forKey key: String) {
        if let value { Keychain.savePassword(value, for: key) }
        else         { Keychain.deletePassword(for: key) }
    }

    func int(forKey key: String) -> Int {
        Int(Keychain.getPassword(for: key) ?? "") ?? -1
    }

    func setInt(_ value: Int, forKey key: String) {
        Keychain.savePassword(String(value), for: key)
    }

    var pmsHostName: String {
        get { Keychain.getPassword(for: AppStorageKeys.pmsHostName) ?? "" }
        set { Keychain.savePassword(newValue, for: AppStorageKeys.pmsHostName) }
    }

    /// Live Bonjour/static-connect service name resolved when the HL7 client
    /// connects (`Hl7ServiceManager.currentServiceName`). Runtime-only — not
    /// persisted — since it reflects the currently connected PMS instance,
    /// not a user-configured setting. Used as MSH-4 (receiving facility) so
    /// outgoing messages identify the actual connected receiver.
    var resolvedPMSServiceName: String?

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

    /// Session-lock idle timeout, editable under Settings > Face Recognition
    /// > Time Limit. Read by FaceSessionManager to configure its idle timer.
    var faceSessionTimeoutOption: FaceSessionTimeoutOption {
        get {
            guard defaults.object(forKey: AppStorageKeys.faceSessionTimeoutOption) != nil else { return .default }
            let raw = defaults.integer(forKey: AppStorageKeys.faceSessionTimeoutOption)
            return FaceSessionTimeoutOption(rawValue: raw) ?? .default
        }
        set { defaults.setValue(newValue.rawValue, forKey: AppStorageKeys.faceSessionTimeoutOption) }
    }

    var selectedTerminalName: String {
        get {
            defaults.string(forKey: AppStorageKeys.selectedTerminalName) ?? ""
        }
        set {
            defaults.setValue(newValue, forKey: AppStorageKeys.selectedTerminalName)
        }
    }

    /// Stable per-install device identifier (from `identifierForVendor`), used to
    /// determine which terminal this device currently holds — never infer that
    /// from a terminal's `isActive` flag, which is account-wide, not per-device.
    /// Set once by `DeviceKeyProvider`; UserDefaults-backed (not Keychain) so a
    /// reinstall clears this value along with the rest of UserDefaults. Note this
    /// is not a hard reinstall guarantee: `identifierForVendor` itself can return
    /// the same UUID across reinstall if another app from the same vendor is still
    /// installed — in that case the underlying device key is unchanged regardless
    /// of where we cache it.
    var deviceKey: String? {
        get { defaults.string(forKey: AppStorageKeys.deviceKey) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.deviceKey) }
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

    /// Selected pharmacy type **code** (server value, e.g. "chain_pharmacy") —
    /// not the display label. Backed by the server-driven list in `pharmacyTypeOptions`.
    var selectedPharmacyTypeCode: String? {
        get { defaults.string(forKey: AppStorageKeys.selectedPharmacyType) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.selectedPharmacyType) }
    }

    /// Pharmacy type list fetched from `/users/pharmacy-types`, cached so the
    /// dropdown still has options offline / before the next fetch completes.
    var pharmacyTypeOptions: [PharmacyTypeOption] {
        get {
            guard let data = defaults.data(forKey: AppStorageKeys.pharmacyTypeOptions),
                  let options = try? JSONDecoder().decode([PharmacyTypeOption].self, from: data)
            else { return [] }
            return options
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.setValue(data, forKey: AppStorageKeys.pharmacyTypeOptions)
        }
    }

    /// Last session-lock owner, persisted so the owner's name/id survive an
    /// app relaunch for display purposes (e.g. "last used" attribution). This
    /// does NOT bypass the lock screen — cold launch always re-locks
    /// regardless of these values (see FaceSessionManager.lockOnColdLaunch).
    var faceLockCurrentUserId: String? {
        get { defaults.string(forKey: AppStorageKeys.faceLockCurrentUserId) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.faceLockCurrentUserId) }
    }

    var faceLockCurrentUserName: String? {
        get { defaults.string(forKey: AppStorageKeys.faceLockCurrentUserName) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.faceLockCurrentUserName) }
    }

    /// Selected country **code** (server value, e.g. "US"), required field.
    var selectedCountryCode: String? {
        get { defaults.string(forKey: AppStorageKeys.selectedCountryCode) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.selectedCountryCode) }
    }

    /// Selected state **code** (server value, e.g. "AK"), required field.
    var selectedStateCode: String? {
        get { defaults.string(forKey: AppStorageKeys.selectedStateCode) }
        set { defaults.setValue(newValue, forKey: AppStorageKeys.selectedStateCode) }
    }

    /// Country (with nested states) list fetched from `/reference/countries`,
    /// cached so the dropdown still has options offline / before the next fetch completes.
    var countryOptions: [Country] {
        get {
            guard let data = defaults.data(forKey: AppStorageKeys.countryOptions),
                  let options = try? JSONDecoder().decode([Country].self, from: data)
            else { return [] }
            return options
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.setValue(data, forKey: AppStorageKeys.countryOptions)
        }
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

    /// Full logout — wipes every Keychain item for this app except the
    /// wrapped DEK/KEK bookkeeping, then clears non-sensitive UserDefaults
    /// session flags. Local CoreData (and its encrypted field values,
    /// and encrypted photo files) is preserved so a returning user finds
    /// their history intact AND still decryptable — wiping the DEK here
    /// would silently make every encrypted row/photo permanently unreadable
    /// on next login, contradicting that intent.
    func logout() {
        Keychain.deleteAll(preservedAccounts: Self.dekBookkeepingAccounts)
        // Same reason as on a fresh install: the wipe above destroys the
        // field-encryption key, so the face rows it wrote can never be read
        // again. Flag first, then purge — if the purge is interrupted, the
        // flag survives and the next launch finishes the job.
        faceEnrollmentPurgePending = true
        purgeFaceEnrollmentsIfKeychainWasWiped()

        defaults.removeObject(forKey: AppStorageKeys.isNewUser)
        clearTerminalCache()
    }
}
