//
//  HL7BatchSyncQueue.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/04/26.
//

//
//  HL7BatchSyncQueue.swift
//  PillCounter
//
//  ACK-driven, fault-tolerant, non-blocking batch sync queue.
//  Owns the full lifecycle: enqueue → send → await ACK → mark synced / retry.
//

import Foundation
import Combine

// MARK: - Queue Item

private struct SyncQueueItem {
    let batchId: Int64
    let requestId: String   // req_id_from_pms or generated fallback
}

// MARK: - HL7BatchSyncQueue

final class HL7BatchSyncQueue {

    // MARK: Dependencies
    private let batchDAO = BatchStore.shared
    private let stockTxnDAO = StockTxnStore.shared
    private let userDAO = UserStore.shared
    private let hl7Builder: HL7CompletionBuilder
    private weak var hl7Manager: Hl7ServiceManager?           // your existing socket manager

    // MARK: State
    private var queue: [SyncQueueItem] = []
    private var isSending = false
    private var pendingRequestId: String?              // internal dedup/park key
    /// MSH-10 (messageControlId) of the in-flight HL7 message — the PMS echoes this
    /// back in MSA-2, NOT `pendingRequestId` (an internal dedup key). Must match
    /// against this, or every real ACK reads as "not mine" and every send times out.
    private var pendingAckMessageId: String?
    private var ackTimeoutWork: DispatchWorkItem?

    /// requestIds that failed (NACK or ACK timeout) in the current connection session.
    /// Parked items are skipped by `loadAndEnqueuePending` until `resetParkedState()`
    /// runs — one retry attempt per connection, no continuous resend hammering the
    /// PMS. Cleared on reconnect (`Hl7ServiceController.onClientConnected`) or an
    /// explicit user-initiated retry.
    private var parkedRequestIds: Set<String> = []

    // MARK: Config
    private let ackTimeoutSeconds: TimeInterval = 10
    private let processingQueue = DispatchQueue(label: "hl7.sync.queue", qos: .utility)

    /// Backlog-drain chunking — see `HL7TxnSyncQueue.loadChunkSize`/`loadChunkDelay`
    /// for the rationale (a single unbounded fetch held the main `viewContext`
    /// continuously long enough, with a large backlog, to read as an app freeze).
    private let loadChunkSize = 50
    private let loadChunkDelay: TimeInterval = 0.05

    // MARK: Init
    init(
        hl7Builder: HL7CompletionBuilder,
        hl7Manager: Hl7ServiceManager?
    ) {
        self.hl7Builder = hl7Builder
        self.hl7Manager = hl7Manager
    }

    // MARK: - Public API

    /// Call on client connect and whenever a batch is completed.
    /// Safe to call multiple times — deduplicates by requestId.
    func enqueueUnsynced() {
        processingQueue.async { [weak self] in
            self?.loadAndEnqueuePending(offset: 0)
        }
    }

    /// Clears parked (failed-attempt) state so previously-failed batches are eligible
    /// for one more send attempt. Call on reconnect and on user-initiated manual retry.
    func resetParkedState() {
        processingQueue.async { [weak self] in
            self?.parkedRequestIds.removeAll()
        }
    }

    /// Call with the raw ACK string received from the PMS socket. `messageId` (MSA-2)
    /// must match this queue's own in-flight `pendingRequestId` — otherwise the ACK
    /// belongs to the other sync queue (txn vs batch) and is ignored here.
    func handleAck(messageId: String?, hl7 ackMessage: String) {
        processingQueue.async { [weak self] in
            guard let self, self.pendingAckMessageId != nil, messageId == self.pendingAckMessageId else { return }
            self.processAck(ackMessage)
        }
    }

    // MARK: - Private: Queue Management

    /// `enqueueUnsynced()` fires on every `transactionsDidChange` signal —
    /// up to once per ACK while a large backlog drains — but every prior
    /// call already queued everything unsynced at the time (deduped below
    /// against `queue`), so a mid-drain re-fetch only ever turns up items
    /// already queued. Skipping the fetch while `queue` still has items
    /// avoids re-fetching the entire unsynced set on every single ACK; once
    /// the queue drains, the next `enqueueUnsynced()` call picks up
    /// anything new.
    /// Paged in chunks of `loadChunkSize`, with a `loadChunkDelay` yield
    /// between chunks — see `HL7TxnSyncQueue.loadAndEnqueuePending` for why.
    private func loadAndEnqueuePending(offset: Int) {
        if offset == 0 {
            guard queue.isEmpty else {
                print("📦 [Queue] Skipping reload — \(queue.count) item(s) still queued")
                return
            }
            print("📦 [Queue] Loading pending batches from offset 0")
        }

        let page = batchDAO.fetchCompletedUnsyncedPage(limit: loadChunkSize, offset: offset)

        for batch in page {
            let requestId = resolvedRequestId(for: batch)

            print("🔍 [Queue] Checking batch:", batch.batch_id,
                  "| reqId:", requestId,
                  "| is_synced:", batch.is_synced)

            guard !parkedRequestIds.contains(requestId) else {
                print("⏸️ [Queue] Skipping parked (already failed this session):", requestId)
                continue
            }

            // Deduplicate — never add same requestId twice
            guard !queue.contains(where: { $0.requestId == requestId }) else {
                print("⚠️ [Queue] Skipping duplicate requestId:", requestId)
                continue
            }

            queue.append(SyncQueueItem(batchId: batch.batch_id, requestId: requestId))
            print("✅ [Queue] Enqueued batch:", batch.batch_id)
        }

        // First chunk enqueued (if any) — let sending start without waiting
        // for the rest of the backlog to page in.
        if offset == 0 {
            processNext()
        }

        guard page.count == loadChunkSize else {
            print("📦 [Queue] Final queue:", queue.map { $0.batchId })
            return
        }

        processingQueue.asyncAfter(deadline: .now() + loadChunkDelay) { [weak self] in
            self?.loadAndEnqueuePending(offset: offset + page.count)
        }
    }

    private func processNext() {

        print("➡️ [Queue] processNext called")
        print("📦 [Queue] Current queue:", queue.map { $0.batchId })
        print("⏳ [Queue] isSending:", isSending)

        // Already waiting for an ACK — do not send another
        guard !isSending, let item = queue.first else {
            print("⏸️ [Queue] Skipping - either sending in progress or queue empty")
            return
        }

        print("🚀 [Queue] Processing batch:", item.batchId,
              "| requestId:", item.requestId)

        // `batch`/`user`/`stockTxns` and everything `buildInventoryMessage`
        // reads off them must all stay on ONE context's queue for the
        // duration of the build (same rationale as `HL7TxnSyncQueue.
        // processNext` — mixing objects across contexts mid-build is what
        // caused the original SIGABRT under load). Fetch everything from a
        // dedicated background context and hand that same context to the
        // builder, so the whole build runs off-main instead of hopping this
        // background-queue work onto `viewContext`/the main thread.
        let bgContext = CoreDataManager.shared.backgroundContext
        let builderConfig = hl7Builder.config
        let hl7: String? = bgContext.performAndWait { () -> String? in
            guard
                let batch = batchDAO.fetchById(item.batchId, in: bgContext),
                batch.status == CountStatus.COMPLETED.rawValue,
                batch.is_synced == false
            else {
                print("❌ [Queue] Batch invalid or already synced:", item.batchId)
                return nil
            }

            let stockTxns = stockTxnDAO.fetchByBatch(batchId: item.batchId, in: bgContext)
            print("📊 [Queue] StockTxns count:", stockTxns.count)

            guard !stockTxns.isEmpty, let userId = batch.user_id, let user = userDAO.fetchByUserId(userId, in: bgContext) else {
                print("❌ [Queue] Missing stock txns or user for batch:", item.batchId)
                return nil
            }

            let message = HL7CompletionBuilder(config: builderConfig, context: bgContext)
                .buildInventoryMessage(batch: batch, user: user)
            return message
        }

        guard let hl7 else {
            queue.removeFirst()
            processNext()
            return
        }
        print("hl7\(hl7)")
        print("📡 [HL7] Sending batch:", item.batchId,
              "| requestId:", item.requestId)

        guard let ackMessageId = HL7TxnSyncQueue.extractMessageControlId(from: hl7) else {
            print("❌ [Queue] Could not read MSH-10 from built message — cannot correlate ACK, skipping send")
            queue.removeFirst()
            processNext()
            return
        }

        isSending            = true
        pendingRequestId     = item.requestId
        pendingAckMessageId  = ackMessageId

        DispatchQueue.main.async { [weak self] in
            self?.hl7Manager?.sendHL7ToPMS(hl7, orderId: item.batchId.description)
            print("📤 [HL7] Sent to server for batch:", item.batchId)
        }

        scheduleAckTimeout(for: item.requestId)
        print("⏱️ [Queue] ACK timeout scheduled for:", item.requestId)
    }
    // MARK: - Private: ACK Handling

    private func processAck(_ message: String) {
        cancelAckTimeout()

        guard let requestId = pendingRequestId else {
            isSending = false
            processNext()
            return
        }

        if isPositiveAck(message) {
            markCurrentBatchSynced()
        } else {
            print("❌ [Queue] Negative/invalid ACK — parking batch until next connect/retry:", requestId)
            parkedRequestIds.insert(requestId)
        }
        advanceQueue()
    }

    private func isPositiveAck(_ message: String) -> Bool {
        return message.contains("|AA|") || message.contains("|AA\r")
    }

    /// Writes via a background context instead of hopping to `viewContext`/
    /// main — see `HL7TxnSyncQueue.markCurrentTxnSynced` for the rationale.
    /// Runs synchronously on `processingQueue` (already the calling queue,
    /// via `processAck`), which only blocks the serialized sync queue, never
    /// the UI thread.
    private func markCurrentBatchSynced() {
        guard let item = queue.first else { return }
        let bgContext = CoreDataManager.shared.backgroundContext
        batchDAO.markSynced(batchId: item.batchId, in: bgContext)
    }

    private func advanceQueue() {
        isSending           = false
        pendingRequestId    = nil
        pendingAckMessageId = nil
        if !queue.isEmpty { queue.removeFirst() }
        processNext()
    }

    // MARK: - Private: ACK Timeout

    private func scheduleAckTimeout(for requestId: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.processingQueue.async {
                guard let self, self.pendingRequestId == requestId else { return }
                print("⏰ [Queue] ACK timeout — parking batch until next connect/retry:", requestId)
                self.parkedRequestIds.insert(requestId)
                self.advanceQueue()
            }
        }
        ackTimeoutWork = work
        DispatchQueue.global().asyncAfter(
            deadline: .now() + ackTimeoutSeconds,
            execute: work
        )
    }

    private func cancelAckTimeout() {
        ackTimeoutWork?.cancel()
        ackTimeoutWork = nil
    }

    // MARK: - Private: Helpers
    /// Uses existing req_id_from_pms or generates a stable millisecond-based fallback.
    private func resolvedRequestId(for batch: BatchCountEntity) -> String {
        if let existing = batch.req_id_from_pms, !existing.isEmpty {
            return existing
        }
        return String(batch.batch_id)   // batch_id is already Int64 milliseconds
    }

}
