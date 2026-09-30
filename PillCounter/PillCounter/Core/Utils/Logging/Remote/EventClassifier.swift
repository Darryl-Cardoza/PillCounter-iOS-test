import Foundation

/// Resolution order: (1) explicit event on the call site, (2) the error's real
/// type — a timeout is a timeout regardless of screen, (3) originating
/// module/class refined by a message keyword for modules covering more than one
/// action, (4) generic fallback. See design spec §6 for the full rationale.
public enum EventClassifier {
    public static func classify(_ entry: LogEntry) -> LogEvent {
        if let event = entry.event { return event }
        if let error = entry.underlyingError, let byType = classifyByErrorType(error) {
            return byType
        }
        return classifyByModule(file: entry.file, message: entry.message)
    }

    private static func classifyByErrorType(_ error: Error) -> LogEvent? {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .networkTimeout : .networkError
        }
        if error is DecodingError { return .networkError }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, (134000..<135000).contains(nsError.code) {
            // Core Data's persistent-store error range.
            return .databaseError
        }

        let description = String(describing: error).lowercased()
        if description.contains("keychain") || description.contains("secitem") {
            return .securityCheckFailed
        }
        return nil
    }

    private static func classifyByModule(file: String, message: String) -> LogEvent {
        let path = file.lowercased()
        let module = LogModule(file: file)
        let text = message.lowercased()

        if module == .login {
            if text.contains("logout") { return .logoutFailed }
            if text.contains("session"), text.contains("idle") || text.contains("inactiv") {
                return .sessionTimeout
            }
            if text.contains("session"), text.contains("expire") || text.contains("unauthor") || text.contains("401") {
                return .sessionExpired
            }
            return .loginFailed
        }
        if module == .verify {
            return text.contains("pin") ? .pinVerifyFailed : .otpVerifyFailed
        }
        if module == .face {
            if text.contains("register") { return .faceRegisterFailed }
            if text.contains("capture") { return .faceCaptureFailed }
            if text.contains("duplicate") { return .faceDuplicateFound }
            if text.contains("delete") { return .faceDeleteFailed }
            if text.contains("lock") || text.contains("timeout") { return .faceLockTimeout }
            if text.contains("observe") { return .faceProfileObserveFailed }
            return .faceVerifyFailed
        }
        if module == .scanning {
            if text.contains("ndc") { return .ndcScanFailed }
            if text.contains("rx") { return .rxScanFailed }
            if text.contains("vial") { return .vialScanFailed }
            if text.contains("tray") { return .trayClassifyFailed }
            if text.contains("glove") { return .gloveDetectFailed }
            if text.contains("model") || text.contains("load") { return .modelLoadFailed }
            return .scanFailed
        }
        // Checked before the generic "hl7" branch below — HL7SyncQueue's path
        // contains "hl7" too, and its failures are sync/offline events, not
        // transport ones.
        if module == .syncQueue {
            if text.contains("inventory") { return .inventorySyncFailed }
            if text.contains("retry") { return .syncRetryFailed }
            return .transactionSyncFailed
        }
        if module == .hl7 {
            if text.contains("send") { return .hl7SendFailed }
            if text.contains("receive") { return .hl7ReceiveFailed }
            if text.contains("connect") { return .hl7ConnectFailed }
            if text.contains("resend") { return .hl7ResendFailed }
            if text.contains("stop") { return .hl7ServiceStopped }
            return .hl7ServiceError
        }
        if module == .history {
            return text.contains("delete") ? .historyDeleteFailed : .historyLoadFailed
        }
        if module == .settings {
            if path.contains("terminal") { return .terminalLoadFailed }
            if text.contains("profile") { return .profileUpdateFailed }
            if text.contains("pms") { return .pmsTestFailed }
            if text.contains("purge") { return .transactionPurgeFailed }
            return .settingsFetchFailed
        }
        if module == .dataStore {
            return .databaseError
        }
        if module == .security {
            return .securityCheckFailed
        }
        return .unknownError
    }
}

/// Path-to-feature lookup shared by event classification and remote tagging.
enum LogModule {
    case login, verify, syncQueue, face, scanning, hl7, history, settings, dataStore, security, other

    init(file: String) {
        let path = file.lowercased()
        if path.contains("/login/") || path.contains("sessionmanager") { self = .login }
        else if path.contains("verifypin") || path.contains("otp") { self = .verify }
        else if path.contains("hl7syncqueue") || path.contains("unsyncedtransaction") { self = .syncQueue }
        else if path.contains("/face") { self = .face }
        else if path.contains("/scanning/") || path.contains("/ocr/") { self = .scanning }
        else if path.contains("hl7") { self = .hl7 }
        else if path.contains("/history/") { self = .history }
        else if path.contains("/settings/") || path.contains("/profile/") { self = .settings }
        else if path.contains("localdatasource") || path.contains("coredatamanager") { self = .dataStore }
        else if path.contains("runtimeunit") || path.contains("/config/") { self = .security }
        else { self = .other }
    }
}
