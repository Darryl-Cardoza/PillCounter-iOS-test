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
    var retryCount: Int = 0
    static let maxRetries = 3
}

// MARK: - HL7TxnSyncQueue
final class HL7TxnSyncQueue {

    private let storage: PillsDataLocalStorage
    private let hl7Builder: HL7CompletionBuilder
    private weak var hl7Manager: Hl7ServiceManager?

    private var queue: [TxnSyncQueueItem] = []
    private var isSending = false
    private var pendingRequestId: String?
    private var ackTimeoutWork: DispatchWorkItem?

    private let ackTimeoutSeconds: TimeInterval = 10
    private let processingQueue = DispatchQueue(label: "hl7.txn.sync.queue", qos: .utility)

    init(
        storage: PillsDataLocalStorage,
        hl7Builder: HL7CompletionBuilder,
        hl7Manager: Hl7ServiceManager?
    ) {
        self.storage     = storage
        self.hl7Builder  = hl7Builder
        self.hl7Manager  = hl7Manager
    }

    // MARK: - PUBLIC

    func enqueueUnsynced() {
        processingQueue.async { [weak self] in
            self?.loadAndEnqueuePending()
            self?.processNext()
        }
    }

    func handleAck(_ ackMessage: String) {
        processingQueue.async { [weak self] in
            self?.processAck(ackMessage)
        }
    }

    // MARK: - LOAD

    private func loadAndEnqueuePending() {
        let txns = storage.fetchCompletedUnsyncedTransactions()
        print("📦 [TxnQueue] Found pending txns:", txns.count)

        for txn in txns {
            let txnId = txn.txn_id
            let requestId = resolvedRequestId(for: txn)

            guard !queue.contains(where: { $0.requestId == requestId }) else {
                print("⚠️ [TxnQueue] Duplicate requestId:", requestId)
                continue
            }

            queue.append(TxnSyncQueueItem(txnId: txnId, requestId: requestId))
            print("✅ [TxnQueue] Enqueued txn:", txnId)
        }

        print("📦 [TxnQueue] Final queue:", queue.map { $0.txnId })
    }

    // MARK: - PROCESS

    private func processNext() {
        guard !isSending, let item = queue.first else { return }

        guard
            let txn = storage.fetchPillCountTransactionByTransactionId(txnId: item.txnId),
            txn.is_synced == false,
            txn.status == CountStatus.COMPLETED.rawValue
        else {
            queue.removeFirst()
            processNext()
            return
        }

        guard let user = txn.user else {
            queue.removeFirst()
            processNext()
            return
        }

        let hl7 = hl7Builder.buildCompletionMessage(txn: txn, user: user)
        print("hl7\(hl7)")
        guard let manager = hl7Manager, !hl7.isEmpty else {
            print("❌ [TxnQueue] HL7 invalid or manager nil")
            return
        }

        isSending = true
        pendingRequestId = item.requestId

        DispatchQueue.main.async {
            manager.sendClientHL7(hl7)
        }

        scheduleAckTimeout(for: item.requestId)
    }

    // MARK: - ACK

    private func processAck(_ message: String) {
        cancelAckTimeout()

        guard let requestId = pendingRequestId else { return }

        if isPositiveAck(message) {
            markCurrentTxnSynced()
            advanceQueue()
        } else {
            handleRetry()
        }
    }

    private func isPositiveAck(_ message: String) -> Bool {
        message.contains("|AA|") || message.contains("|AA\r")
    }

    private func markCurrentTxnSynced() {
        guard let item = queue.first else { return }

        DispatchQueue.main.async {
            self.storage.updateTransactionSynced(txnId: item.txnId)
        }
    }

    private func advanceQueue() {
        isSending = false
        pendingRequestId = nil
        queue.removeFirst()
        processNext()
    }

    private func handleRetry() {
        guard !queue.isEmpty else { return }

        queue[0].retryCount += 1

        if queue[0].retryCount >= TxnSyncQueueItem.maxRetries {
            let failed = queue.removeFirst()
            queue.append(failed)
        }

        isSending = false
        pendingRequestId = nil

        processingQueue.asyncAfter(deadline: .now() + 2.0) {
            self.processNext()
        }
    }

    // MARK: - TIMEOUT

    private func scheduleAckTimeout(for requestId: String) {
        let work = DispatchWorkItem { [weak self] in
            self?.processingQueue.async {
                guard self?.pendingRequestId == requestId else { return }
                self?.handleRetry()
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
}
