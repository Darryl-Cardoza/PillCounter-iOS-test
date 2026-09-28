import Testing
@testable import PillCounter

struct NetworkStatusProviderTests {
    @Test func snapshotReturnsAKnownConnectionType() {
        let snapshot = NetworkStatusProvider.shared.snapshot()
        #expect(["wifi", "cellular", "wired", "unknown"].contains(snapshot.type))
    }
}
