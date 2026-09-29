import Testing
import Foundation
@testable import PillCounter

private final class CapturingDestination: LogDestination {
    private let lock = NSLock()
    private var _entries: [LogEntry] = []
    var entries: [LogEntry] { lock.lock(); defer { lock.unlock() }; return _entries }
    func write(_ entry: LogEntry, formatted: String) {
        lock.lock(); _entries.append(entry); lock.unlock()
    }
}

private final class RecordingUploader: RemoteLogSubmitting {
    private let lock = NSLock()
    private var _sent: [RemoteLogPayload] = []
    var sent: [RemoteLogPayload] { lock.lock(); defer { lock.unlock() }; return _sent }
    func submit(_ payload: RemoteLogPayload) { lock.lock(); _sent.append(payload); lock.unlock() }
}

private struct StubHealthRepository: HealthRepositoryProtocol {
    let result: Result<HealthResponse, Error>
    func checkHealth() async throws -> HealthResponse { try result.get() }
}

private struct ServerDown: Error {}

private func response(isHealthy: Bool?, checks: [String: HealthCheckDetail]? = nil) -> HealthResponse {
    HealthResponse(
        status: 200, isSuccess: true, message: nil, token: nil,
        data: HealthData(isHealthy: isHealthy, checks: checks, checkedAt: "2026-09-29T10:00:00Z")
    )
}

private func check(_ healthy: Bool?, detail: String? = nil) -> HealthCheckDetail {
    HealthCheckDetail(isHealthy: healthy, latencyMs: 12, detail: detail)
}

@MainActor
@Suite(.serialized)
struct UserViewModelHealthCheckTests {

    private struct Harness {
        let viewModel: UserViewModel
        let destination: CapturingDestination
        let queue: DispatchQueue

        var errorEntries: [LogEntry] {
            queue.sync {}
            return destination.entries.filter { $0.level == .error }
        }
    }

    private func makeHarness(_ result: Result<HealthResponse, Error>,
                             destinations: [LogDestination]? = nil) -> Harness {
        let destination = CapturingDestination()
        let queue = DispatchQueue(label: "test.health.\(UUID().uuidString)")
        let logger = AppLogger(destinations: destinations ?? [destination], queue: queue)
        let viewModel = UserViewModel(
            userLocalDB: MockUserDataSource(),
            healthRepo: StubHealthRepository(result: result),
            logger: logger
        )
        return Harness(viewModel: viewModel, destination: destination, queue: queue)
    }

    /// OfflineSessionManager and its flag live in shared singletons; start each
    /// test online and put the original state back afterwards.
    private func withCleanOfflineState(_ body: () async -> Void) async {
        let manager = OfflineSessionManager.shared
        let wasOffline = manager.isOffline
        manager.markHealthy(checkedAt: nil)
        await body()
        manager.markHealthy(checkedAt: nil)
        if wasOffline { manager.markOffline() }
    }

    @Test func healthyResponseLogsNothingAndStaysOnline() async {
        await withCleanOfflineState {
            let harness = makeHarness(.success(response(isHealthy: true, checks: ["db": check(true)])))
            let healthy = await harness.viewModel.checkServerHealth()
            #expect(healthy)
            #expect(harness.errorEntries.isEmpty)
            #expect(!OfflineSessionManager.shared.isOffline)
        }
    }

    @Test func unhealthyResponseLogsErrorNamingOnlyTheFailedChecks() async {
        await withCleanOfflineState {
            let checks = ["db": check(false, detail: "connection refused"), "cache": check(true), "queue": check(nil)]
            let harness = makeHarness(.success(response(isHealthy: false, checks: checks)))
            let healthy = await harness.viewModel.checkServerHealth()

            #expect(!healthy)
            #expect(OfflineSessionManager.shared.isOffline)
            let entries = harness.errorEntries
            #expect(entries.count == 1)
            #expect(entries.first?.event == .healthCheckFailed)
            #expect(entries.first?.context?["failed_checks"] as? String == "db,queue")
            let details = entries.first?.context?["details"] as? String ?? ""
            #expect(details.contains("db: connection refused"))
            #expect(!details.contains("cache"))
        }
    }

    @Test func unhealthyDetailIsRedactedBeforeItIsLogged() async {
        await withCleanOfflineState {
            let checks = ["smtp": check(false, detail: "auth failed for admin@example.com")]
            let harness = makeHarness(.success(response(isHealthy: false, checks: checks)))
            _ = await harness.viewModel.checkServerHealth()

            let details = harness.errorEntries.first?.context?["details"] as? String ?? ""
            #expect(details.contains("[REDACTED_EMAIL]"))
            #expect(!details.contains("admin@example.com"))
        }
    }

    @Test func unhealthyWithoutCheckDetailsStillLogs() async {
        await withCleanOfflineState {
            let harness = makeHarness(.success(response(isHealthy: false, checks: nil)))
            let healthy = await harness.viewModel.checkServerHealth()

            #expect(!healthy)
            #expect(harness.errorEntries.count == 1)
            #expect(harness.errorEntries.first?.context?["failed_checks"] as? String == "")
        }
    }

    @Test func missingIsHealthyFlagIsTreatedAsUnhealthyAndLogged() async {
        await withCleanOfflineState {
            let harness = makeHarness(.success(response(isHealthy: nil)))
            let healthy = await harness.viewModel.checkServerHealth()

            #expect(!healthy)
            #expect(OfflineSessionManager.shared.isOffline)
            #expect(harness.errorEntries.count == 1)
        }
    }

    @Test func requestFailureLogsErrorWithUnderlyingErrorAndGoesOffline() async {
        await withCleanOfflineState {
            let harness = makeHarness(.failure(ServerDown()))
            let healthy = await harness.viewModel.checkServerHealth()

            #expect(!healthy)
            #expect(OfflineSessionManager.shared.isOffline)
            let entries = harness.errorEntries
            #expect(entries.count == 1)
            #expect(entries.first?.event == .healthCheckFailed)
            #expect(entries.first?.underlyingError is ServerDown)
        }
    }

    @Test func cancelledRequestIsNotLoggedAsAnError() async {
        await withCleanOfflineState {
            let harness = makeHarness(.failure(CancellationError()))
            let healthy = await harness.viewModel.checkServerHealth()

            #expect(!healthy)
            #expect(harness.errorEntries.isEmpty)
        }
    }

    @Test func unhealthyLogReachesTheRemotePayloadAsHealthCheckFailed() async {
        await withCleanOfflineState {
            let uploader = RecordingUploader()
            let queue = DispatchQueue(label: "test.health.remote")
            let logger = AppLogger(destinations: [RemoteLogDestination(uploader: uploader, isLoggedIn: { true })], queue: queue)
            let viewModel = UserViewModel(
                userLocalDB: MockUserDataSource(),
                healthRepo: StubHealthRepository(
                    result: .success(response(isHealthy: false, checks: ["db": check(false, detail: "down")]))
                ),
                logger: logger
            )

            _ = await viewModel.checkServerHealth()
            queue.sync {}

            #expect(uploader.sent.count == 1)
            #expect(uploader.sent.first?.event == "HEALTH_CHECK_FAILED")
            #expect(uploader.sent.first?.severity == LogLevel.error.rawValue)
            #expect(uploader.sent.first?.context?["failed_checks"] == "db")
        }
    }
}
