//
//  Hl7ServiceController+TxnSync.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//

import Combine
import Foundation

extension Hl7ServiceController {

    // MARK: - Setup
    // Called from evaluate(). Guard prevents duplicate queue on repeated evaluate() calls.

    func setupTxnSyncQueue() {
        guard txnSyncQueue == nil else {
            print("⚠️ [TxnSync] Already set up — skipping")
            return
        }
        let queue = HL7TxnSyncQueue(
            hl7Builder: HL7CompletionBuilder(),
            hl7Manager: hl7Manager
        )
        self.txnSyncQueue = queue
        print("🔧 [HL7] TxnSyncQueue setup complete")
        // ⚠️ Storage observation is centralised in setupStorageObserver()
        // in Hl7ServiceController.swift — do NOT add another subscriber here.
    }

    // MARK: - Called by socket layer when client connects / reconnects

    func onClientConnectedTxn() {
        print("📡 [TxnSync] onClientConnected — enqueuing pending txns")
        txnSyncQueue?.enqueueUnsynced()
    }

    // MARK: - Called from Hl7EventHandler when ACK arrives

    func onTxnAckReceived(messageId: String?, hl7: String) {
        txnSyncQueue?.handleAck(messageId: messageId, hl7: hl7)
    }

    // MARK: - Called after a transaction is saved in CoreData

    func onTransactionSaved() {
        txnSyncQueue?.enqueueUnsynced()
    }
}
