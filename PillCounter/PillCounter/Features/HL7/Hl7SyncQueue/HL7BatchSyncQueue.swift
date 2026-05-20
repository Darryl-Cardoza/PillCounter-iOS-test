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
    var retryCount: Int = 0
    static let maxRetries = 3
}

// MARK: - HL7BatchSyncQueue

final class HL7BatchSyncQueue {

    // MARK: Dependencies
    private let batchDAO = BatchDAO.shared
    private let transactionDAO = TransactionDAO.shared
    private let hl7Builder: HL7CompletionBuilder
    private weak var hl7Manager: Hl7ServiceManager?           // your existing socket manager

    // MARK: State
    private var queue: [SyncQueueItem] = []
    private var isSending = false
    private var pendingRequestId: String?              // ACK correlation
    private var ackTimeoutWork: DispatchWorkItem?

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

    /// Call with the raw ACK string received from the PMS socket.
    func handleAck(_ ackMessage: String) {
        processingQueue.async { [weak self] in
            self?.processAck(ackMessage)
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

        let txns = transactionDAO.fetchByBatch(batchId: item.batchId)

        print("📊 [Queue] Transactions count:", txns.count)
        
        guard !txns.isEmpty, let user = txns.first?.user else {
            print("❌ [Queue] Missing txns or user for batch:", item.batchId)
            queue.removeFirst()
            processNext()
            return
        }

        
        // Persist the resolved requestId back to Core Data if it was generated
        if batch.req_id_from_pms == nil {
            print("💾 [Queue] Persisting generated requestId:", item.requestId)
            persistGeneratedRequestId(item.requestId, for: batch)
        }

        let hl7 = hl7Builder.buildInventoryMessage(batch: batch, user: user)
        print("hl7\(hl7)")
        print("📡 [HL7] Sending batch:", item.batchId,
              "| requestId:", item.requestId)

        isSending        = true
        pendingRequestId = item.requestId

        DispatchQueue.main.async { [weak self] in
            self?.hl7Manager?.sendClientHL7(hl7)
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
            advanceQueue()
        } else {
            handleNackOrInvalid()
        }
    }

    private func isPositiveAck(_ message: String) -> Bool {
        return message.contains("|AA|") || message.contains("|AA\r")
    }

    private func markCurrentBatchSynced() {
        guard let item = queue.first,
              let batch = batchDAO.fetchById(item.batchId) else { return }

        DispatchQueue.main.async {
            batch.is_synced = true
            try? CoreDataManager.shared.context.save()
        }
    }

    private func advanceQueue() {
        isSending        = false
        pendingRequestId = nil
        if !queue.isEmpty { queue.removeFirst() }
        processNext()
    }

    private func handleNackOrInvalid() {
        guard !queue.isEmpty else {
            isSending = false
            return
        }

        queue[0].retryCount += 1

        if queue[0].retryCount >= SyncQueueItem.maxRetries {
            // Move to end — do not block other batches
            let failed = queue.removeFirst()
            queue.append(failed)
        }

        isSending        = false
        pendingRequestId = nil

        // Back-off before next attempt
        processingQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.processNext()
        }
    }

    // MARK: - Private: ACK Timeout

    private func scheduleAckTimeout(for requestId: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.processingQueue.async {
                guard self?.pendingRequestId == requestId else { return }
                self?.handleNackOrInvalid()
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

    private func persistGeneratedRequestId(_ requestId: String, for batch: BatchCountEntity) {
        DispatchQueue.main.async {
            batch.req_id_from_pms = "REQ\(String(batch.batch_id))"
            try? CoreDataManager.shared.context.save()
        }
    }
}
