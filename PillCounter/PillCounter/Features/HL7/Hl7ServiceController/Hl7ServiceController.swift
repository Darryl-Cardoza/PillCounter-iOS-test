//
//  Hl7ServiceController.swift
//  PillCounter
//
//  Created by Bhushan Patil on 04/02/26.
//

import Foundation
import SwiftUI
import Combine
import ComposeApp

@MainActor
final class Hl7ServiceController: ObservableObject {

    static let shared = Hl7ServiceController()

    // MARK: - App Storage

    @AppStorage(AppStorageManager.AppStorageKeys.isLoggedIn)
    private var isLoggedIn: Bool = false

    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable)
    private var isHl7Enabled: Bool = false

    @AppStorage(AppStorageManager.AppStorageKeys.pmsHostName)
    private var pmsHostName: String = ""

    @AppStorage(AppStorageManager.AppStorageKeys.pillCounterHostName)
    private var pillCounterHostName: String = ""

    // MARK: - Dependencies

    let pillDataLocalStorage = PillsDataLocalStorage.shared
    var cancellables = Set<AnyCancellable>()

    // MARK: - HL7 Layer

    var hl7Manager: Hl7ServiceManager?
    private var hl7Handler: Hl7EventHandler?

    // MARK: - Legacy Send Queue (kept for reference — superseded by queues below)

    private var sendingQueue: [PillCountTransactionEntity] = []
    private var currentTxn: PillCountTransactionEntity?
    private var currentMessageId: String?
    private var retryCount = 0
    private let maxRetries = 3

    // MARK: - Bind (called once from SwiftUI root)

    func bind(
        pillScanViewModel: PillScanViewModel,
        userViewModel: UserViewModel
    ) {
        guard hl7Handler == nil else { return }

        hl7Handler = Hl7EventHandler(
            pillScanViewModel: pillScanViewModel,
            userViewModel: userViewModel
        )
    }

    // MARK: - Entry Point

    /// Called whenever app state changes (login, HL7 toggle, etc.)
    func evaluate() {
        guard shouldStartService else {
            stopService()
            return
        }
        startHl7Services()
        setupBatchSyncQueue()
        setupTxnSyncQueue()
        observeTxnChanges()
        observeBatchCompletion()
    }

    private var shouldStartService: Bool {
        isLoggedIn && isHl7Enabled && !SecurityManager.isDeviceCompromised()
    }

    // MARK: - Start / Stop

    private func startHl7Services() {
        guard hl7Manager == nil, let handler = hl7Handler else { return }

        hl7Manager = Hl7ServiceManager(
            port: 2575,
            serviceName: "Terminal-2",
            serviceType: pillCounterHostName,
            pmsServiceType: pmsHostName,
            listener: handler
        )
    }

    private func stopService() {
        hl7Manager?.stop()
        hl7Manager = nil
        resetQueueState()
    }

    // MARK: - Observe Pending Transactions

    private var isObservingPending = false

    private func observeTxnChanges() {
        pillDataLocalStorage.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                print("🔄 [TxnObserver] Detected change → enqueue txn sync")
                self?.txnSyncQueue?.enqueueUnsynced()
            }
            .store(in: &cancellables)
    }
    
    
    // MARK: - Events from Hl7EventHandler

    /// PMS client connection is ready — start both queues.
    func onClientConnected() {
        print("📡 [HL7] onClientConnected — starting batch + txn queues")
        batchSyncQueue?.enqueueUnsynced()   // batch queue (StockSync)
        txnSyncQueue?.enqueueUnsynced()     // txn queue   (TxnSync)
    }

    /// ACK received from PMS — route to both queues.
    /// Each queue checks its own pendingId and ignores ACKs it didn't send.
    func onAckReceived(messageId: String?, ackCode: String, hl7: String) {
        batchSyncQueue?.handleAck(hl7)
        txnSyncQueue?.handleAck(hl7)
    }

    /// ACK timeout — let each queue's internal timeout handle retries.
    func onAckTimeout() {
        handleSendFailure()
    }

    // MARK: - Legacy Queue Logic (kept intact)

    private func resendPendingHl7Transactions() {
        print("🔄 [HL7] Resend Pending Transactions START")

        let pending = pillDataLocalStorage.fetchCompletedUnsyncedTransactions()
        print("📦 [HL7] Pending Count:", pending.count)
        print("📦 [HL7] Pending Txns:", pending.map { $0.txn_id })

        guard !pending.isEmpty else {
            print("⚠️ [HL7] No pending transactions found")
            return
        }

        sendingQueue = pending
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        sendNextIfPossible()
    }

    private func sendNextIfPossible() {
        guard currentTxn == nil else { return }
        guard !sendingQueue.isEmpty else { return }

        let txn = sendingQueue.first!
        sendTransaction(txn)
    }

    func sendTransaction(_ txn: PillCountTransactionEntity) {
        currentTxn = txn
        retryCount += 1

        let messageId = "TXN_\(txn.txn_id)_\(Int(Date().timeIntervalSince1970))"
        currentMessageId = messageId

        let hl7 = buildHl7Message(txn: txn)
        hl7Manager?.sendClientHL7(hl7)
    }

    private func handleSendFailure() {
        guard let txn = currentTxn else { return }

        if retryCount < maxRetries {
            sendTransaction(txn)
            return
        }

        sendingQueue.removeFirst()
        sendingQueue.append(txn)

        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        sendNextIfPossible()
    }

    private func resetQueueState() {
        sendingQueue.removeAll()
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0
    }

    // MARK: - HL7 Message Builder

    private func buildHl7Message(txn: PillCountTransactionEntity) -> String {
        guard let user = txn.user else {
            print("❌ [HL7] Missing user for txn:", txn.txn_id)
            return ""
        }
        return HL7CompletionBuilder().buildCompletionMessage(txn: txn, user: user)
    }

    private func hl7Timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }
}
