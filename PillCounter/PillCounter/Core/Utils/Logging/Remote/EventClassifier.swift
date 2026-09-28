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
            switch urlError.code {
            case .timedOut:
                return .networkTimeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed:
                return .networkError
            default:
                return .networkError
            }
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
        let text = message.lowercased()

        if path.contains("/login/") || path.contains("sessionmanager") {
            if text.contains("logout") { return .logoutFailed }
            if text.contains("session"), text.contains("idle") || text.contains("inactiv") {
                return .sessionTimeout
            }
            if text.contains("session"), text.contains("expire") || text.contains("unauthor") || text.contains("401") {
                return .sessionExpired
            }
            return .loginFailed
        }
        if path.contains("verifypin") || path.contains("otp") {
            return text.contains("pin") ? .pinVerifyFailed : .otpVerifyFailed
        }
        if path.contains("/faceauth/") || path.contains("face") {
            if text.contains("register") { return .faceRegisterFailed }
            if text.contains("capture") { return .faceCaptureFailed }
            if text.contains("duplicate") { return .faceDuplicateFound }
            if text.contains("delete") { return .faceDeleteFailed }
            if text.contains("lock") || text.contains("timeout") { return .faceLockTimeout }
            if text.contains("observe") { return .faceProfileObserveFailed }
            return .faceVerifyFailed
        }
        if path.contains("/scanning/") || path.contains("/ocr/") {
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
        if path.contains("hl7syncqueue") || path.contains("unsyncedtransaction") {
            if text.contains("inventory") { return .inventorySyncFailed }
            if text.contains("retry") { return .syncRetryFailed }
            return .transactionSyncFailed
        }
        if path.contains("hl7") {
            if text.contains("send") { return .hl7SendFailed }
            if text.contains("receive") { return .hl7ReceiveFailed }
            if text.contains("connect") { return .hl7ConnectFailed }
            if text.contains("resend") { return .hl7ResendFailed }
            if text.contains("stop") { return .hl7ServiceStopped }
            return .hl7ServiceError
        }
        if path.contains("/history/") {
            return text.contains("delete") ? .historyDeleteFailed : .historyLoadFailed
        }
        if path.contains("/settings/") || path.contains("/profile/") {
            if path.contains("terminal") { return .terminalLoadFailed }
            if text.contains("profile") { return .profileUpdateFailed }
            if text.contains("pms") { return .pmsTestFailed }
            if text.contains("purge") { return .transactionPurgeFailed }
            return .settingsFetchFailed
        }
        if path.contains("localdatasource") || path.contains("coredatamanager") {
            return .databaseError
        }
        if path.contains("runtimeunit") || path.contains("/config/") {
            return .securityCheckFailed
        }
        return .unknownError
    }
}
