import Foundation

public struct LogEntry {
    public let timestamp: Date
    public let level: LogLevel
    public let file: String
    public let function: String
    public let line: Int
    public let message: String
    public let humanReadableError: String?
    public let actualError: String?
    public let stackTrace: String?
    /// The original error, kept alongside its translated string forms above —
    /// EventClassifier needs the real type (URLError code, DecodingError, etc.)
    /// to classify accurately; a string can't be pattern-matched reliably.
    public let underlyingError: Error?
    public let event: LogEvent?
    public let context: [String: Any]?

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        file: String,
        function: String,
        line: Int,
        message: String,
        humanReadableError: String? = nil,
        actualError: String? = nil,
        stackTrace: String? = nil,
        underlyingError: Error? = nil,
        event: LogEvent? = nil,
        context: [String: Any]? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.file = file
        self.function = function
        self.line = line
        self.message = message
        self.humanReadableError = humanReadableError
        self.actualError = actualError
        self.stackTrace = stackTrace
        self.underlyingError = underlyingError
        self.event = event
        self.context = context
    }
}
