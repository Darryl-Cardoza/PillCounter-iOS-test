import Foundation

public protocol LogDestination {
    func write(_ entry: LogEntry, formatted: String)
}
