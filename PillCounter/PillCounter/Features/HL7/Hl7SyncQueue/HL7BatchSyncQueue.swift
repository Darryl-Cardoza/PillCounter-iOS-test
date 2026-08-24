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
            self?.loadAndEnqueuePending()
            self?.processNext()
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

    private func loadAndEnqueuePending() {
        let batches = batchDAO.fetchCompletedUnsynced()
        print("📦 [Queue] Found pending batches:", batches.count)

        for batch in batches {
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

        print("📦 [Queue] Final queue:", queue.map { $0.batchId })
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

        guard
            let batch = batchDAO.fetchById(item.batchId),
            batch.status == CountStatus.COMPLETED.rawValue,
            batch.is_synced == false
        else {
            print("❌ [Queue] Batch invalid or already synced:", item.batchId)
            queue.removeFirst()
            processNext()
            return
        }

        let stockTxns = stockTxnDAO.fetchByBatch(batchId: item.batchId)

        print("📊 [Queue] StockTxns count:", stockTxns.count)

        guard !stockTxns.isEmpty, let userId = batch.user_id, let user = userDAO.fetchByUserId(userId) else {
            print("❌ [Queue] Missing stock txns or user for batch:", item.batchId)
            queue.removeFirst()
            processNext()
            return
        }

        
        let hl7 = hl7Builder.buildInventoryMessage(batch: batch, user: user)
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

    private func markCurrentBatchSynced() {
        guard let item = queue.first else { return }
        DispatchQueue.main.async {
            self.batchDAO.markSynced(batchId: item.batchId)
        }
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
