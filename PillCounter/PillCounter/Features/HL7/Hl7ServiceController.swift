//
//  Hl7ServiceController.swift
//  PillCounter
//
//  Created by Bhushan Patil on 04/02/26.
//  Hl7ServiceController.swift
//  PillCounter

import Foundation
import SwiftUI
import Combine

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

    private let pillDataLocalStorage = PillsDataLocalStorage.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - HL7 Layer

    private var hl7Manager: Hl7ServiceManager?
    private var hl7Handler: Hl7EventHandler?

    // MARK: - Send Queue

    /// Ordered queue of transactions waiting to be ACK'd by PMS.
    private var sendingQueue: [PillCountTransactionEntity] = []

    /// The single transaction currently in-flight (waiting for ACK).
    private var currentTxn: PillCountTransactionEntity?
    private var currentMessageId: String?

    private var retryCount = 0
    private let maxRetries = 3

    // MARK: - Init

    private init() {}

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
        observePendingTransactions()
    }

    private var shouldStartService: Bool {
        isLoggedIn && isHl7Enabled && !SecurityManager.isDeviceCompromised()
    }

    // MARK: - Start / Stop

    private func startHl7Services() {
        guard hl7Manager == nil, let handler = hl7Handler else { return }

        print("[HL7CTRL] Starting HL7 services")

        hl7Manager = Hl7ServiceManager(
            port: 2575,
            serviceName: "PillCounterHL7",
            serviceType: pillCounterHostName,
            pmsServiceType: pmsHostName,
            listener: handler
        )
        // Hl7ServiceManager internally starts NWPathMonitor → NWBrowser → Client → Server
    }

    private func stopService() {
        print("[HL7CTRL] Stopping HL7 services")
        hl7Manager?.stop()
        hl7Manager = nil
        resetQueueState()
    }

    // MARK: - Observe Pending Transactions

    private var isObservingPending = false

    private func observePendingTransactions() {
        guard !isObservingPending else { return }
        isObservingPending = true

        pillDataLocalStorage
            .observePendingHl7Transactions()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] txns in
                guard let self else { return }
                // Actual sending is triggered in onClientConnected.
                // This observer is for UI/state awareness only.
            }
            .store(in: &cancellables)
    }

    // MARK: - Events from Hl7EventHandler

    /// PMS client connection is ready — load and start sending pending transactions.
    func onClientConnected() {
        print("[HL7CTRL] Client connected — loading pending transactions")
        resendPendingHl7Transactions()
    }

    /// ACK received from PMS.
    func onAckReceived(messageId: String?, ackCode: String) {
        let ackMsgId = messageId?.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[HL7][ACK] messageId=\(ackMsgId ?? "nil") code=\(ackCode)")

        guard let txn = currentTxn else {
            print("[HL7][ACK] No in-flight txn — ignoring ACK")
            return
        }

        // NACK → retry / move to end
        guard ackCode == "AA" else {
            print("[HL7][ACK] NACK received")
            handleSendFailure()
            return
        }

        // If PMS sent a messageId, it must match what we sent
        if let ackId = ackMsgId, !ackId.isEmpty {
            guard let inflightId = currentMessageId, ackId == inflightId else {
                print("[HL7][ACK] MessageId mismatch — ignoring ACK")
                return
            }
        } else {
            print("[HL7][ACK] No messageId in ACK — accepting (single in-flight rule)")
        }

        // Mark synced in persistence
        pillDataLocalStorage.updateTransactionSynced(txnId: txn.txn_id)
        print("[HL7][ACK] Txn \(txn.txn_id) marked synced")

        // Advance queue
        sendingQueue.removeFirst()
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        sendNextIfPossible()
    }

    /// ACK timeout — treat same as send failure.
    func onAckTimeout() {
        print("[HL7CTRL] ACK timeout")
        handleSendFailure()
    }

    // MARK: - Send Queue Logic

    private func resendPendingHl7Transactions() {
        let pending = pillDataLocalStorage.getPendingHl7Txn()

        guard !pending.isEmpty else {
            print("[HL7CTRL] No pending transactions")
            return
        }

        print("[HL7CTRL] Queuing \(pending.count) pending transaction(s)")

        sendingQueue = pending
        currentTxn = nil
        currentMessageId = nil
        retryCount = 0

        sendNextIfPossible()
    }

    private func sendNextIfPossible() {
        // Already waiting for an ACK
        guard currentTxn == nil else {
            print("[HL7CTRL] In-flight txn exists — waiting for ACK")
            return
        }

        guard !sendingQueue.isEmpty else {
            print("[HL7CTRL] All transactions processed")
            return
        }

        let txn = sendingQueue.first!
        sendTransaction(txn)
    }

    private func sendTransaction(_ txn: PillCountTransactionEntity) {
        currentTxn = txn
        retryCount += 1

        let messageId = "TXN_\(txn.txn_id)_\(Int(Date().timeIntervalSince1970))"
        currentMessageId = messageId

        let hl7 = buildHl7Message(from: txn, messageId: messageId)

        print("[HL7CTRL] Sending txnId=\(txn.txn_id) attempt=\(retryCount)/\(maxRetries)")
        hl7Manager?.sendClientHL7(hl7)
    }

    private func handleSendFailure() {
        guard let txn = currentTxn else { return }

        if retryCount < maxRetries {
            print("[HL7CTRL] Retrying txnId=\(txn.txn_id) attempt \(retryCount + 1)/\(maxRetries)")
            sendTransaction(txn)
            return
        }

        // Max retries exhausted → move to end of queue, try others
        print("[HL7CTRL] Max retries for txnId=\(txn.txn_id) — moving to end of queue")

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
