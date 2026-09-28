import Network
import Foundation

/// Net-new, scoped to remote log shipping only — the app has no general-purpose
/// reachability monitor (the only existing NWPathMonitor is private to
/// Hl7ServiceManager's local PMS discovery and isn't reusable here).
public final class NetworkStatusProvider {
    public static let shared = NetworkStatusProvider()

    public struct Snapshot {
        public let type: String
        public let isOnline: Bool
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pillcounter.networkstatus")
    private let lock = NSLock()
    private var current = Snapshot(type: "unknown", isOnline: false)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let snapshot = Snapshot(type: Self.connectionType(path), isOnline: path.status == .satisfied)
            self.lock.lock()
            self.current = snapshot
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    private static func connectionType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "unknown"
    }
}
