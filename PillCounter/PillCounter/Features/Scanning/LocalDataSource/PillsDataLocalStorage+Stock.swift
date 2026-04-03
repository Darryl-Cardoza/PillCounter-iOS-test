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
        
        entity.start_date_time = batchId
        
        CoreDataManager.shared.save(context: mainThreadContext)

        return batchId
    }
    
    func getTransactionCount(for batchId: Int64) -> Int {
        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false",
            batchId
        )

        return (try? mainThreadContext.count(for: request)) ?? 0
    }
    
    
    func fetchAllBatches() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> =
            BatchCountEntity.fetchRequest()

        request.predicate = NSPredicate(format: "is_deleted == false")

        request.sortDescriptors = [
            NSSortDescriptor(key: "start_date_time", ascending: false)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }
    
    
    func fetchTransactionsByBatch(batchId: Int64) -> [PillCountTransactionEntity] {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false",
            batchId
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: false)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }
    
    
    
}
