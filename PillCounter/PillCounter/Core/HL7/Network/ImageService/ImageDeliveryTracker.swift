//
//  ImageDeliveryTracker.swift
//  PillCounter
//

import Foundation

/// Tracks, in memory only, which image filenames have been confirmed as
/// successfully sent to the PMS over the image HTTPS server (TCP send
/// completed with no error). Not persisted — cleared on app restart. This is
/// a lossy but safe signal: on restart a transaction just waits to be
/// re-delivered/re-confirmed rather than ever being deleted prematurely. The
/// 24h TTL sweep (see TransactionRetentionSweeper) is the backstop for cases
/// where delivery confirmation never completes.
final class ImageDeliveryTracker {

    static let shared = ImageDeliveryTracker()
    private init() {}

    private var deliveredFilenames: Set<String> = []
    private let lock = NSLock()

    func markDelivered(_ filenames: [String]) {
        lock.lock(); defer { lock.unlock() }
        deliveredFilenames.formUnion(filenames)
    }

    /// True when every filename in `filenames` has been confirmed delivered.
    /// An empty list (transaction has no images) is trivially satisfied.
    func allDelivered(_ filenames: [String]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return filenames.isEmpty || filenames.allSatisfy { deliveredFilenames.contains($0) }
    }
}
