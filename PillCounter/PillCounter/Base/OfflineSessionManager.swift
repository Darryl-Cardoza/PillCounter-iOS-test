//
//  OfflineSessionManager.swift
//  PillCounter
//

import Foundation
import Combine

extension Notification.Name {
    /// Posted by BaseRepository.performRequest for any 5xx response or
    /// network-level failure that exhausts its retries.
    static let serverErrorResponseReceived = Notification.Name("serverErrorResponseReceived")
}

/// Centrally owns offline-mode state.
/// - Flips `isOffline` on a failed `/health` check, an auth/me 5xx, or any other
///   API call's exhausted-retry 5xx/network failure (via `.serverErrorResponseReceived`).
/// - Flips `isOfflineSessionExpired` the instant `offline_session_threshold_seconds`
///   elapses since the last successful health check, via a live re-armed `Timer`
///   (mirrors `FaceSessionManager`'s idle-timeout pattern) — forced logout fires
///   immediately, regardless of foreground/navigation activity.
@MainActor
final class OfflineSessionManager: ObservableObject {

    static let shared = OfflineSessionManager()

    /// Fallback threshold used when the server has never supplied
    /// `offline_session_threshold_seconds` (e.g. fresh install).
    static let defaultThresholdSeconds = 86400

    @Published private(set) var isOffline: Bool
    @Published private(set) var isOfflineSessionExpired: Bool = false
    /// Bumped once a second while offline so any view observing this object
    /// re-renders live countdown text — owned here (not by the view) so it
    /// survives SwiftUI rebuilding the observing view's struct.
    @Published private(set) var tick: Int = 0

    /// Invoked exactly once, the instant the offline session expires. Set by
    /// the app root to perform the actual forced logout. Deliberately a direct
    /// callback rather than relying on SwiftUI's `.onChange` (which only fires
    /// on a false→true *transition* and can miss it under timing races) —
    /// this fires unconditionally when expiry is detected, from any call site.
    ///
    /// Self-healing: if expiry was already detected before this was assigned
    /// (e.g. a timer fired before the app root had a chance to set this on
    /// launch), assigning it here fires it immediately — `hasFiredExpiredCallback`
    /// tracks "callback actually ran," separately from `isOfflineSessionExpired`
    /// ("expiry detected"), so a nil-callback race can never permanently
    /// swallow a forced logout.
    var onSessionExpired: (() -> Void)? {
        didSet {
            if isOfflineSessionExpired && !hasFiredExpiredCallback {
                fireExpiredCallback()
            }
        }
    }

    private var hasFiredExpiredCallback = false

    private var cancellables = Set<AnyCancellable>()
    private var expiryTimer: Timer?
    private var tickTimer: Timer?

    private init() {
        isOffline = AppStorageManager.shared.isOfflineMode

        NotificationCenter.default
            .publisher(for: .serverErrorResponseReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.markOffline()
            }
            .store(in: &cancellables)

        if isOffline {
            armExpiryTimer()
            armTickTimer()
        }
    }

    // MARK: - Health check outcomes

    /// Call after a successful, healthy `/health` 2xx response.
    func markHealthy(checkedAt: String?) {
        if let checkedAt {
            AppStorageManager.shared.lastHealthCheckedAt = checkedAt
        }
        isOffline = false
        AppStorageManager.shared.isOfflineMode = false
        disarmExpiryTimer()
        disarmTickTimer()
    }

    /// Call when `/health` fails, auth/me fails after a healthy `/health`, or any
    /// other API call exhausts retries on a 5xx/network failure.
    func markOffline() {
        guard !isOffline else { return }
        isOffline = true
        AppStorageManager.shared.isOfflineMode = true
        armExpiryTimer()
        armTickTimer()
    }

    // MARK: - Expiry (live timer, plus a manual re-check for foreground/appear call sites)

    /// Schedules a one-shot `Timer` to fire exactly when the offline session
    /// expires, so forced logout happens immediately rather than waiting for the
    /// next foreground/Dashboard-appear check. No-ops if the expiry is already
    /// in the past (fires the check immediately) or unknown (no anchor yet —
    /// `markHealthy` hasn't ever run, so there's nothing to expire).
    private func armExpiryTimer() {
        disarmExpiryTimer()
        guard let expiry = currentExpiryDate() else { return }
        let delay = expiry.timeIntervalSinceNow
        guard delay > 0 else {
            evaluateExpiry()
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.evaluateExpiry() }
        }
        // Timer.scheduledTimer only registers in `.default` run loop mode,
        // which stalls while the user is scrolling/tracking a gesture — add it
        // to `.common` explicitly so the forced logout fires on time regardless
        // of what the user is doing in the UI at that instant.
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func disarmExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    private func armTickTimer() {
        disarmTickTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick += 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func disarmTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Computes `lastHealthCheckedAt + threshold` and compares to now. Sets
    /// `isOfflineSessionExpired` and fires `onSessionExpired` when the offline
    /// session should be forced out. Safe to call redundantly (the live timer
    /// above, scenePhase/.active, Dashboard onAppear all call this) — guarded
    /// so the callback fires exactly once per offline session.
    func evaluateExpiry() {
        guard isOffline, !isOfflineSessionExpired else { return }
        guard let expiry = currentExpiryDate() else { return }
        if Date() > expiry {
            isOfflineSessionExpired = true
            fireExpiredCallback()
        }
    }

    /// Fires `onSessionExpired` exactly once. Called both from `evaluateExpiry()`
    /// (the normal path) and from `onSessionExpired`'s `didSet` (the self-heal
    /// path, for when expiry was detected before a callback existed to run).
    private func fireExpiredCallback() {
        guard !hasFiredExpiredCallback, let callback = onSessionExpired else { return }
        hasFiredExpiredCallback = true
        callback()
    }

    /// `nil` only when there is no known anchor timestamp (no health check has
    /// ever succeeded). The threshold itself always resolves — falling back to
    /// `defaultThresholdSeconds` when never cached from the server.
    func currentExpiryDate() -> Date? {
        guard let checkedAtString = AppStorageManager.shared.lastHealthCheckedAt,
              let anchor = Self.parseCheckedAt(checkedAtString) else { return nil }
        let thresholdSeconds = AppStorageManager.shared.cachedOfflineSessionThresholdSeconds
            ?? Self.defaultThresholdSeconds
        return anchor.addingTimeInterval(TimeInterval(thresholdSeconds))
    }

    /// Remaining time until forced logout, or `nil` if not offline / no expiry known.
    var remainingOfflineTime: TimeInterval? {
        guard isOffline, let expiry = currentExpiryDate() else { return nil }
        return max(0, expiry.timeIntervalSinceNow)
    }

    static func parseCheckedAt(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Call after a forced logout completes (or a successful login) to reset state.
    func reset() {
        isOffline = false
        isOfflineSessionExpired = false
        hasFiredExpiredCallback = false
        AppStorageManager.shared.isOfflineMode = false
        disarmExpiryTimer()
        disarmTickTimer()
    }
}
