import Foundation

public protocol LogDestination {
    func write(_ formatted: String)
}
