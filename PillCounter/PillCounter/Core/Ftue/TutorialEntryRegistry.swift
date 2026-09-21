//
//  TutorialEntryRegistry.swift
//  PillCounter
//
//  Tracks batch/transaction ids created purely as a byproduct of walking
//  through an FTUE tour, so HL7 send/resend paths can exclude them. In-memory
//  only (no Core Data schema change) — sufficient because exclusion only
//  needs to hold for the current app session, before the real sync queue
//  would otherwise pick the row up.
//
//  Marking happens only at row-CREATION call sites, keyed on whether a tour
//  is active at that instant. Resuming an already-existing batch/transaction
//  never re-creates it, so resumed real work is never retroactively marked —
//  only a genuinely new row created while a tour is active gets excluded.
//

import Foundation

/// Not @MainActor: marked at row creation on the main queue (BatchStore/
/// StockTxnStore run on the Core Data view context's queue) but checked from
/// HL7BatchSyncQueue's own background processingQueue — genuinely
/// cross-thread, so access is guarded by a lock rather than actor isolation.
final class TutorialEntryRegistry {
    static let shared = TutorialEntryRegistry()

    private let lock = NSLock()
    private var batchIds: Set<Int64> = []
    private var stockTxnIds: Set<Int64> = []
    /// Reserved for the future Dispense-flow tour; unused by this plan.
    private var dispenseTxnIds: Set<Int64> = []

    private init() {}

    func markTutorialBatch(_ id: Int64) {
        lock.lock(); defer { lock.unlock() }
        batchIds.insert(id)
    }

    func isTutorialBatch(_ id: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return batchIds.contains(id)
    }

    func markTutorialStockTxn(_ id: Int64) {
        lock.lock(); defer { lock.unlock() }
        stockTxnIds.insert(id)
    }

    func isTutorialStockTxn(_ id: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stockTxnIds.contains(id)
    }

    func markTutorialDispenseTxn(_ id: Int64) {
        lock.lock(); defer { lock.unlock() }
        dispenseTxnIds.insert(id)
    }

    func isTutorialDispenseTxn(_ id: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return dispenseTxnIds.contains(id)
    }
}
