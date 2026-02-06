//
//  Hl7ServiceController.swift
//  PillCounter
//
//  Created by Bhushan Patil on 04/02/26.
//  Hl7ServiceController.swift
//  PillCounter
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class Hl7ServiceController: ObservableObject {

    static let shared = Hl7ServiceController()

    // MARK: - App State

    @AppStorage(AppStorageManager.AppStorageKeys.isLoggedIn)
    private var isLoggedIn: Bool = false

    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable)
    private var isHl7Enabled: Bool = false

    @AppStorage(AppStorageManager.AppStorageKeys.pmsHostName)
    private var pmsHostName: String = ""

    @AppStorage(AppStorageManager.AppStorageKeys.pillCounterHostName)
    private var pillCounterHostName: String = ""

    // MARK: - Dependencies

    private let pillDataLocalStorage = PillsDataLocalStorage.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - HL7 Infra

    private var hl7Manager: Hl7ServiceManager?
    private var hl7Handler: Hl7EventHandler?

    // Track in-flight messages (messageId → txnId)
    private var sendingQueue: [Int64] = []
    // Prevent duplicate resend
    private var hasResentPending = false

    private init() {}

    // MARK: - Binding (called once from SwiftUI root)

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

    func evaluate() {
        guard shouldStartService else {
            stopService()
            return
        }

        startServiceIfNeeded()
    }

    private var shouldStartService: Bool {
        isLoggedIn && isHl7Enabled && !SecurityManager.isDeviceCompromised()
    }

    // MARK: - Service Lifecycle

    private func startServiceIfNeeded() {
        guard hl7Manager == nil, let handler = hl7Handler else { return }

        hl7Manager = Hl7ServiceManager(
            port: 2575,
            serviceName: "PillCounterHL7",
            serviceType: pillCounterHostName,
            pmsServiceType: pmsHostName,
            listener: handler
        )

        do {
            try hl7Manager?.start()
        } catch {
            print("❌ Failed to start HL7 service: \(error)")
        }
    }

    private func stopService() {
        hl7Manager?.stop()
        hl7Manager = nil
        hasResentPending = false
    }

    // MARK: - Observe Pending Transactions (Android Flow.collect)

    private var isObservingPending = false

    private func observePendingTransactions() {
        guard !isObservingPending else { return }
        isObservingPending = true

        pillDataLocalStorage
            .observePendingHl7Transactions()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] txns in
                guard let self else { return }

                guard !txns.isEmpty else {
                    self.hasResentPending = false
                    return
                }

                print("Pending HL7 txns detected: \(txns.count)")
                self.startClient()
            }
            .store(in: &cancellables)
    }


    // MARK: - Client Control

    func startClient() {
        guard let hl7Manager else {
            print("HL7 service not running")
            return
        }
        hl7Manager.startClient()
    }

    func stopClient() {
        hl7Manager?.disconnectClient()
        hasResentPending = false
    }

    // MARK: - EVENTS (called from Hl7EventHandler)

    /// PMS connected
    func onClientConnected() {
        resendPendingHl7Transactions()
    }

    func onAckReceived(messageId: String) {

        print("[HL7][ACK] received")

        guard !sendingQueue.isEmpty else {
            print("[HL7][ACK] No pending txn to sync")
            return
        }

        let syncedTxnId = sendingQueue.removeFirst()

        print("[HL7][ACK] Syncing txnId =", syncedTxnId)

        pillDataLocalStorage.updateTransactionSynced(txnId: syncedTxnId)

        // Send next message automatically
        sendNextIfPossible()
    }


    // MARK: - Resend Logic (Android resendPendingHl7Transactions)
    private func resendPendingHl7Transactions() {
        let pending = pillDataLocalStorage.getPendingHl7TxnOnce()

        guard !pending.isEmpty else {
            print("[HL7] No pending transactions")
            return
        }

        // Build FIFO queue
        sendingQueue = pending.map { $0.txn_id }

        print("[HL7] Sending queue:", sendingQueue)

        sendNextIfPossible()
    }

    
    private func sendNextIfPossible() {
        guard let nextTxnId = sendingQueue.first else {
            print("[HL7] Queue empty, nothing to send")
            return
        }

        guard let txn = pillDataLocalStorage
            .fetchPillCountTransactionByTransactionId(txnId: nextTxnId) else {
            sendingQueue.removeFirst()
            sendNextIfPossible()
            return
        }

        let messageId = "TXN_\(txn.txn_id)_\(Int(Date().timeIntervalSince1970))"
        let hl7 = buildHl7Message(from: txn, messageId: messageId)

        print("[HL7] Sending txnId =", txn.txn_id)
        hl7Manager?.sendClientHL7(hl7)
    }
    

    // MARK: - Send HL7
    private func sendTransaction(_ txn: PillCountTransactionEntity) {
        let messageId = "TXN_\(txn.txn_id)_\(Int(Date().timeIntervalSince1970))"
        let hl7 = buildHl7Message(from: txn, messageId: messageId)
        hl7Manager?.sendClientHL7(hl7)
        print("HL7 sent | txnId=\(txn.txn_id) | messageId=\(messageId)")
    }

    
    private func buildHl7Message(
        from txn: PillCountTransactionEntity,
        messageId: String
    ) -> String {

        let timestamp = hl7Timestamp()

        let msh = [
            "MSH",
            "|",
            "^~\\&",
            "PILLCOUNTER",
            "PC",
            "PMS",
            "PMS",
            timestamp,
            "",
            "ORM^O01",
            messageId,
            "P",
            "2.3"
        ].joined(separator: "|")

        return msh + "\r"
    }
    private func hl7Timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

}
