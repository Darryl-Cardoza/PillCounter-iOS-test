//
//  WithTimeout.swift
//  PillCounter
//

import Foundation

/// Races `operation` against a timer; returns nil if `operation` hasn't
/// finished within `seconds`. Use for awaiting values that depend on an
/// external callback that isn't guaranteed to fire (e.g. FCM token delivery).
///
/// `operation` runs detached and is never cancelled: cancelling a task suspended
/// on a raw `withCheckedContinuation` (e.g. `FCMManager.getToken()`) does not
/// resume that continuation — it's only ever resumed by `updateToken(_:)` firing
/// later — so cancelling would strand the continuation (Swift's "leaked its
/// continuation" runtime warning) instead of freeing it. Whichever of
/// `operation`/timer finishes first resumes this function; the loser keeps
/// running harmlessly in the background and its result is simply discarded.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let box = ResumeOnce(continuation)
        Task.detached {
            let value = await operation()
            await box.resume(with: value)
        }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await box.resume(with: nil)
        }
    }
}

private actor ResumeOnce<T: Sendable> {
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }
    func resume(with value: T?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}
