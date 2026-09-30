import Foundation

public protocol LogDestination {
    func write(_ entry: LogEntry, formatted: String)
}

#if DEBUG
struct ConsoleLogDestination: LogDestination {
    func write(_ entry: LogEntry, formatted: String) { print(formatted) }
}
#endif
