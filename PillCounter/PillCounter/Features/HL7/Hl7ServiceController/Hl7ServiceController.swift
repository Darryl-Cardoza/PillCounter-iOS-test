//
//  Hl7ServiceController.swift
//  PillCounter
//

import Foundation
import SwiftUI
import Combine
import Hl7Core

@MainActor
final class Hl7ServiceController: ObservableObject {

    static let shared = Hl7ServiceController()

    // MARK: - App Storage

    // selectedTerminalName is UserDefaults-backed — @AppStorage is valid here.
    @AppStorage(AppStorageManager.AppStorageKeys.selectedTerminalName)
    private var selectedTerminalName: String = ""

    // MARK: - Dependencies

    let transactionDAO = TransactionStore.shared
    let batchDAO = BatchStore.shared
    var cancellables = Set<AnyCancellable>()

    // MARK: - HL7 Layer
    var hl7Manager: Hl7ServiceManager?
    private var hl7Handler: Hl7EventHandler?

    // MARK: - Legacy Send Queue
    private var sendingQueue: [PillCountTransactionEntity] = []
    private var currentTxn: PillCountTransactionEntity?
    private var currentMessageId: String?
    private var retryCount = 0
    private let maxRetries = 3

    // MARK: - Bind (called once from SwiftUI root)
    func bind(pillScanViewModel: PillScanViewModel, userViewModel: UserViewModel) {
        guard hl7Handler == nil else { return }
        hl7Handler = Hl7EventHandler(
            pillScanViewModel: pillScanViewModel,
            userViewModel: userViewModel
        )
    }

    // MARK: - Entry Point
    func evaluate() {
        print("===== HL7 Service Evaluation =====")
        print("isLoggedIn: \(AppStorageManager.shared.isLoggedIn)")
        print("isPmsIntegrated: \(AppStorageManager.shared.isPmsIntegrated)")
        print("isDeviceCompromised: \(SecurityManager.isDeviceCompromised())")
        print("shouldStartService: \(shouldStartService)")
        print("=================================")
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
        AppStorageManager.shared.isLoggedIn
            && AppStorageManager.shared.isPmsIntegrated
            && !SecurityManager.isDeviceCompromised()
    }

    // MARK: - Start / Stop

    private func startHl7Services() {
        guard hl7Manager == nil, let handler = hl7Handler else { return }

        let serviceName = selectedTerminalName.isEmpty ? "Terminal-1" : selectedTerminalName
        hl7Manager = Hl7ServiceManager(
            port: 2575,
            serviceName: serviceName,
            serviceType: AppStorageManager.shared.pillCounterHostName,
            pmsServiceType: AppStorageManager.shared.pmsHostName,
            listener: handler
        )
    }

    /// Call this after a terminal update so HL7 rebroadcasts with the new name.
    func restartForTerminalChange() {
        guard shouldStartService else { return }
        stopService()
        startHl7Services()
        setupBatchSyncQueue()
        setupTxnSyncQueue()
        observeTxnChanges()
        observeBatchCompletion()
    }

    /// Call this after loadMobileThemeSettings() successfully writes
    /// pmsHostName and pillCounterHostName to AppStorageManager.
    /// If the manager was created before settings arrived (empty service type),
    /// this triggers the first real Bonjour browse.
    func notifySettingsUpdated() {
        guard shouldStartService else { return }

        if hl7Manager == nil {
            // Manager wasn't created yet at all — start fresh now
            startHl7Services()
            setupBatchSyncQueue()
            setupTxnSyncQueue()
            observeTxnChanges()
            observeBatchCompletion()
        } else {
            // Manager exists but was stuck with an empty pmsServiceType —
            // pass the now-populated value so the browser can start.
            hl7Manager?.restartBrowsingIfNeeded(pmsServiceType: AppStorageManager.shared.pmsHostName)
        }
    }

    private func stopService() {
        hl7Manager?.stop()
        hl7Manager = nil
        resetQueueState()
    }

    // MARK: - Observe Pending Transactions

    private func observeTxnChanges() {
        transactionDAO.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Log("🔄 [TxnObserver] Detected change → enqueue txn sync")
                self?.txnSyncQueue?.enqueueUnsynced()
                self?.transactionDAO.sweepStaleSyncedTransactions(olderThan: Self.retentionMaxAge)
            }
            .store(in: &cancellables)
    }

    /// Backstop TTL for transactions whose PMS image delivery never
    /// completes — see TransactionStore.sweepStaleSyncedTransactions.
    private static let retentionMaxAge: TimeInterval = 24 * 60 * 60

    // MARK: - Events from Hl7EventHandler

    func onClientConnected() {
        Log("📡 [HL7] onClientConnected — starting batch + txn queues")
        batchSyncQueue?.enqueueUnsynced()
        txnSyncQueue?.enqueueUnsynced()
    }

    func onAckReceived(messageId: String?, ackCode: String, hl7: String) {
        batchSyncQueue?.handleAck(hl7)
        txnSyncQueue?.handleAck(hl7)
    }

    func onAckTimeout() {
        handleSendFailure()
    }

    // MARK: - Legacy Queue Logic

    private func resendPendingHl7Transactions() {
        print("🔄 [HL7] Resend Pending Transactions START")

        let pending = transactionDAO.fetchCompletedUnsynced()
        print("📦 [HL7] Pending Count:", pending.count)
        print("📦 [HL7] Pending Txns:", pending.map { $0.txn_id })

        guard !pending.isEmpty else {
            Log("⚠️ [HL7] No pending transactions found")
            return
        }
        sendingQueue   = pending
        currentTxn     = nil
        currentMessageId = nil
        retryCount     = 0
        sendNextIfPossible()
    }

    private func sendNextIfPossible() {
        guard currentTxn == nil, !sendingQueue.isEmpty else { return }
        sendTransaction(sendingQueue.first!)
    }

    func sendTransaction(_ txn: PillCountTransactionEntity) {
        currentTxn = txn
        retryCount += 1
        let messageId = "TXN_\(txn.txn_id)_\(Int(Date().timeIntervalSince1970))"
        currentMessageId = messageId
        hl7Manager?.sendClientHL7(buildHl7Message(txn: txn))
    }

    private func handleSendFailure() {
        guard let txn = currentTxn else { return }
        if retryCount < maxRetries {
            sendTransaction(txn)
            return
        }
        sendingQueue.removeFirst()
        sendingQueue.append(txn)
        currentTxn       = nil
        currentMessageId = nil
        retryCount       = 0
        sendNextIfPossible()
    }

    private func resetQueueState() {
        sendingQueue.removeAll()
        currentTxn       = nil
        currentMessageId = nil
        retryCount       = 0
    }

    // MARK: - HL7 Message Builder

    private func buildHl7Message(txn: PillCountTransactionEntity) -> String {
        guard let user = txn.user else {
            Log("❌ [HL7] Missing user for txn: \(txn.txn_id)")
            return ""
        }
        return HL7CompletionBuilder().buildCompletionMessage(txn: txn, user: user)
    }
}
