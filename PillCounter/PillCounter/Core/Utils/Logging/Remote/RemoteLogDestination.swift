import Foundation

final class RemoteLogDestination: LogDestination {
    private let uploader: RemoteLogSubmitting

    init(uploader: RemoteLogSubmitting = RemoteLogUploader.shared) {
        self.uploader = uploader
    }

    func write(_ entry: LogEntry, formatted: String) {
        guard entry.level >= .error || entry.event == .sessionStarted else { return }

        let event = entry.event ?? EventClassifier.classify(entry)
        let tag = Self.tag(forFile: entry.file)
        let network = NetworkStatusProvider.shared.snapshot()

        let errorInfo: RemoteLogPayload.ErrorInfo?
        if entry.underlyingError != nil || entry.actualError != nil {
            errorInfo = RemoteLogPayload.ErrorInfo(
                type: entry.underlyingError.map { String(describing: type(of: $0)) },
                message: LogRedactor.redact(entry.humanReadableError ?? entry.actualError),
                stackTrace: LogRedactor.redact(entry.stackTrace),
                isFatal: false
            )
        } else {
            errorInfo = nil
        }

        let payload = RemoteLogPayload(
            deviceKey: DeviceInfoProvider.deviceKey,
            appName: DeviceInfoProvider.appName,
            appVersion: DeviceInfoProvider.appVersion,
            platform: DeviceInfoProvider.platform,
            osVersion: DeviceInfoProvider.osVersion,
            deviceModel: DeviceInfoProvider.deviceModel,
            sessionId: DeviceInfoProvider.sessionId,
            logId: UUID().uuidString,
            severity: entry.level.rawValue,
            timestamp: Self.timestampFormatter.string(from: entry.timestamp),
            message: LogRedactor.redact(entry.message) ?? entry.message,
            tag: tag,
            event: event.rawValue,
            context: entry.context?.mapValues { String(describing: $0) },
            error: errorInfo,
            network: .init(type: network.type, isOnline: network.isOnline)
        )

        #if DEBUG
        print("[RemoteLogDestination] submit \(event.rawValue): \(payload.message)")
        #endif
        uploader.submit(payload)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Reuses EventClassifier's module→feature grouping rather than a
    /// one-tag-per-file scheme, which would produce 100+ near-meaningless tags.
    private static func tag(forFile file: String) -> String {
        let path = file.lowercased()
        if path.contains("/login/") || path.contains("sessionmanager") { return "auth.login" }
        if path.contains("verifypin") || path.contains("otp") { return "auth.verify" }
        if path.contains("hl7syncqueue") || path.contains("unsyncedtransaction") { return "sync.transaction" }
        if path.contains("/faceauth/") || path.contains("face") { return "auth.face" }
        if path.contains("/scanning/") || path.contains("/ocr/") { return "scanning.pill" }
        if path.contains("hl7") { return "hl7.sync" }
        if path.contains("/history/") { return "history" }
        if path.contains("/settings/") || path.contains("/profile/") { return "settings.profile" }
        if path.contains("localdatasource") || path.contains("coredatamanager") { return "data.store" }
        if path.contains("runtimeunit") || path.contains("/config/") { return "security.keys" }
        return "app.general"
    }
}
