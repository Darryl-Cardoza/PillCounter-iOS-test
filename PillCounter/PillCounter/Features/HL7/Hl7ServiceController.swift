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


    // Prevent duplicate resend
    private var hasResentPending = false

    
    // Queue holds txn objects, not IDs
    private var sendingQueue: [PillCountTransactionEntity] = []

    // In-flight state
    private var currentTxn: PillCountTransactionEntity?
    private var currentMessageId: String?

    private var retryCount = 0
    private let maxRetries = 3
    
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

    func onAckReceived(messageId: String?, ackCode: String) {

        let ackMsgId = messageId?.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[HL7][ACK] messageId=\(ackMsgId ?? "nil"), code=\(ackCode)")

        guard let txn = currentTxn else {
            print("[HL7][ACK] No in-flight txn, ignoring ACK")
            return
        }

        // Reject NACK always
        guard ackCode == "AA" else {
            print("[HL7][ACK] NACK received")
            handleSendFailure()
            return
        }

        // ONLY compare if PMS actually sent a messageId
        if let ackId = ackMsgId, !ackId.isEmpty {
            guard let inflightId = currentMessageId,
                  ackId == inflightId else {
                print("[HL7][ACK] MessageId mismatch, ignoring ACK")
                return
            }
        } else {
            print("[HL7][ACK] No messageId in ACK, accepting based on single in-flight rule")
        }

        pillDataLocalStorage.updateTransactionSynced(txnId: txn.txn_id)

        print("[HL7][ACK] Txn synced")

        sendingQueue.removeFirst()
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        sendNextIfPossible()
    }




    // MARK: - Resend Logic (Android resendPendingHl7Transactions)
    private func resendPendingHl7Transactions() {
        let pending = pillDataLocalStorage.getPendingHl7Txn()

        guard !pending.isEmpty else {
            print("[HL7] No pending transactions")
            return
        }

        sendingQueue = pending
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        sendNextIfPossible()
    }

    
    private func sendNextIfPossible() {

        // If something is already in-flight, wait
        guard currentTxn == nil else {
            print("[HL7] Waiting for ACK")
            return
        }

        guard !sendingQueue.isEmpty else {
            print("[HL7] All transactions processed")
//            stopClient()
            return
        }

        let txn = sendingQueue.first!
        sendTransaction(txn)
    }

    

    // MARK: - Send HL7
    private func sendTransaction(_ txn: PillCountTransactionEntity) {

        currentTxn = txn
        retryCount += 1

        let messageId = "TXN_\(txn.txn_id)_\(Int(Date().timeIntervalSince1970))"
        currentMessageId = messageId

        let hl7 = buildHl7Message(from: txn, messageId: messageId)

        print("[HL7] Sending txnId=\(txn.txn_id), attempt=\(retryCount)")
        hl7Manager?.sendClientHL7(hl7)
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

    
    private func handleSendFailure() {

        guard let txn = currentTxn else { return }

        if retryCount < maxRetries {
            print("[HL7] Retrying txnId=\(txn.txn_id)")
            sendTransaction(txn)
            return
        }

        // After 3 attempts → move to end of queue
        print("[HL7] Moving txnId=\(txn.txn_id) to end of queue")

        // Remove from front
        sendingQueue.removeFirst()

        // Append to end
        sendingQueue.append(txn)

        // Reset state
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        // Pick next txn
        sendNextIfPossible()
    }
    
    func onAckTimeout() {
        print("[HL7] ACK timeout")
        handleSendFailure()
    }
}
