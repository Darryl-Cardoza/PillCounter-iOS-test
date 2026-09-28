import Testing
import Foundation
@testable import PillCounter

private final class RecordingHTTPClient: RemoteLogSending {
    private let lock = NSLock()
    private var _sent: [RemoteLogPayload] = []
    var sent: [RemoteLogPayload] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }
    func send(_ payload: RemoteLogPayload) {
        lock.lock()
        _sent.append(payload)
        lock.unlock()
    }
}

@Suite(.serialized)
struct RemoteLogDestinationTests {
    @Test func shipsErrorLevelEntries() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(httpClient: client)
        let entry = LogEntry(level: .error, file: "/Features/Scanning/BarcodeAndQRDecoder.swift",
                              function: "f", line: 1, message: "Scan failed")
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.count == 1)
        #expect(client.sent.first?.event == "SCAN_FAILED")
    }

    @Test func doesNotShipWarnInfoDebugVerbose() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(httpClient: client)
        for level: LogLevel in [.warn, .info, .debug, .verbose] {
            let entry = LogEntry(level: level, file: "/f.swift", function: "f", line: 1, message: "m")
            destination.write(entry, formatted: "irrelevant")
        }
        #expect(client.sent.isEmpty)
    }

    @Test func remoteGateIgnoresGlobalMinimumLogLevel() {
        let previous = LoggerConfig.minimumLogLevel
        LoggerConfig.minimumLogLevel = .verbose
        defer { LoggerConfig.minimumLogLevel = previous }

        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(httpClient: client)
        let warnEntry = LogEntry(level: .warn, file: "/f.swift", function: "f", line: 1, message: "m")
        destination.write(warnEntry, formatted: "irrelevant")
        #expect(client.sent.isEmpty)
    }

    @Test func redactsMessageBeforeSending() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(httpClient: client)
        let entry = LogEntry(level: .error, file: "/f.swift", function: "f", line: 1,
                              message: "contact jane.doe@example.com about scan failure")
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.first?.message.contains("[REDACTED_EMAIL]") == true)
    }

    @Test func explicitEventOnEntryWinsOverClassifier() {
        let client = RecordingHTTPClient()
        let destination = RemoteLogDestination(httpClient: client)
        let entry = LogEntry(level: .error, file: "/Features/Scanning/BarcodeAndQRDecoder.swift",
                              function: "f", line: 1, message: "Scan failed", event: .dispenseCount)
        destination.write(entry, formatted: "irrelevant")
        #expect(client.sent.first?.event == "DISPENSE_COUNT")
    }
}
