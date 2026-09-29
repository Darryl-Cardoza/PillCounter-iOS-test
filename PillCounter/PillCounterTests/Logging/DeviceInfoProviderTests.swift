import Testing
@testable import PillCounter

@Suite(.serialized)
struct DeviceInfoProviderTests {
    @Test func sessionIdIsStableWithinProcess() {
        #expect(DeviceInfoProvider.sessionId == DeviceInfoProvider.sessionId)
        #expect(!DeviceInfoProvider.sessionId.isEmpty)
    }

    @Test func rotateSessionAppliesNewId() {
        let before = DeviceInfoProvider.sessionId
        let rotated = DeviceInfoProvider.rotateSession()
        #expect(rotated != before)
        #expect(DeviceInfoProvider.sessionId == rotated)
    }

    @Test func everyRotationProducesADistinctId() {
        let ids = (0..<20).map { _ in DeviceInfoProvider.rotateSession() }
        #expect(Set(ids).count == ids.count)
    }

    @Test func rotatingConcurrentlyNeverLeavesAnEmptyId() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { DeviceInfoProvider.rotateSession(); _ = DeviceInfoProvider.sessionId }
            }
        }
        #expect(!DeviceInfoProvider.sessionId.isEmpty)
    }

    @Test func deviceModelIsNonEmpty() {
        #expect(!DeviceInfoProvider.deviceModel.isEmpty)
    }

    @Test func appVersionFallsBackWhenBundleValueMissing() {
        #expect(!DeviceInfoProvider.appVersion.isEmpty)
    }
}
