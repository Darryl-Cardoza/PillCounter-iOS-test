//
//  SessionManager.swift
//  PillCounter
//

import Foundation
import Combine

extension Notification.Name {
    static let sessionDidExpire = Notification.Name("sessionDidExpire")
    static let unauthorizedResponseReceived = Notification.Name("unauthorizedResponseReceived")
}

/// Centrally owns session-expiry logic.
/// - Fires `.sessionDidExpire` when the access token cannot be refreshed.
/// - Listens for `.unauthorizedResponseReceived` posted by BaseRepository on every 401.
@MainActor
final class SessionManager: ObservableObject {

    static let shared = SessionManager()

    @Published private(set) var isSessionExpired: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // Collapses concurrent refresh triggers (foreground check, dashboard
    // onAppear, and every in-flight request's 401 handler can all call this
    // around the same time) into a single in-flight `/auth/refresh` call —
    // this is what was flooding the endpoint with parallel requests.
    private var inFlightRefresh: Task<Void, Never>?

    private init() {
        NotificationCenter.default
            .publisher(for: .unauthorizedResponseReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleUnauthorized()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    /// Call when the app becomes active (scene phase → .active).
    /// Refreshes a token that is close to expiry; forces logout if refresh fails.
    func checkTokenOnForeground() async {
        guard AppStorageManager.shared.isLoggedIn else { return }
        _ = await refreshIfNeeded()
    }

    /// Refreshes the access token if it's missing or within 5 minutes of expiry.
    /// Shares the same in-flight guard as every other refresh trigger (foreground
    /// check, 401 handler) — concurrent callers all await one `/auth/refresh` call.
    /// Returns `true` when a refresh was actually attempted (regardless of outcome),
    /// so callers can decide whether to re-fetch remote data off the back of it.
    @discardableResult
    func refreshIfNeeded() async -> Bool {
        let storedExpiry = AppStorageManager.shared.tokenExpiryTimestamp ?? 0.0
        guard storedExpiry == 0.0 || Date().timeIntervalSince1970 > storedExpiry - 300 else {
            return false
        }
        await attemptRefresh()
        return true
    }

    // MARK: - Private

    private func handleUnauthorized() async {
        // Try to refresh first. If refresh also fails the session is truly gone.
        await attemptRefresh()
    }

    private func attemptRefresh() async {
        // Another caller's refresh is already in flight — wait for it instead
        // of firing a second concurrent /auth/refresh request.
        if let existing = inFlightRefresh {
            await existing.value
            return
        }

        let task = Task { await performRefresh() }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
    }

    private func performRefresh() async {
        guard let refreshToken = AppStorageManager.shared.refreshToken,
              !refreshToken.isEmpty else {
            markExpired()
            return
        }

        do {
            let result = try await UserRepository.shared.refreshToken(refreshToken: refreshToken)
            if result.isSuccess ?? false {
                AppStorageManager.shared.accessToken  = result.data?.accessToken ?? ""
                AppStorageManager.shared.refreshToken = result.data?.refreshToken ?? ""
                let expiresIn = TimeInterval(result.data?.expiresIn ?? 86400)
                AppStorageManager.shared.tokenExpiryTimestamp =
                    Date().addingTimeInterval(expiresIn).timeIntervalSince1970
            } else {
                markExpired()
            }
        } catch {
            markExpired()
        }
    }

    /// Call from any site that conclusively knows the session cannot be recovered.
    func triggerExpiry() {
        markExpired()
    }

    private func markExpired() {
        guard !isSessionExpired else { return }
        isSessionExpired = true
        NotificationCenter.default.post(name: .sessionDidExpire, object: nil)
    }

    /// Call after a successful login or explicit logout to reset state.
    func reset() {
        isSessionExpired = false
    }
}
