import Foundation

public final class AppLogger {
    public static let shared = AppLogger()

    private let destinations: [LogDestination]
    private let queue: DispatchQueue

    public init(
        destinations: [LogDestination]? = nil,
        queue: DispatchQueue = DispatchQueue(label: "com.pillcounter.applogger")
    ) {
        #if DEBUG
        self.destinations = destinations ?? [ConsoleLogDestination(), RemoteLogDestination()]
        #else
        self.destinations = destinations ?? [RemoteLogDestination()]
        #endif
        self.queue = queue
    }

    public func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .verbose, message: message, error: nil, event: nil, context: nil, file: file, function: function, line: line)
    }

    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message: message, error: nil, event: nil, context: nil, file: file, function: function, line: line)
    }

    public func info(
        _ message: String,
        event: LogEvent? = nil,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, error: nil, event: event, context: context, file: file, function: function, line: line)
    }

    public func warn(
        _ message: String,
        event: LogEvent? = nil,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warn, message: message, error: nil, event: event, context: context, file: file, function: function, line: line)
    }

    public func error(
        _ message: String,
        error underlyingError: Error? = nil,
        event: LogEvent? = nil,
        context: [String: Any]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message, error: underlyingError, event: event, context: context, file: file, function: function, line: line)
    }

    private func log(
        level: LogLevel,
        message: String,
        error underlyingError: Error?,
        event: LogEvent?,
        context: [String: Any]?,
        file: String,
        function: String,
        line: Int
    ) {
        let effectiveLevel: LogLevel
        if level == .error, let underlyingError, isCancellation(underlyingError) {
            effectiveLevel = .debug
        } else {
            effectiveLevel = level
        }

        guard effectiveLevel >= LoggerConfig.minimumLogLevel || event == .sessionStarted else { return }

        let humanReadable = underlyingError.map { ErrorTranslator.translate($0) }
        let actual = underlyingError.map { "\(type(of: $0)): \($0)" }

        let entry = LogEntry(
            level: effectiveLevel,
            file: file,
            function: function,
            line: line,
            message: message,
            humanReadableError: humanReadable,
            actualError: actual,
            underlyingError: underlyingError,
            event: event,
            context: context
        )
        let formatted = LogFormatter.format(entry)
        let destinations = self.destinations

        queue.async {
            for destination in destinations {
                destination.write(entry, formatted: formatted)
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
