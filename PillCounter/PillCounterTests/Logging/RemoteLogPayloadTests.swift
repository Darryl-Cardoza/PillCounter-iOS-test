import Testing
import Foundation
@testable import PillCounter

struct RemoteLogPayloadTests {
    @Test func encodesExpectedTopLevelKeys() throws {
        let payload = RemoteLogPayload(
            deviceKey: "device-1", appName: "PillCounter", appVersion: "1.0", platform: "iOS",
            osVersion: "17.0", deviceModel: "iPhone15,3", sessionId: "session-1", logId: "log-1",
            severity: 4, timestamp: "2026-09-28T00:00:00.000Z", message: "Scan failed",
            tag: "scanning.barcode", event: "SCAN_TIMEOUT", context: ["attempt": "2"],
            error: .init(type: "URLError", message: "timed out", stackTrace: "...", isFatal: false),
            network: .init(type: "cellular", isOnline: true)
        )
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["device_key"] as? String == "device-1")
        #expect(json?["log_id"] as? String == "log-1")
        #expect(json?["event"] as? String == "SCAN_TIMEOUT")
        #expect((json?["error"] as? [String: Any])?["stack_trace"] as? String == "...")
        #expect((json?["network"] as? [String: Any])?["is_online"] as? Bool == true)
    }

    @Test func encodesWithNilErrorAndContext() throws {
        let payload = RemoteLogPayload(
            deviceKey: "d", appName: "a", appVersion: "1", platform: "iOS", osVersion: "17",
            deviceModel: "iPhone15,3", sessionId: "s", logId: "l", severity: 4,
            timestamp: "2026-09-28T00:00:00.000Z", message: "m", tag: "t", event: "UNKNOWN_ERROR",
            context: nil, error: nil, network: .init(type: "wifi", isOnline: true)
        )
        let data = try JSONEncoder().encode(payload)
        #expect(!data.isEmpty)
    }
}
