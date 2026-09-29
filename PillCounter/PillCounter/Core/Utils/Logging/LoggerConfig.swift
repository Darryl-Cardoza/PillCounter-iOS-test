import Foundation

/// Single centralized switch for what gets written to the log file.
/// No module decides its own log level — this is the one place that does.
public enum LoggerConfig {
    public static var minimumLogLevel: LogLevel = .error

    static let maxPendingEntries = 2_000
    static let pendingMaxAge: TimeInterval = 7 * 24 * 60 * 60
    static let maxLogFileBytes = 5 * 1024 * 1024
}
