//
//  Hl7ServiceController+SyncQueueStorage.swift.swift
//  PillCounter
//
//  Created by Bhushan Patil on 24/04/26.
//

//
//  Hl7ServiceController+SyncQueueStorage.swift
//  PillCounter
//
//  Stores batchSyncQueue as an associated object on Hl7ServiceController
//  so it survives without requiring a stored property in the main class.
//

import Foundation

private enum SyncQueueKey {
    static var key: UInt8 = 0
}

extension Hl7ServiceController {
  
    var batchSyncQueue: HL7BatchSyncQueue? {
        get {
            objc_getAssociatedObject(self, &SyncQueueKey.key) as? HL7BatchSyncQueue
        }
        set {
            objc_setAssociatedObject(
                self,
                &SyncQueueKey.key,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
    
    
//    // MARK: - Observer For completion of batch
    func observeBatchCompletion() {
        batchDAO.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.batchSyncQueue?.enqueueUnsynced()
            }
            .store(in: &cancellables)
    }

    func sendBatchInventory(batchId: Int64) {
        guard
            let batch = batchDAO.fetchById(batchId),
            batch.status == CountStatus.COMPLETED.rawValue,
            batch.is_synced == false,
            batch.req_id_from_pms != nil
        else { return }

        let stockTxns = StockTxnStore.shared.fetchByBatch(batchId: batchId)

        guard
            !stockTxns.isEmpty,
            let userId = batch.user_id,
            let user = UserStore.shared.fetchByUserId(userId)
        else { return }

        let hl7 = HL7CompletionBuilder().buildInventoryMessage(batch: batch, user: user)
        hl7Manager?.sendHL7ToPMS(hl7, orderId: batch.bucket_id)

        batchDAO.markSynced(batchId: batchId)
    }
}
