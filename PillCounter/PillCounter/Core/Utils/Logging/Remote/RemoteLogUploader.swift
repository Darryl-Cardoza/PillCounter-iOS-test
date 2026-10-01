import UIKit

protocol RemoteLogSubmitting {
    func submit(_ payload: RemoteLogPayload)
}

/// Online → send now (retrying a retryable failure a couple of times), never
/// touching the file unless it still fails. Offline, or once retries are
/// exhausted, the payload is queued in the log file and replayed by `flush()`.
final class RemoteLogUploader: RemoteLogSubmitting, @unchecked Sendable {
    static let shared: RemoteLogUploader = {
        let uploader = RemoteLogUploader()
        NetworkStatusProvider.shared.onBecameOnline = {
            uploader.resetBackoff()
            uploader.flushWithBackgroundTime()
        }
        return uploader
    }()

    private static let backoff: TimeInterval = 60

    private let client: RemoteLogDelivering
    private let file: LogFile
    private let isOnline: () -> Bool
    private let retryDelays: [Duration]
    private let lock = NSLock()
    private var flushing = false
    private var flushScheduled = false
    private var retryAfter = Date.distantPast

    init(
        client: RemoteLogDelivering = RemoteLogHTTPClient(),
        file: LogFile = .shared,
        isOnline: @escaping () -> Bool = { NetworkStatusProvider.shared.snapshot().isOnline },
        retryDelays: [Duration] = [.seconds(2), .seconds(5)]
    ) {
        self.client = client
        self.file = file
        self.isOnline = isOnline
        self.retryDelays = retryDelays
    }

    func submit(_ payload: RemoteLogPayload) {
        guard let body = try? JSONEncoder().encode(payload) else { return }
        guard canSend else {
            #if DEBUG
            print("[RemoteLogUploader] QUEUED, not sent — offline or in backoff")
            #endif
            file.appendPending(body)
            return
        }
        Task.detached(priority: .background) {
            await self.withBackgroundTime { await self.deliverOrQueue(body) }
        }
    }

    /// Entry point for triggers (launch/foreground/backgrounding/connectivity).
    func flushWithBackgroundTime() {
        Task.detached(priority: .background) {
            await self.withBackgroundTime { await self.flush() }
        }
    }

    /// Keeps the process alive (up to iOS's grace period) so a send started
    /// just before suspension finishes instead of being cut off mid-request.
    private func withBackgroundTime(_ work: () async -> Void) async {
        let end = await Self.beginBackgroundTask()
        await work()
        await end()
    }

    @MainActor
    private static func beginBackgroundTask() -> @MainActor () -> Void {
        var id = UIBackgroundTaskIdentifier.invalid
        let finish = {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
        id = UIApplication.shared.beginBackgroundTask(withName: "log-upload") { finish() }
        return finish
    }

    func deliverOrQueue(_ body: Data) async {
        var result = await client.deliver(body)
        for delay in retryDelays where result == .retry {
            try? await Task.sleep(for: delay)
            result = await client.deliver(body)
        }
        switch result {
        case .retry:
            noteFailure()
            file.appendPending(body)
        case .unauthorized:
            file.appendPending(body)
        case .delivered:
            await flush()
        case .drop:
            break
        }
    }

    func flush() async {
        guard canSend, beginFlush() else { return }
        defer { endFlush() }

        var done = Set<String>()
        for line in file.pendingLines() {
            guard canSend else { break }
            switch await client.deliver(Data(line.utf8)) {
            case .delivered, .drop: done.insert(line)
            case .retry: noteFailure(); return finish(done)
            case .unauthorized: return finish(done)
            }
        }
        finish(done)
    }

    // MARK: - State

    private var canSend: Bool {
        lock.lock(); defer { lock.unlock() }
        return isOnline() && Date() >= retryAfter
    }

    private func finish(_ done: Set<String>) {
        if !done.isEmpty { file.compact(removing: done) }
    }

    private func beginFlush() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if flushing { return false }
        flushing = true
        return true
    }

    private func endFlush() {
        lock.lock(); flushing = false; lock.unlock()
    }

    /// Backs off, then replays the queue once the backoff ends — otherwise a
    /// queued log would wait for the next launch/foreground/connectivity event.
    private func noteFailure() {
        lock.lock()
        retryAfter = Date().addingTimeInterval(Self.backoff)
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        guard schedule else { return }
        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(Self.backoff))
            self.clearFlushScheduled()
            await self.flush()
        }
    }

    private func clearFlushScheduled() {
        lock.lock(); flushScheduled = false; lock.unlock()
    }

    func resetBackoff() {
        lock.lock(); retryAfter = .distantPast; lock.unlock()
    }
}
