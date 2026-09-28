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

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        file: String,
        function: String,
        line: Int,
        message: String,
        humanReadableError: String? = nil,
        actualError: String? = nil,
        stackTrace: String? = nil
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
    }
}
