import Foundation

public enum LogEvent: String {
    // MARK: - Auth / Login
    case loginSubmitted = "LOGIN_SUBMITTED"
    case loginFailed = "LOGIN_FAILED"
    case logoutSuccess = "LOGOUT_SUCCESS"
    case logoutFailed = "LOGOUT_FAILED"
    case sessionExpired = "SESSION_EXPIRED"
    case sessionTimeout = "SESSION_TIMEOUT"

    // MARK: - OTP
    case otpVerified = "OTP_VERIFIED"
    case otpVerifyFailed = "OTP_VERIFY_FAILED"
    /// Not in the original enum spec — added because sendOTP/resendOTP failures
    /// in LoginViewModel are a distinct action from verification and have no
    /// close match among the given cases.
    case otpSendFailed = "OTP_SEND_FAILED"

    // MARK: - PIN
    case pinVerified = "PIN_VERIFIED"
    case pinVerifyFailed = "PIN_VERIFY_FAILED"

    // MARK: - Face auth
    case faceRegisterSuccess = "FACE_REGISTER_SUCCESS"
    case faceRegisterFailed = "FACE_REGISTER_FAILED"
    case faceCaptureFailed = "FACE_CAPTURE_FAILED"
    case faceDuplicateFound = "FACE_DUPLICATE_FOUND"
    case faceVerifySuccess = "FACE_VERIFY_SUCCESS"
    case faceVerifyFailed = "FACE_VERIFY_FAILED"
    case faceDeleteSuccess = "FACE_DELETE_SUCCESS"
    case faceDeleteFailed = "FACE_DELETE_FAILED"
    case faceLockSession = "FACE_LOCK_SESSION"
    case faceLockTimeout = "FACE_LOCK_TIMEOUT"
    case faceProfileObserveFailed = "FACE_PROFILE_OBSERVE_FAILED"

    // MARK: - Dashboard
    case userFetchFailed = "USER_FETCH_FAILED"
    case dashboardLoadFailed = "DASHBOARD_LOAD_FAILED"
    case kekRotateSuccess = "KEK_ROTATE_SUCCESS"
    case kekRotateFailed = "KEK_ROTATE_FAILED"

    // MARK: - Dispense flow
    case rxScanSuccess = "RX_SCAN_SUCCESS"
    case rxScanFailed = "RX_SCAN_FAILED"
    case rxConfirmed = "RX_CONFIRMED"
    case rxCancelled = "RX_CANCELLED"
    case ndcScanSuccess = "NDC_SCAN_SUCCESS"
    case ndcScanFailed = "NDC_SCAN_FAILED"
    case ndcMismatch = "NDC_MISMATCH"
    case ndcNotFound = "NDC_NOT_FOUND"
    case substituteConfirmed = "SUBSTITUTE_CONFIRMED"
    case vialScanFailed = "VIAL_SCAN_FAILED"
    case dispenseResumed = "DISPENSE_RESUMED"
    case dispenseResumeFailed = "DISPENSE_RESUME_FAILED"
    case dispenseCount = "DISPENSE_COUNT"
    case dispenseFailed = "DISPENSE_FAILED"

    // MARK: - Batch count / inventory
    case batchCount = "BATCH_COUNT"
    case batchCreateFailed = "BATCH_CREATE_FAILED"
    case batchDeleteSuccess = "BATCH_DELETE_SUCCESS"
    case batchDeleteFailed = "BATCH_DELETE_FAILED"
    case inventoryScanFailed = "INVENTORY_SCAN_FAILED"
    case inventoryCountSaved = "INVENTORY_COUNT_SAVED"
    case inventoryCountFailed = "INVENTORY_COUNT_FAILED"
    case stockCountComplete = "STOCK_COUNT_COMPLETE"
    case stockCountDiscarded = "STOCK_COUNT_DISCARDED"

    // MARK: - Pill scanning / counting
    case countResume = "COUNT_RESUME"
    case pillCountSaved = "PILL_COUNT_SAVED"
    case pillCountFailed = "PILL_COUNT_FAILED"
    case pillCountReset = "PILL_COUNT_RESET"
    case trayClassifyFailed = "TRAY_CLASSIFY_FAILED"
    case gloveDetectFailed = "GLOVE_DETECT_FAILED"
    case modelLoadFailed = "MODEL_LOAD_FAILED"

    // MARK: - History
    case historyLoadFailed = "HISTORY_LOAD_FAILED"
    case historyDeleteSuccess = "HISTORY_DELETE_SUCCESS"
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
    case transactionSyncSuccess = "TRANSACTION_SYNC_SUCCESS"
    case transactionSyncFailed = "TRANSACTION_SYNC_FAILED"
    case inventorySyncFailed = "INVENTORY_SYNC_FAILED"
    case syncRetryFailed = "SYNC_RETRY_FAILED"

    // MARK: - Profile / terminal / settings
    case profileUpdateSuccess = "PROFILE_UPDATE_SUCCESS"
    case profileUpdateFailed = "PROFILE_UPDATE_FAILED"
    case profileDeleteFailed = "PROFILE_DELETE_FAILED"
    case terminalUpdateFailed = "TERMINAL_UPDATE_FAILED"
    case terminalLoadFailed = "TERMINAL_LOAD_FAILED"
    case settingsFetchFailed = "SETTINGS_FETCH_FAILED"
    case settingsApplyFailed = "SETTINGS_APPLY_FAILED"
    case transactionPurgeSuccess = "TRANSACTION_PURGE_SUCCESS"
    case transactionPurgeFailed = "TRANSACTION_PURGE_FAILED"
    case pmsTestSuccess = "PMS_TEST_SUCCESS"
    case pmsTestFailed = "PMS_TEST_FAILED"

    // MARK: - Drug lookup
    case drugLookupFailed = "DRUG_LOOKUP_FAILED"
    case drugImageFailed = "DRUG_IMAGE_FAILED"

    // MARK: - Token / health
    case tokenRefreshSuccess = "TOKEN_REFRESH_SUCCESS"
    case tokenRefreshFailed = "TOKEN_REFRESH_FAILED"
    case healthCheckFailed = "HEALTH_CHECK_FAILED"

    // MARK: - Security
    case dbKeyRotateFailed = "DB_KEY_ROTATE_FAILED"
    case auditLogFailed = "AUDIT_LOG_FAILED"
    case securityCheckFailed = "SECURITY_CHECK_FAILED"
    case cacheReadFailed = "CACHE_READ_FAILED"
    case navigationFailed = "NAVIGATION_FAILED"

    // MARK: - Generic infra
    case scanTimeout = "SCAN_TIMEOUT"
    case scanFailed = "SCAN_FAILED"
    case networkTimeout = "NETWORK_TIMEOUT"
    case networkError = "NETWORK_ERROR"
    case databaseError = "DATABASE_ERROR"
    case bluetoothError = "BLUETOOTH_ERROR"
    case permissionDenied = "PERMISSION_DENIED"
    case fileReadError = "FILE_READ_ERROR"
    case fileWriteError = "FILE_WRITE_ERROR"

    // MARK: - Fallbacks (used by RemoteLogDestination when a call site omits event)
    case appCrash = "APP_CRASH"
    case unknownError = "UNKNOWN_ERROR"
}
