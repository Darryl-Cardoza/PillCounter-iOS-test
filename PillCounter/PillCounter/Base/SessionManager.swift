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

        let storedExpiry = AppStorageManager.shared.tokenExpiryTimestamp ?? 0.0

        // Not expired yet (more than 5-minute buffer remaining)
        if storedExpiry > 0,
           Date().timeIntervalSince1970 < storedExpiry - 300 {
            return
        }

        await attemptRefresh()
    }

    // MARK: - Private

    private func handleUnauthorized() async {
        // Try to refresh first. If refresh also fails the session is truly gone.
        await attemptRefresh()
    }

    private func attemptRefresh() async {
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
