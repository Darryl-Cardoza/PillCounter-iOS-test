//
//  FaceSessionManager.swift
//  PillCounter
//
//  Single source of truth for "who currently owns this app session" via face
//  recognition. Distinct from SessionManager (Base/SessionManager.swift),
//  which owns auth-token expiry — that is a login concept, this is a
//  physical-presence concept layered on top of an already-logged-in app.
//
//  Persistence: `last_authenticated_at` on FaceUserEntity (Core Data) is the
//  durable per-user "last active" timestamp — set on every successful face
//  match and touched again by `recordActivity()` while unlocked, so it
//  survives a crash/kill (spec: "must survive app termination"). The
//  in-memory `currentUserId`/`lockState` here do NOT survive termination by
//  design — cold launch always re-locks (see `lockOnColdLaunch`).
//

import Foundation

@MainActor
final class FaceSessionManager: ObservableObject {

    static let shared = FaceSessionManager()

    /// Idle time, in seconds, with no recorded activity before the app locks.
    /// Editable under Settings > Face Recognition > Time Limit
    /// (FaceSessionTimeoutOption); seeded from that persisted value here.
    var inactivityTimeout: TimeInterval = AppStorageManager.shared.faceSessionTimeoutOption.seconds

    @Published private(set) var lockState: SessionLockState = .locked
    @Published private(set) var currentUserId: String?
    @Published private(set) var currentUserName: String?

    /// How long the app sat idle before this lock, for the "Idle for N min"
    /// subtitle. `nil` on cold launch, where there's no prior activity to
    /// measure against.
    @Published private(set) var idleDurationAtLock: TimeInterval?

    var isLocked: Bool {
        switch lockState {
        case .locked, .scanning, .failed: return true
        case .unlocked: return false
        }
    }

    /// The lock overlay stays visible through the brief "Welcome back" screen
    /// even though `isLocked` is already false, so the transition reads as
    /// one continuous motion instead of the underlying app flashing in
    /// mid-animation. `dismissOverlay()` ends this window.
    @Published private(set) var isOverlayVisible: Bool = true

    private var lastActiveAt: Date = Date()
    private var idleTimer: Timer?

    private init() {
        // Display-only continuity across relaunches (spec 7: resume in place
        // once unlocked) — does not affect lockState, which always starts
        // `.locked` per `lockOnColdLaunch`.
        currentUserId = AppStorageManager.shared.faceLockCurrentUserId
        currentUserName = AppStorageManager.shared.faceLockCurrentUserName
    }

    // MARK: - Enrollment gate

    /// Face unlock is only meaningful when somebody is enrolled AND active.
    /// With nothing to match against, a lock is unrecoverable — no scan can
    /// ever succeed, so the overlay would trap the app with no way out. Every
    /// lock entry point checks this, and `releaseLockIfNoUsersEnrolled()`
    /// releases an existing lock the moment the roster empties.
    ///
    /// `activeOnly: true` deliberately mirrors the identify path
    /// (FaceRecognitionRepository) — deactivating every user is just as
    /// unrecoverable as deleting them.
    var hasEnrolledUsers: Bool {
        !FaceUserStore.shared.getAllUsers(activeOnly: true).isEmpty
    }

    /// Drops any active lock when the roster is empty — called on app
    /// foreground/launch and right after user deletion, so deleting the last
    /// enrolled user can never leave the app stuck behind the overlay.
    /// No-op while users remain.
    func releaseLockIfNoUsersEnrolled() {
        guard !hasEnrolledUsers else { return }

        currentUserId = nil
        currentUserName = nil
        AppStorageManager.shared.faceLockCurrentUserId = nil
        AppStorageManager.shared.faceLockCurrentUserName = nil

        idleDurationAtLock = nil
        lockState = .unlocked(userName: "")
        isOverlayVisible = false
        stopIdleTimer()
    }

    // MARK: - Lock / unlock

    /// Cold launch (app was fully closed and reopened) always requires a
    /// fresh scan — call once at app start, before the first frame renders.
    /// Skipped entirely when nobody is enrolled.
    func lockOnColdLaunch() {
        guard hasEnrolledUsers else {
            releaseLockIfNoUsersEnrolled()
            return
        }
        lockState = .locked
        isOverlayVisible = true
        idleDurationAtLock = nil
        stopIdleTimer()
    }

    /// App entered background — always lock; resuming to foreground with a
    /// stale session is exactly the gap this feature closes.
    func lockOnBackground() {
        guard hasEnrolledUsers else {
            releaseLockIfNoUsersEnrolled()
            return
        }
        idleDurationAtLock = isLocked ? idleDurationAtLock : Date().timeIntervalSince(lastActiveAt)
        lockState = .locked
        isOverlayVisible = true
        stopIdleTimer()
    }

    func lockDueToInactivity() {
        guard !isLocked else { return }
        guard hasEnrolledUsers else {
            releaseLockIfNoUsersEnrolled()
            return
        }
        idleDurationAtLock = Date().timeIntervalSince(lastActiveAt)
        lockState = .locked
        isOverlayVisible = true
        stopIdleTimer()
    }

    /// Allowed from `.locked` (first scan) and from `.failed` (Try Again).
    /// Guarded against `.scanning`/`.unlocked` so a stray call can't restart
    /// a scan that is already in flight or re-lock an unlocked session.
    func beginScanning() {
        switch lockState {
        case .locked, .failed:
            lockState = .scanning
        case .scanning, .unlocked:
            return
        }
    }

    func markFailed() {
        lockState = .failed
    }

    /// Call after a successful face match, regardless of whether it's the
    /// same user as before or a different one — ownership always switches to
    /// whoever just scanned (spec 6).
    func unlock(userId: String, userName: String) {
        let now = Date()
        currentUserId = userId
        currentUserName = userName
        lastActiveAt = now
        lockState = .unlocked(userName: userName)

        AppStorageManager.shared.faceLockCurrentUserId = userId
        AppStorageManager.shared.faceLockCurrentUserName = userName
        FaceUserStore.shared.updateLastAuthenticatedAt(id: userId, date: now)

        startIdleTimer()
    }

    /// Returns to `.locked` from the failure screen without granting access.
    /// Session owner is left untouched (spec 5).
    func cancelScan() {
        lockState = .locked
    }

    /// Ends the "Welcome back" transition window, hiding the overlay and
    /// revealing the app underneath exactly where it was left (spec 7). Call
    /// after the brief auto-dismiss delay on the unlocked screen.
    func dismissOverlay() {
        isOverlayVisible = false
    }

    // MARK: - Activity tracking

    /// Call on every meaningful user interaction while unlocked. Resets the
    /// idle clock and persists the current owner's last-active timestamp so
    /// it's accurate even if the app is killed a moment later.
    func recordActivity() {
        guard !isLocked, let userId = currentUserId else { return }
        lastActiveAt = Date()
        FaceUserStore.shared.updateLastAuthenticatedAt(id: userId, date: lastActiveAt)
        startIdleTimer()
    }

    private func startIdleTimer() {
        stopIdleTimer()
        // Nothing to lock back to — don't arm a timer that would fire into a
        // dead end.
        guard hasEnrolledUsers else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lockDueToInactivity()
            }
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// "Idle for 2 min" / "Idle for 45 sec" style text for the locked
    /// screen's subtitle. `nil` when there's nothing to report (cold launch).
    var idleDurationText: String? {
        guard let seconds = idleDurationAtLock else { return nil }
        if seconds >= 60 {
            let minutes = Int((seconds / 60).rounded())
            return String(format: L10n.FaceAuth.sessionIdleMinutes, minutes)
        }
        return String(format: L10n.FaceAuth.sessionIdleSeconds, Int(seconds.rounded()))
    }
}
