import Foundation

public enum LogEvent: String {
    // MARK: - Auth / Login
    case loginFailed = "LOGIN_FAILED"
    case logoutFailed = "LOGOUT_FAILED"
    case sessionExpired = "SESSION_EXPIRED"
    case sessionTimeout = "SESSION_TIMEOUT"
    /// Marker entry on every session-id rotation; bypasses the ERROR+ filters.
    case sessionStarted = "SESSION_STARTED"

    // MARK: - OTP
    case otpVerifyFailed = "OTP_VERIFY_FAILED"
    /// Not in the original enum spec — added because sendOTP/resendOTP failures
    /// in LoginViewModel are a distinct action from verification and have no
    /// close match among the given cases.
    case otpSendFailed = "OTP_SEND_FAILED"

    // MARK: - PIN
    case pinVerifyFailed = "PIN_VERIFY_FAILED"

    // MARK: - Face auth
    case faceRegisterFailed = "FACE_REGISTER_FAILED"
    case faceCaptureFailed = "FACE_CAPTURE_FAILED"
    case faceDuplicateFound = "FACE_DUPLICATE_FOUND"
    case faceVerifyFailed = "FACE_VERIFY_FAILED"
    case faceDeleteFailed = "FACE_DELETE_FAILED"
    case faceLockTimeout = "FACE_LOCK_TIMEOUT"
    case faceProfileObserveFailed = "FACE_PROFILE_OBSERVE_FAILED"

    // MARK: - Dashboard
    case userFetchFailed = "USER_FETCH_FAILED"

    // MARK: - Dispense flow
    case rxScanFailed = "RX_SCAN_FAILED"
    case ndcScanFailed = "NDC_SCAN_FAILED"
    case ndcNotFound = "NDC_NOT_FOUND"
    case vialScanFailed = "VIAL_SCAN_FAILED"
    case dispenseCount = "DISPENSE_COUNT"

    // MARK: - Pill scanning / counting
    case trayClassifyFailed = "TRAY_CLASSIFY_FAILED"
    case gloveDetectFailed = "GLOVE_DETECT_FAILED"
    case modelLoadFailed = "MODEL_LOAD_FAILED"

    // MARK: - History
    case historyLoadFailed = "HISTORY_LOAD_FAILED"
    case historyDeleteFailed = "HISTORY_DELETE_FAILED"

    // MARK: - HL7
    case hl7SendSuccess = "HL7_SEND_SUCCESS"
    case hl7SendFailed = "HL7_SEND_FAILED"
    case hl7ReceiveFailed = "HL7_RECEIVE_FAILED"
    case hl7ConnectFailed = "HL7_CONNECT_FAILED"
    case hl7ResendFailed = "HL7_RESEND_FAILED"
    case hl7OrderEdit = "HL7_ORDER_EDIT"
    case hl7OrderCancel = "HL7_ORDER_CANCEL"
    case hl7ServiceError = "HL7_SERVICE_ERROR"
    case hl7ServiceStopped = "HL7_SERVICE_STOPPED"

    // MARK: - Sync / offline
    case transactionSyncFailed = "TRANSACTION_SYNC_FAILED"
    case inventorySyncFailed = "INVENTORY_SYNC_FAILED"
    case syncRetryFailed = "SYNC_RETRY_FAILED"

    // MARK: - Profile / terminal / settings
    case profileUpdateFailed = "PROFILE_UPDATE_FAILED"
    case profileDeleteFailed = "PROFILE_DELETE_FAILED"
    case terminalUpdateFailed = "TERMINAL_UPDATE_FAILED"
    case terminalLoadFailed = "TERMINAL_LOAD_FAILED"
    case settingsFetchFailed = "SETTINGS_FETCH_FAILED"
    case transactionPurgeFailed = "TRANSACTION_PURGE_FAILED"
    case pmsTestFailed = "PMS_TEST_FAILED"

    // MARK: - Drug lookup
    case drugLookupFailed = "DRUG_LOOKUP_FAILED"
    case drugImageFailed = "DRUG_IMAGE_FAILED"

    // MARK: - Token / health
    case tokenRefreshFailed = "TOKEN_REFRESH_FAILED"
    case healthCheckFailed = "HEALTH_CHECK_FAILED"

    // MARK: - Security
    case dbKeyRotateFailed = "DB_KEY_ROTATE_FAILED"
    case securityCheckFailed = "SECURITY_CHECK_FAILED"
    case navigationFailed = "NAVIGATION_FAILED"

    // MARK: - Generic infra
    case scanFailed = "SCAN_FAILED"
    case networkTimeout = "NETWORK_TIMEOUT"
    case networkError = "NETWORK_ERROR"
    case databaseError = "DATABASE_ERROR"
    case fileWriteError = "FILE_WRITE_ERROR"

    // MARK: - Fallbacks (used by RemoteLogDestination when a call site omits event)
    case appCrash = "APP_CRASH"
    case unknownError = "UNKNOWN_ERROR"
}
