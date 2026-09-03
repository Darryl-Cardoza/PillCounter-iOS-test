//
//  HL7TxnSyncQueue.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//
//  ACK-driven, fault-tolerant, non-blocking transaction sync queue.
//  Mirrors HL7BatchSyncQueue exactly — one txn in-flight at a time,
//  retry-on-NACK, move-to-end on max retries, ACK timeout with back-off.
//

import Foundation
import Combine

// MARK: - Queue Item

struct TxnSyncQueueItem: HL7QueueItem {
    let txnId: Int64
    let requestId: String
    let cursor: Int64
}

// MARK: - HL7TxnSyncQueue
final class HL7TxnSyncQueue: HL7SyncQueue<TxnSyncQueueItem> {

    private let transactionDAO = TransactionStore.shared
    /// Only the config is needed here — the actual `HL7CompletionBuilder`
    /// (and its underlying `HL7Builder` message engine) is constructed fresh
    /// per send, scoped to the background context the send runs on (see
    /// `processNext`), so this queue never builds/holds a real builder.
    private let hl7Config: HL7Config
    private weak var hl7Manager: Hl7ServiceManager?

    init(
        hl7Config: HL7Config = .current,
        hl7Manager: Hl7ServiceManager?
    ) {
        self.hl7Config = hl7Config
        self.hl7Manager = hl7Manager
        super.init(processingQueueLabel: "hl7.txn.sync.queue")
    }

    // MARK: - PUBLIC

    /// `enqueueUnsynced()` fires on every `transactionsDidChange` signal —
    /// up to once per ACK while a large backlog drains — but every prior
    /// call already queued everything unsynced at the time (deduped in the
    /// base class against `queue`), so a mid-drain re-fetch only ever turns
    /// up items already queued. Skipping the fetch while `queue` still has
    /// items avoids re-fetching and fully AES-decrypting the entire unsynced
    /// set (potentially thousands of rows) on every single ACK; once the
    /// queue drains, the next `enqueueUnsynced()` call picks up anything new.
    func enqueueUnsynced() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.loadAndEnqueuePending(
                after: nil,
                fetchPage: { cursor, limit in
                    self.transactionDAO.fetchCompletedUnsyncedPage(after: cursor, limit: limit)
                        .filter { !$0.is_deleted }
                        .map { TxnSyncQueueItem(txnId: $0.txn_id, requestId: self.resolvedRequestId(for: $0), cursor: $0.created_at) }
                },
                onFirstChunk: { self.processNext() }
            )
        }
    }

    // MARK: - PROCESS

    override func processNext() {
        guard !isSending, let item = queue.first else { return }

        // `txn`/`user` and everything `buildCompletionMessage` reads off them
        // (relationship faults, plus its own nested store calls) must all
        // stay on ONE context's queue for the duration of the build — mixing
        // an object from one context with a fetch/fault on another is what
        // previously surfaced as a SIGABRT inside `pillCountDetails(from:)`
        // under load. Rather than routing this through `viewContext` (which
        // would hop this background-queue work onto the main thread for the
        // whole build), fetch `txn` from a dedicated background context and
        // hand that same context to the builder, so the entire build runs
        // off-main. `bgContext` is a fresh `newBackgroundContext()` per call
        // — cheap, and avoids any shared mutable context state between
        // concurrent sync-queue sends.
        let bgContext = CoreDataManager.shared.backgroundContext
        let builderConfig = hl7Config
        let hl7: String? = bgContext.performAndWait { () -> String? in
            guard
                let txn = transactionDAO.fetchById(item.txnId, in: bgContext),
                txn.is_synced == false,
                txn.status == CountStatus.COMPLETED.rawValue,
                let user = txn.user
            else { return nil }
            let message = HL7CompletionBuilder(config: builderConfig, context: bgContext)
                .buildCompletionMessage(txn: txn, user: user)
            return message
        }

        guard let hl7 else {
            removeFirstQueueItem()
            processNext()
            return
        }
        StoreLogger.debug("📡 [HL7] Built txn message for \(item.txnId):\n\(hl7)")
        guard let manager = hl7Manager, !hl7.isEmpty else {
            return
        }

        guard let ackMessageId = Self.extractMessageControlId(from: hl7) else {
            removeFirstQueueItem()
            processNext()
            return
        }

        isSending = true
        pendingRequestId = item.requestId
        pendingAckMessageId = ackMessageId

        DispatchQueue.main.async {
            manager.sendHL7ToPMS(hl7, orderId: item.requestId)
        }

        scheduleAckTimeout(for: item.requestId)
    }

    // MARK: - Overrides

    /// Writes the ACK-success sync flag via a background context instead of
    /// hopping to `viewContext`/main — `TransactionStore.updateSynced`
    /// (fetch + save, plus a further fetch + possible hard-delete via
    /// `attemptHardDeleteIfEligible`) previously ran synchronously on main
    /// once per synced transaction, which under a fast-ACKing PMS was
    /// frequent enough repeated main-thread work to read as app lag while a
    /// backlog drained. Runs synchronously on `processingQueue` (this method
    /// is already called from there via `processAck`), which is fine — it
    /// only blocks the serialized sync queue, never the UI thread. The write
    /// merges into `viewContext` automatically (`automaticallyMergesChangesFromParent`
    /// on `CoreDataManager.backgroundContext`); `transactionsDidChange` still
    /// reaches UI observers via their own `.receive(on: .main)`.
    override func markCurrentItemSynced() {
        guard let item = queue.first else { return }
        let bgContext = CoreDataManager.shared.backgroundContext
        TransactionStore.shared.updateSynced(txnId: item.txnId, in: bgContext)
    }

    // Note: `removeFirstQueueItem` is left at the base default (unconditional
    // `queue.removeFirst()`), preserving this queue's existing crash-risk
    // behavior on an empty queue — deliberately not fixed as a side effect
    // of this refactor. `shouldSkipItem`/`handleNilPendingRequestId` are
    // also left at base defaults: the soft-delete skip happens in
    // `enqueueUnsynced`'s fetchPage closure above (before `Item` is even
    // constructed), and this queue's `processAck` nil-`pendingRequestId`
    // branch has always just returned.

    // MARK: - HELPERS

    private func resolvedRequestId(for txn: PillCountTransactionEntity) -> String {
        return "TXN_\(txn.txn_id)"
    }

    /// Reads MSH-10 (messageControlId) from an already-encoded HL7 message —
    /// the value the PMS echoes back in MSA-2 of its ACK. fields[9] per the same
    /// MSH layout documented in HL7MessageBuilder.validateHl7Message.
    static func extractMessageControlId(from encoded: String) -> String? {
        guard let msh = encoded.components(separatedBy: "\r").first(where: { $0.hasPrefix("MSH") }) else {
            return nil
        }
        let fields = msh.components(separatedBy: "|")
        guard fields.count > 9, !fields[9].trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return fields[9]
    }
}
