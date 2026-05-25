//
//  Hl7ServiceController+StockSync.swift.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/04/26.
//

//
//  Hl7ServiceController+StockSync.swift
//  PillCounter
//
//  Wires the queue into the existing Hl7ServiceController.
//  Replaces the old observer + sendBatchInventory extension entirely.
//

import Combine
import Foundation

extension Hl7ServiceController {

    // MARK: - Setup
    // Call once from Hl7ServiceController.init() or wherever you set up HL7.

    func setupBatchSyncQueue() {
        let queue = HL7BatchSyncQueue(
            hl7Builder: HL7CompletionBuilder(),
            hl7Manager: hl7Manager
        )
        self.batchSyncQueue = queue
        observeStorageChanges()
        print("🔧 [HL7] BatchSyncQueue setup complete, queue:", queue)  // temp
    }


    // MARK: - Called from completeBatch() after confirmed Core Data save

    func onBatchCompleted() {
        batchSyncQueue?.enqueueUnsynced()
    }

    // MARK: - Private

    private func observeStorageChanges() {
        batchDAO.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.batchSyncQueue?.enqueueUnsynced()
            }
            .store(in: &cancellables)
    }
}
