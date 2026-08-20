//
//  SessionLockState.swift
//  PillCounter
//

/// Drives the global session-lock overlay (see FaceSessionManager). Distinct
/// from AuthenticationState — that enum tracks per-frame scan pipeline
/// progress; this tracks which of the three lock-screen UIs to show.
enum SessionLockState: Equatable {
    /// Locked, no scan in progress — shows the "Session Locked" screen with
    /// the primary "scan to unlock" action.
    case locked
    /// A face scan is running against the existing verify pipeline.
    case scanning
    /// A scan matched a registered user — shows "Welcome back, [name]"
    /// briefly before auto-dismissing the overlay.
    case unlocked(userName: String)
    /// The scan attempt timed out with no match — shows "We couldn't
    /// recognize you" with Cancel / Try Again.
    case failed
}
