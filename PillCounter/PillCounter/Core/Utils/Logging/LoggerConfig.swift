import Foundation

/// Single centralized switch for what gets written to the log file.
/// No module decides its own log level — this is the one place that does.
public enum LoggerConfig {
    public static var minimumLogLevel: LogLevel = .error
}
