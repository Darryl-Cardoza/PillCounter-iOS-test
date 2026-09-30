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
    private var _onBecameOnline: (() -> Void)?

    /// Fires on every offline→online transition, including the first path update at launch.
    var onBecameOnline: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onBecameOnline }
        set { lock.lock(); _onBecameOnline = newValue; lock.unlock() }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let snapshot = Snapshot(type: Self.connectionType(path), isOnline: path.status == .satisfied)
            self.lock.lock()
            let wasOnline = self.current.isOnline
            self.current = snapshot
            let callback = self._onBecameOnline
            self.lock.unlock()
            if snapshot.isOnline && !wasOnline { callback?() }
        }
        monitor.start(queue: queue)
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    private static func connectionType(_ path: NWPath) -> String {
        if path.status != .satisfied { return "offline" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        return "unknown"
    }
}
