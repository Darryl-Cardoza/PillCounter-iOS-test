import Testing
import Foundation
@testable import PillCounter

private final class OnlineSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = true
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

private final class FakeClient: RemoteLogDelivering, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [RemoteLogDeliveryResult]
    private var _bodies: [String] = []
    var delay: Duration?
    var onDeliver: (() -> Void)?
    var bodies: [String] { lock.lock(); defer { lock.unlock() }; return _bodies }
    init(_ results: [RemoteLogDeliveryResult]) { self.results = results }
    func deliver(_ body: Data) async -> RemoteLogDeliveryResult {
        if let delay { try? await Task.sleep(for: delay) }
        lock.lock()
        _bodies.append(String(decoding: body, as: UTF8.self))
        let result = results.isEmpty ? RemoteLogDeliveryResult.delivered : results.removeFirst()
        lock.unlock()
        onDeliver?()
        return result
    }
}

private func body(_ id: String) -> Data {
    let stamp = ISO8601DateFormatter().string(from: Date())
    return Data("{\"log_id\":\"\(id)\",\"timestamp\":\"\(stamp)\"}".utf8)
}

private func makeFile() -> (LogFile, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    return (LogFile(fileURL: url), url)
}

private func payload() -> RemoteLogPayload {
    RemoteLogPayload(
        deviceKey: "d", appName: "PillCounter", appVersion: "1", platform: "iOS", osVersion: "17",
        deviceModel: "m", sessionId: "s", logId: "l", severity: 4,
        timestamp: ISO8601DateFormatter().string(from: Date()), message: "m", tag: "t",
        event: "UNKNOWN_ERROR", context: nil, error: nil, network: .init(type: "wifi", isOnline: false)
    )
}

@Suite(.serialized)
struct RemoteLogUploaderTests {
    @Test func offlineSubmitQueuesWithoutSending() {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { false }, retryDelays: [])
        uploader.submit(payload())
        #expect(file.pendingLines().count == 1)
        #expect(client.bodies.isEmpty)
    }

    @Test func identicalSubmitsWithinWindowCollapseToOne() {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let uploader = RemoteLogUploader(client: FakeClient([]), file: file, isOnline: { false }, retryDelays: [])
        uploader.submit(payload()); uploader.submit(payload())
        #expect(file.pendingLines().count == 1)
    }

    @Test func flushSkipsLinesQueuedByAnotherUser() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let stamp = ISO8601DateFormatter().string(from: Date())
        file.appendPending(Data("{\"log_id\":\"a\",\"timestamp\":\"\(stamp)\",\"context\":{\"user_id\":\"A\"}}".utf8))
        file.appendPending(Data("{\"log_id\":\"b\",\"timestamp\":\"\(stamp)\",\"context\":{\"user_id\":\"B\"}}".utf8))
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [], currentUserId: { "B" })
        await uploader.flush()
        #expect(client.bodies.count == 1 && client.bodies[0].contains("\"b\""))
        #expect(file.pendingLines().count == 1)
    }

    @Test func onlineDeliveryDoesNotTouchTheFile() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([.delivered])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.deliverOrQueue(body("a"))
        #expect(client.bodies.count == 1)
        #expect(file.pendingLines().isEmpty)
        #expect(((try? String(contentsOf: url, encoding: .utf8)) ?? "").isEmpty)
    }

    @Test func retryableFailureQueuesAndDropDiscards() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([.retry, .drop])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.deliverOrQueue(body("a"))
        #expect(file.pendingLines().count == 1)
        uploader.resetBackoff()
        await uploader.deliverOrQueue(body("b"))
        #expect(file.pendingLines().count == 1)
    }

    @Test func flushSendsOldestFirstAndRemovesDelivered() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("1")); file.appendPending(body("2")); file.appendPending(body("3"))
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies.count == 3)
        #expect(client.bodies[0].contains("\"1\"") && client.bodies[2].contains("\"3\""))
        #expect(file.pendingLines().isEmpty)
    }

    @Test func flushWhileOfflineSendsNothingAndKeepsQueue() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("1"))
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { false }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies.isEmpty)
        #expect(file.pendingLines().count == 1)
    }

    @Test func flushWithEmptyQueueSendsNothing() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies.isEmpty)
    }

    @Test func nonRetryableRejectionRemovesTheEntryAndContinues() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("1")); file.appendPending(body("2"))
        let client = FakeClient([.drop, .delivered])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies.count == 2)
        #expect(file.pendingLines().isEmpty)
    }

    @Test func backoffBlocksFlushUntilReset() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("1"))
        let client = FakeClient([.retry, .delivered])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies.count == 1)

        await uploader.flush()
        #expect(client.bodies.count == 1)
        #expect(file.pendingLines().count == 1)

        uploader.resetBackoff()
        await uploader.flush()
        #expect(client.bodies.count == 2)
        #expect(file.pendingLines().isEmpty)
    }

    @Test func successfulLiveSendDrainsTheQueue() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("old1")); file.appendPending(body("old2"))
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.deliverOrQueue(body("live"))
        #expect(client.bodies.count == 3)
        #expect(client.bodies[0].contains("live"))
        #expect(file.pendingLines().isEmpty)
    }

    @Test func liveSendFailureQueuesAndBlocksFurtherSendsUntilReset() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([.retry])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.deliverOrQueue(body("a"))
        await uploader.flush()
        #expect(client.bodies.count == 1)
        #expect(file.pendingLines().count == 1)
    }

    @Test func goingOfflineMidFlushStopsAndKeepsRemaining() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("1")); file.appendPending(body("2")); file.appendPending(body("3"))
        let online = OnlineSwitch()
        let client = FakeClient([])
        client.onDeliver = { online.value = client.bodies.count < 1 }
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { online.value })
        await uploader.flush()
        #expect(client.bodies.count == 1)
        let left = file.pendingLines()
        #expect(left.count == 2 && left[0].contains("\"2\""))
    }

    @Test func concurrentFlushesSendEachEntryOnce() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        for id in 1...5 { file.appendPending(body("\(id)")) }
        let client = FakeClient([])
        client.delay = .milliseconds(20)
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        async let first: Void = uploader.flush()
        async let second: Void = uploader.flush()
        _ = await (first, second)
        #expect(client.bodies.count == 5)
        #expect(file.pendingLines().isEmpty)
    }

    @Test func offlineSubmitWritesOneParseableLineWithMultilineMessage() throws {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let uploader = RemoteLogUploader(client: FakeClient([]), file: file, isOnline: { false })
        let multiline = RemoteLogPayload(
            deviceKey: "d", appName: "PillCounter", appVersion: "1", platform: "iOS", osVersion: "17",
            deviceModel: "m", sessionId: "s", logId: "l", severity: 4,
            timestamp: ISO8601DateFormatter().string(from: Date()), message: "line one\nline two", tag: "t",
            event: "UNKNOWN_ERROR", context: nil, error: nil, network: .init(type: "wifi", isOnline: false)
        )
        uploader.submit(multiline)

        let lines = file.pendingLines()
        #expect(lines.count == 1)
        let json = try JSONSerialization.jsonObject(
            with: Data(lines[0].utf8)) as? [String: Any]
        #expect(json?["message"] as? String == "line one\nline two")
    }

    @Test func flushSendsTheStoredJSONUnchanged() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let original = body("exact")
        file.appendPending(original)
        let client = FakeClient([])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies == [String(decoding: original, as: UTF8.self)])
    }

    @Test func liveSendRetriesThenDeliversWithoutTouchingTheFile() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([.retry, .retry, .delivered])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true },
                                         retryDelays: [.milliseconds(1), .milliseconds(1)])
        await uploader.deliverOrQueue(body("a"))
        #expect(client.bodies.count == 3)
        #expect(file.pendingLines().isEmpty)
    }

    @Test func liveSendQueuesOnlyAfterRetriesAreExhausted() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([.retry, .retry, .retry])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true },
                                         retryDelays: [.milliseconds(1), .milliseconds(1)])
        await uploader.deliverOrQueue(body("a"))
        #expect(client.bodies.count == 3)
        #expect(file.pendingLines().count == 1)
    }

    @Test func dropIsNeverRetriedOrQueued() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        let client = FakeClient([.drop])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true },
                                         retryDelays: [.milliseconds(1), .milliseconds(1)])
        await uploader.deliverOrQueue(body("a"))
        #expect(client.bodies.count == 1)
        #expect(file.pendingLines().isEmpty)
    }

    @Test func flushStopsAtFirstRetryableFailureAndKeepsRest() async {
        let (file, url) = makeFile(); defer { try? FileManager.default.removeItem(at: url) }
        file.appendPending(body("1")); file.appendPending(body("2")); file.appendPending(body("3"))
        let client = FakeClient([.delivered, .retry])
        let uploader = RemoteLogUploader(client: client, file: file, isOnline: { true }, retryDelays: [])
        await uploader.flush()
        #expect(client.bodies.count == 2)
        let left = file.pendingLines()
        #expect(left.count == 2 && left[0].contains("\"2\""))
    }
}
