import Foundation

final class RemoteLogDestination: LogDestination {
    private let uploader: RemoteLogSubmitting
    private let isLoggedIn: () -> Bool

    init(
        uploader: RemoteLogSubmitting = RemoteLogUploader.shared,
        isLoggedIn: @escaping () -> Bool = { AppStorageManager.shared.isLoggedIn }
    ) {
        self.uploader = uploader
        self.isLoggedIn = isLoggedIn
    }

    func write(_ entry: LogEntry, formatted: String) {
        guard entry.level >= .error || entry.event == .sessionStarted else { return }
        // /mobile/logs requires the access token, which only exists after login. The
        // session marker is exempt: logout wipes the token before this async write
        // runs, and the uploader queues it until the next login.
        guard isLoggedIn() || entry.event == .sessionStarted else { return }

        let event = entry.event ?? EventClassifier.classify(entry)
        let tag = Self.tag(forFile: entry.file)
        let network = NetworkStatusProvider.shared.snapshot()

        let errorInfo: RemoteLogPayload.ErrorInfo?
        if entry.underlyingError != nil || entry.actualError != nil {
            errorInfo = RemoteLogPayload.ErrorInfo(
                type: entry.underlyingError.map { String(describing: type(of: $0)) },
                message: LogRedactor.redact(entry.actualError ?? entry.humanReadableError),
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
            severity: max(entry.level.rawValue - 1, 0),
            timestamp: Self.timestampFormatter.string(from: entry.timestamp),
            message: Self.message(for: entry),
            tag: tag,
            event: event.rawValue,
            context: ["file": Self.fileName(entry), "method": Self.methodName(entry)]
                .merging(entry.context?.mapValues { LogRedactor.redact(String(describing: $0)) ?? "" } ?? [:]) { _, custom in custom },
            error: errorInfo,
            network: .init(type: network.type, isOnline: network.isOnline)
        )

        #if DEBUG
        print("[RemoteLogDestination] submit \(event.rawValue): \(payload.message)")
        #endif
        uploader.submit(payload)
    }

    private static func fileName(_ entry: LogEntry) -> String {
        (entry.file as NSString).lastPathComponent
    }

    private static func methodName(_ entry: LogEntry) -> String {
        String(entry.function.prefix { $0 != "(" })
    }

    /// "File.swift -> ClassName -> method -> error", the same shape Android sends.
    /// Swift has no runtime caller-class, so the file's base name stands in for it.
    private static func message(for entry: LogEntry) -> String {
        let file = fileName(entry)
        let detail = [entry.message, entry.humanReadableError].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " -> ")
        let redacted = LogRedactor.redact(detail) ?? detail
        return "\(file) -> \((file as NSString).deletingPathExtension) -> \(methodName(entry)) -> \(redacted)"
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// One tag per feature module (see LogModule), not per file.
    private static func tag(forFile file: String) -> String {
        switch LogModule(file: file) {
        case .login: return "auth.login"
        case .verify: return "auth.verify"
        case .syncQueue: return "sync.transaction"
        case .face: return "auth.face"
        case .scanning: return "scanning.pill"
        case .hl7: return "hl7.sync"
        case .history: return "history"
        case .settings: return "settings.profile"
        case .dataStore: return "data.store"
        case .security: return "security.keys"
        case .other: return "app.general"
        }
    }
}
