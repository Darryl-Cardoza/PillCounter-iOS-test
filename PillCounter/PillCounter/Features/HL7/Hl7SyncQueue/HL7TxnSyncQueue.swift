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

private struct TxnSyncQueueItem {
    let txnId: Int64
    let requestId: String
}

// MARK: - HL7TxnSyncQueue
final class HL7TxnSyncQueue {

    private let transactionDAO = TransactionStore.shared
    private let hl7Builder: HL7CompletionBuilder
    private weak var hl7Manager: Hl7ServiceManager?

    private var queue: [TxnSyncQueueItem] = []
    private var isSending = false
    private var pendingRequestId: String?
    /// MSH-10 (messageControlId) of the in-flight HL7 message — this is what the PMS
    /// echoes back in MSA-2, NOT `pendingRequestId` (an internal `"TXN_<id>"` dedup
    /// key). ACKs must be matched against this, or every real ACK is misread as
    /// "not mine" and every send times out even when the PMS answered correctly.
    private var pendingAckMessageId: String?
    private var ackTimeoutWork: DispatchWorkItem?

    /// requestIds that failed (NACK or ACK timeout) in the current connection session.
    /// Parked items are skipped by `loadAndEnqueuePending` until `resetParkedState()`
    /// runs — one retry attempt per connection, no continuous resend hammering the
    /// PMS. Cleared on reconnect (`Hl7ServiceController.onClientConnected`) or an
    /// explicit user-initiated retry.
    private var parkedRequestIds: Set<String> = []

    private let ackTimeoutSeconds: TimeInterval = 10
    private let processingQueue = DispatchQueue(label: "hl7.txn.sync.queue", qos: .utility)

    /// Backlog-drain chunking: how many unsynced rows `loadAndEnqueuePending`
    /// fetches per `performAndWait` hop onto the main `viewContext`, and how
    /// long it yields the processing queue between chunks. A single unbounded
    /// fetch decrypts the whole backlog in one continuous hop — with many
    /// thousands of unsynced rows that held the main queue long enough to
    /// read as an app freeze while connecting. Chunking trades a slightly
    /// slower enqueue for regular breathing room on the main queue.
    private let loadChunkSize = 50
    private let loadChunkDelay: TimeInterval = 0.05

    init(
        hl7Builder: HL7CompletionBuilder,
        hl7Manager: Hl7ServiceManager?
    ) {
        self.hl7Builder  = hl7Builder
        self.hl7Manager  = hl7Manager
    }

    // MARK: - PUBLIC

    func enqueueUnsynced() {
        processingQueue.async { [weak self] in
            self?.loadAndEnqueuePending(offset: 0)
        }
    }

    /// Clears parked (failed-attempt) state so previously-failed txns are eligible
    /// for one more send attempt. Call on reconnect and on user-initiated manual retry.
    func resetParkedState() {
        processingQueue.async { [weak self] in
            self?.parkedRequestIds.removeAll()
        }
    }

    func handleAck(messageId: String?, hl7 ackMessage: String) {
        processingQueue.async { [weak self] in
            guard let self, self.pendingAckMessageId != nil, messageId == self.pendingAckMessageId else { return }
            self.processAck(ackMessage)
        }
    }

    // MARK: - LOAD

    /// `enqueueUnsynced()` fires on every `transactionsDidChange` signal —
    /// up to once per ACK while a large backlog drains — but every prior
    /// call already queued everything unsynced at the time (deduped below
    /// against `queue`), so a mid-drain re-fetch only ever turns up items
    /// already queued. Skipping the fetch while `queue` still has items
    /// avoids re-fetching and fully AES-decrypting the entire unsynced set
    /// (potentially thousands of rows) on every single ACK; once the queue
    /// drains, the next `enqueueUnsynced()` call picks up anything new.
    ///
    /// Paged in chunks of `loadChunkSize`, with a `loadChunkDelay` yield
    /// between chunks — each chunk's fetch is a `performAndWait` hop onto the
    /// main `viewContext` (see `processNext`), and a single unbounded fetch
    /// of a large backlog held that hop continuously long enough to read as
    /// an app freeze. Sync starts as soon as the first chunk lands rather
    /// than waiting for the whole backlog.
    private func loadAndEnqueuePending(offset: Int) {
        if offset == 0 {
            guard queue.isEmpty else {
                print("📦 [TxnQueue] Skipping reload — \(queue.count) item(s) still queued")
                return
            }
        }

        let page = transactionDAO.fetchCompletedUnsyncedPage(limit: loadChunkSize, offset: offset)
        if offset == 0 {
            print("📦 [TxnQueue] Loading pending txns from offset 0")
        }

        for txn in page {
            if txn.is_deleted {
                  print("⛔️ [TxnQueue] Skipping deleted txn:", txn.txn_id)
                  continue
            }

            let txnId = txn.txn_id
            let requestId = resolvedRequestId(for: txn)

            guard !parkedRequestIds.contains(requestId) else {
                print("⏸️ [TxnQueue] Skipping parked (already failed this session):", requestId)
                continue
            }

            guard !queue.contains(where: { $0.requestId == requestId }) else {
                print("⚠️ [TxnQueue] Duplicate requestId:", requestId)
                continue
            }

            queue.append(TxnSyncQueueItem(txnId: txnId, requestId: requestId))
            print("✅ [TxnQueue] Enqueued txn:", txnId)
        }

        // First chunk enqueued (if any) — let sending start without waiting
        // for the rest of the backlog to page in.
        if offset == 0 {
            processNext()
        }

        guard page.count == loadChunkSize else {
            print("📦 [TxnQueue] Final queue:", queue.map { $0.txnId })
            return
        }

        processingQueue.asyncAfter(deadline: .now() + loadChunkDelay) { [weak self] in
            self?.loadAndEnqueuePending(offset: offset + page.count)
        }
    }

    // MARK: - PROCESS

    private func processNext() {
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
        let builderConfig = hl7Builder.config
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
            queue.removeFirst()
            processNext()
            return
        }
        print("hl7\(hl7)")
        guard let manager = hl7Manager, !hl7.isEmpty else {
            print("❌ [TxnQueue] HL7 invalid or manager nil")
            return
        }

        guard let ackMessageId = Self.extractMessageControlId(from: hl7) else {
            print("❌ [TxnQueue] Could not read MSH-10 from built message — cannot correlate ACK, skipping send")
            queue.removeFirst()
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

    // MARK: - ACK

    private func processAck(_ message: String) {
        cancelAckTimeout()

        guard let requestId = pendingRequestId else { return }

        if isPositiveAck(message) {
            markCurrentTxnSynced()
        } else {
            print("❌ [TxnQueue] Negative/invalid ACK — parking txn until next connect/retry:", requestId)
            parkedRequestIds.insert(requestId)
        }
        advanceQueue()
    }

    private func isPositiveAck(_ message: String) -> Bool {
        message.contains("|AA|") || message.contains("|AA\r")
    }

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
    private func markCurrentTxnSynced() {
        guard let item = queue.first else { return }
        let bgContext = CoreDataManager.shared.backgroundContext
        TransactionStore.shared.updateSynced(txnId: item.txnId, in: bgContext)
    }

    private func advanceQueue() {
        isSending = false
        pendingRequestId = nil
        pendingAckMessageId = nil
        queue.removeFirst()
        processNext()
    }

    // MARK: - TIMEOUT

    private func scheduleAckTimeout(for requestId: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.processingQueue.async {
                guard let self, self.pendingRequestId == requestId else { return }
                print("⏰ [TxnQueue] ACK timeout — parking txn until next connect/retry:", requestId)
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
