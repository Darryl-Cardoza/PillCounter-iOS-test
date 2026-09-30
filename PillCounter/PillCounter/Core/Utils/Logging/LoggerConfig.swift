import Foundation

/// Single centralized switch for which log levels are emitted.
/// No module decides its own log level — this is the one place that does.
/// Remote shipping applies its own error-level floor regardless.
public enum LoggerConfig {
    #if DEBUG
    public static var minimumLogLevel: LogLevel = .debug
    #else
    public static var minimumLogLevel: LogLevel = .error
    #endif

    static let maxPendingEntries = 2_000
    static let pendingMaxAge: TimeInterval = 7 * 24 * 60 * 60
    static let maxLogFileBytes = 5 * 1024 * 1024
}
