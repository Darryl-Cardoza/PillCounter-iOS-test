import Testing
import Foundation
@testable import PillCounter

private final class RecordingHTTPClient: RemoteLogSubmitting {
    private let lock = NSLock()
    private var _sent: [RemoteLogPayload] = []
    var sent: [RemoteLogPayload] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }
    func submit(_ payload: RemoteLogPayload) {
        lock.lock()
        _sent.append(payload)
        lock.unlock()
    }
}

@Suite(.serialized)
struct RemoteLogDestinationTests {
    @Test func shipsErrorLevelEntries() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { true })
        let entry = LogEntry(level: .error, file: "/Features/Scanning/BarcodeAndQRDecoder.swift",
                              function: "f", line: 1, message: "Scan failed")
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.count == 1)
        #expect(client.sent.first?.event == "SCAN_FAILED")
    }

    @Test func dropsEverythingWhileLoggedOut() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { false })
        destination.write(LogEntry(level: .error, file: "/f.swift", function: "f", line: 1, message: "m"), formatted: "irrelevant")
        destination.write(LogEntry(level: .info, file: "/f.swift", function: "f", line: 1, message: "Session started",
                                   event: .sessionStarted), formatted: "irrelevant")
        #expect(client.sent.isEmpty)
    }

    @Test func loggedOutEntriesNeverReachTheQueueFile() throws {
        struct NoopClient: RemoteLogDelivering {
            func deliver(_ body: Data) async -> RemoteLogDeliveryResult { .delivered }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = LogFile(fileURL: url)
        let uploader = RemoteLogUploader(client: NoopClient(), file: file, isOnline: { false })
        let destination = RemoteLogDestination(uploader: uploader, isLoggedIn: { false })
        destination.write(LogEntry(level: .error, file: "/f.swift", function: "f", line: 1, message: "m"), formatted: "irrelevant")
        #expect(file.pendingLines().isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8).isEmpty)
    }

    @Test func doesNotShipWarnInfoDebugVerbose() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { true })
        for level: LogLevel in [.warn, .info, .debug, .verbose] {
            let entry = LogEntry(level: level, file: "/f.swift", function: "f", line: 1, message: "m")
            destination.write(entry, formatted: "irrelevant")
        }
        #expect(client.sent.isEmpty)
    }

    @Test func shipsSessionStartedMarkerBelowErrorLevel() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { true })
        let entry = LogEntry(level: .info, file: "/f.swift", function: "f", line: 1, message: "Session started",
                              event: .sessionStarted, context: ["reason": "login", "previous_session_id": "old"])
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.first?.event == "SESSION_STARTED")
        #expect(client.sent.first?.context?["previous_session_id"] == "old")
    }

    @Test func remoteGateIgnoresGlobalMinimumLogLevel() {
        let previous = LoggerConfig.minimumLogLevel
        LoggerConfig.minimumLogLevel = .verbose
        defer { LoggerConfig.minimumLogLevel = previous }

        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { true })
        let warnEntry = LogEntry(level: .warn, file: "/f.swift", function: "f", line: 1, message: "m")
        destination.write(warnEntry, formatted: "irrelevant")
        #expect(client.sent.isEmpty)
    }

    @Test func redactsMessageBeforeSending() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { true })
        let entry = LogEntry(level: .error, file: "/f.swift", function: "f", line: 1,
                              message: "contact jane.doe@example.com about scan failure")
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.first?.message.contains("[REDACTED_EMAIL]") == true)
    }

    @Test func explicitEventOnEntryWinsOverClassifier() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(uploader: client, isLoggedIn: { true })
        let entry = LogEntry(level: .error, file: "/Features/Scanning/BarcodeAndQRDecoder.swift",
                              function: "f", line: 1, message: "Scan failed", event: .dispenseCount)
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.first?.event == "DISPENSE_COUNT")
    }
}
