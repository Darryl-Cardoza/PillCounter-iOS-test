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
            self?.loadAndEnqueuePending()
            self?.processNext()
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

    private func loadAndEnqueuePending() {
        let txns = transactionDAO.fetchCompletedUnsynced()
        print("📦 [TxnQueue] Found pending txns:", txns.count)

        for txn in txns {
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

        print("📦 [TxnQueue] Final queue:", queue.map { $0.txnId })
    }

    // MARK: - PROCESS

    private func processNext() {
        guard !isSending, let item = queue.first else { return }

        guard
            let txn = transactionDAO.fetchById(item.txnId),
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

    private func markCurrentTxnSynced() {
        guard let item = queue.first else { return }

        DispatchQueue.main.async {
            TransactionStore.shared.updateSynced(txnId: item.txnId)
        }
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
