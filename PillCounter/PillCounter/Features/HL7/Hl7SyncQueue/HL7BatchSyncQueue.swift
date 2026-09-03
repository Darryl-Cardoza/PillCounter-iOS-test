//
//  HL7BatchSyncQueue.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/04/26.
//
//  ACK-driven, fault-tolerant, non-blocking batch sync queue.
//  Owns the full lifecycle: enqueue → send → await ACK → mark synced / retry.
//

import Foundation
import Combine

// MARK: - Queue Item

struct BatchSyncQueueItem: HL7QueueItem {
    let batchId: Int64
    let requestId: String   // req_id_from_pms or generated fallback
    let cursor: Int64
}

// MARK: - HL7BatchSyncQueue

final class HL7BatchSyncQueue: HL7SyncQueue<BatchSyncQueueItem> {

    // MARK: Dependencies
    private let batchDAO = BatchStore.shared
    private let stockTxnDAO = StockTxnStore.shared
    private let userDAO = UserStore.shared
    /// Only the config is needed here — the actual `HL7CompletionBuilder`
    /// (and its underlying `HL7Builder` message engine) is constructed fresh
    /// per send, scoped to the background context the send runs on (see
    /// `processNext`), so this queue never builds/holds a real builder.
    private let hl7Config: HL7Config
    private weak var hl7Manager: Hl7ServiceManager?           // your existing socket manager

    // MARK: Init
    init(
        hl7Config: HL7Config = .current,
        hl7Manager: Hl7ServiceManager?
    ) {
        self.hl7Config = hl7Config
        self.hl7Manager = hl7Manager
        super.init(processingQueueLabel: "hl7.sync.queue")
    }

    // MARK: - Public API

    /// Call on client connect and whenever a batch is completed.
    /// Safe to call multiple times — deduplicates by requestId.
    func enqueueUnsynced() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.loadAndEnqueuePending(
                after: nil,
                fetchPage: { cursor, limit in
                    self.batchDAO.fetchCompletedUnsyncedPage(after: cursor, limit: limit)
                        .map { BatchSyncQueueItem(batchId: $0.batch_id, requestId: self.resolvedRequestId(for: $0), cursor: $0.start_date_time) }
                },
                onFirstChunk: { self.processNext() }
            )
        }
    }

    // MARK: - Private: Processing

    override func processNext() {
        // Already waiting for an ACK — do not send another
        guard !isSending, let item = queue.first else {
            return
        }

        // `batch`/`user`/`stockTxns` and everything `buildInventoryMessage`
        // reads off them must all stay on ONE context's queue for the
        // duration of the build (same rationale as `HL7TxnSyncQueue.
        // processNext` — mixing objects across contexts mid-build is what
        // caused the original SIGABRT under load). Fetch everything from a
        // dedicated background context and hand that same context to the
        // builder, so the whole build runs off-main instead of hopping this
        // background-queue work onto `viewContext`/the main thread.
        let bgContext = CoreDataManager.shared.backgroundContext
        let builderConfig = hl7Config
        let hl7: String? = bgContext.performAndWait { () -> String? in
            guard
                let batch = batchDAO.fetchById(item.batchId, in: bgContext),
                batch.status == CountStatus.COMPLETED.rawValue,
                batch.is_synced == false
            else {
                return nil
            }

            let stockTxns = stockTxnDAO.fetchByBatch(batchId: item.batchId, in: bgContext)

            guard !stockTxns.isEmpty, let userId = batch.user_id, let user = userDAO.fetchByUserId(userId, in: bgContext) else {
                return nil
            }

            let message = HL7CompletionBuilder(config: builderConfig, context: bgContext)
                .buildInventoryMessage(batch: batch, user: user)
            return message
        }

        guard let hl7 else {
            removeFirstQueueItem()
            processNext()
            return
        }
        StoreLogger.debug("📡 [HL7] Built batch message for \(item.batchId):\n\(hl7)")

        guard let ackMessageId = HL7TxnSyncQueue.extractMessageControlId(from: hl7) else {
            removeFirstQueueItem()
            processNext()
            return
        }

        isSending            = true
        pendingRequestId     = item.requestId
        pendingAckMessageId  = ackMessageId

        DispatchQueue.main.async { [weak self] in
            self?.hl7Manager?.sendHL7ToPMS(hl7, orderId: item.batchId.description)
            StoreLogger.debug("📤 [HL7] Sent to server for batch: \(item.batchId)")
        }

        scheduleAckTimeout(for: item.requestId)
    }

    // MARK: - Overrides

    /// Preserves this queue's original guard against an empty queue
    /// (`HL7TxnSyncQueue`'s equivalent is unconditional — deliberately not
    /// unified, see `HL7SyncQueue`'s header comment).
    override func removeFirstQueueItem() {
        if !queue.isEmpty { queue.removeFirst() }
    }

    /// Preserves this queue's original `processAck` fallback: an ACK
    /// arriving with no `pendingRequestId` set resets `isSending` and calls
    /// `processNext()` directly here (`HL7TxnSyncQueue`'s equivalent branch
    /// does neither, just returns — deliberately not unified).
    override func handleNilPendingRequestId() {
        isSending = false
        processNext()
    }

    /// Writes via a background context instead of hopping to `viewContext`/
    /// main — see `HL7TxnSyncQueue.markCurrentItemSynced` for the rationale.
    /// Runs synchronously on `processingQueue` (already the calling queue,
    /// via `processAck`), which only blocks the serialized sync queue, never
    /// the UI thread.
    override func markCurrentItemSynced() {
        guard let item = queue.first else { return }
        let bgContext = CoreDataManager.shared.backgroundContext
        batchDAO.markSynced(batchId: item.batchId, in: bgContext)
    }

    // Note: `shouldSkipItem` is left at the base default (never skip) —
    // this queue has never skipped soft-deleted rows during drain, unlike
    // HL7TxnSyncQueue.

    // MARK: - Private: Helpers
    /// Uses existing req_id_from_pms or generates a stable millisecond-based fallback.
    private func resolvedRequestId(for batch: BatchCountEntity) -> String {
        if let existing = batch.req_id_from_pms, !existing.isEmpty {
            return existing
        }
        return String(batch.batch_id)   // batch_id is already Int64 milliseconds
    }
}
