import Testing
import Foundation
@testable import PillCounter

private final class MockLogDestination: LogDestination {
    private let lock = NSLock()
    private var _written: [String] = []
    private var _entries: [LogEntry] = []
    var written: [String] {
        lock.lock(); defer { lock.unlock() }
        return _written
    }
    var entries: [LogEntry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }
    func write(_ entry: LogEntry, formatted: String) {
        lock.lock()
        _written.append(formatted)
        _entries.append(entry)
        lock.unlock()
    }
}

@Suite(.serialized)
struct AppLoggerTests {
    @Test func errorLevelPassesDefaultMinimumLevel() {
        let mock = MockLogDestination()
        let queue = DispatchQueue(label: "test.applogger.1")
        let logger = AppLogger(destinations: [mock], queue: queue)

        logger.error("something failed")
        queue.sync {}

        #expect(mock.written.count == 1)
        #expect(mock.written.first?.contains("Level: ERROR") == true)
    }

    @Test func warnLevelIsDroppedByDefaultMinimumLevel() {
        let mock = MockLogDestination()
        let queue = DispatchQueue(label: "test.applogger.2")
        let logger = AppLogger(destinations: [mock], queue: queue)

        logger.warn("something suspicious")
        queue.sync {}

        #expect(mock.written.isEmpty)
    }

    @Test func errorCapturesUnderlyingErrorTranslationAndStackTrace() {
        let mock = MockLogDestination()
        let queue = DispatchQueue(label: "test.applogger.3")
        let logger = AppLogger(destinations: [mock], queue: queue)

        logger.error("request failed", error: URLError(.timedOut))
        queue.sync {}

        let output = mock.written.first ?? ""
        #expect(output.contains("Human Readable Error:"))
        #expect(output.contains("The request timed out"))
        #expect(output.contains("Actual Error:"))
        #expect(output.contains("Stack Trace:"))
    }

    @Test func cancellationErrorIsLoggedAtDebugNotError() {
        let mock = MockLogDestination()
        let queue = DispatchQueue(label: "test.applogger.4")
        let logger = AppLogger(destinations: [mock], queue: queue)
        let previousLevel = LoggerConfig.minimumLogLevel
        LoggerConfig.minimumLogLevel = .verbose
        defer { LoggerConfig.minimumLogLevel = previousLevel }

        logger.error("operation ended", error: CancellationError())
        queue.sync {}

        #expect(mock.written.first?.contains("Level: DEBUG") == true)
    }

    @Test func sessionMarkerBypassesMinimumLogLevel() {
        let mock = MockLogDestination()
        let queue = DispatchQueue(label: "test.applogger.marker")
        let logger = AppLogger(destinations: [mock], queue: queue)

        logger.info("Session started", event: .sessionStarted, context: ["reason": "logout"])
        logger.info("ordinary info")
        queue.sync {}

        #expect(mock.written.count == 1)
        #expect(mock.written.first?.contains("Session started") == true)
    }

    @Test func unrecognizedErrorPreservesOriginalErrorTextAlongsideGenericMessage() {
        struct CustomError: Error, CustomStringConvertible {
            var description: String { "CustomError(code: 42)" }
        }
        let mock = MockLogDestination()
        let queue = DispatchQueue(label: "test.applogger.5")
        let logger = AppLogger(destinations: [mock], queue: queue)

        logger.error("unexpected failure", error: CustomError())
        queue.sync {}

        let output = mock.written.first ?? ""
        #expect(output.contains("An unexpected error occurred."))
        #expect(output.contains("CustomError(code: 42)"))
    }
}
