//
//  PillsDataLocalStorage+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/04/26.
//
import Foundation
import CoreData


extension  PillsDataLocalStorage {
    
    func createBatch(
        bucketId: String? = nil,
        note: String? = nil,
        status: String = "ACTIVE"
    ) -> Int64 {
        
        let batchId = Int64(Date().timeIntervalSince1970 * 1000)

        let entity = BatchCountEntity(context: mainThreadContext)
        
        entity.batch_id = batchId
        entity.bucket_id = bucketId
        entity.note = note
        entity.status = status
        entity.is_deleted = false
        
        entity.start_date_time = String(batchId)
        entity.end_date_time = nil
        
        CoreDataManager.shared.save(context: mainThreadContext)

        return batchId
    }
    
    
//    func assignTransactionToBatch(
//        txnId: Int64,
//        batchId: Int64
//    ) {
//        guard let txn = fetchPillCountTransactionByTransactionId(txnId: txnId) else {
//            print("❌ txn not found")
//            return
//        }
//
//        txn.batch_id = batchId
//        
//        CoreDataManager.shared.save(context: mainThreadContext)
//    }
//    
//    
//    func fetchTransactionsByBatch(
//        batchId: Int64,
//        countType: CountType
//    ) -> [PillCountTransactionEntity] {
//        
//        let request: NSFetchRequest<PillCountTransactionEntity> =
//            PillCountTransactionEntity.fetchRequest()
//
//        request.predicate = NSPredicate(
//            format: "batch_id == %lld AND count_type == %@ AND is_deleted == false",
//            batchId,
//            countType.rawValue
//        )
//
//        request.sortDescriptors = [
//            NSSortDescriptor(key: "created_at", ascending: false)
//        ]
//
//        return (try? mainThreadContext.fetch(request)) ?? []
//    }
//    
//    func fetchAllBatches() -> [BatchCountEntity] {
//        
//        let request: NSFetchRequest<BatchCountEntity> =
//            BatchCountEntity.fetchRequest()
//
//        request.predicate = NSPredicate(format: "is_deleted == false")
//
//        request.sortDescriptors = [
//            NSSortDescriptor(key: "start_date_time", ascending: false)
//        ]
//
//        return (try? mainThreadContext.fetch(request)) ?? []
//    }
//    
//    func fetchBatchesByCountType(
//        countType: CountType
//    ) -> [BatchCountEntity] {
//
//        let allBatches = fetchAllBatches()
//
//        return allBatches.filter { batch in
//            let txns = fetchTransactionsByBatch(
//                batchId: Int64(batch.batch_id ?? 0) ?? 0,
//                countType: countType
//            )
//            return !txns.isEmpty
//        }
//    }
}
