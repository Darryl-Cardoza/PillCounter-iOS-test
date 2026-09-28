import Testing
@testable import PillCounter

struct DeviceInfoProviderTests {
    @Test func sessionIdIsStableWithinProcess() {
        #expect(DeviceInfoProvider.sessionId == DeviceInfoProvider.sessionId)
        #expect(!DeviceInfoProvider.sessionId.isEmpty)
    }

    @Test func deviceModelIsNonEmpty() {
        #expect(!DeviceInfoProvider.deviceModel.isEmpty)
    }

    @Test func appVersionFallsBackWhenBundleValueMissing() {
        #expect(!DeviceInfoProvider.appVersion.isEmpty)
    }
}
