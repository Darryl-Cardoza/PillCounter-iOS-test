import Testing
@testable import PillCounter

struct NetworkStatusProviderTests {
    @Test func snapshotReturnsAKnownConnectionType() {
        let snapshot = NetworkStatusProvider.shared.snapshot()
        #expect(["wifi", "cellular", "offline", "unknown"].contains(snapshot.type))
    }

    @Test func onBecameOnlineCallbackCanBeSetAndCleared() {
        let provider = NetworkStatusProvider.shared
        let previous = provider.onBecameOnline
        defer { provider.onBecameOnline = previous }

        provider.onBecameOnline = {}
        #expect(provider.onBecameOnline != nil)
        provider.onBecameOnline = nil
        #expect(provider.onBecameOnline == nil)
    }
}
