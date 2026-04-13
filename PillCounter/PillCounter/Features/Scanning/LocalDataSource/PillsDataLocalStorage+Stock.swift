//
//  PillsDataLocalStorage+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/04/26.
//
import Foundation
import CoreData


extension  PillsDataLocalStorage {
    
    func createBatch(bucketId: String, isFromPms: Bool) -> BatchCountEntity? {
        let context = mainThreadContext

        let batchId = Int64(Date().timeIntervalSince1970 * 1000)

        let batch = BatchCountEntity(context: context)
        batch.batch_id = batchId
        batch.start_date_time = batchId
        batch.status = "partial"
        batch.is_deleted = false
        batch.bucket_id = bucketId
        batch.is_from_pms = isFromPms

        do {
            try context.save()
            return batch
        } catch {
            return nil
        }
    }
    
    
    
    func getTransactionCount(for batchId: Int64) -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "PillCountTransactionEntity")

        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false AND drug.ndc != nil",
            batchId
        )

        request.propertiesToFetch = ["drug.ndc"]
        request.returnsDistinctResults = true
        request.resultType = .dictionaryResultType

        do {
            let results = try mainThreadContext.fetch(request)
            return results.count  
        } catch {
            print("❌ Distinct NDC count failed:", error)
            return 0
        }
    }
    
    
    func fetchAllBatches() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> =
            BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@",
            "partial"
        )
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
    
    func fetchBatchById(_ batchId: Int64) -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false",
            batchId
        )
        request.fetchLimit = 1
        return try? mainThreadContext.fetch(request).first
    }
    
    
    func deleteBatches(ids: Set<Int64>) {
        let context = mainThreadContext

        let batchRequest: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        batchRequest.predicate = NSPredicate(format: "batch_id IN %@", ids)

        let txnRequest: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        txnRequest.predicate = NSPredicate(format: "batch_id IN %@", ids)

        do {
            // Soft-delete batches
            let batches = try context.fetch(batchRequest)
            batches.forEach { $0.is_deleted = true }

            // Soft-delete all child transactions
            let transactions = try context.fetch(txnRequest)
            transactions.forEach { $0.is_deleted = true }

            try context.save()
            print("✅ [Delete] Soft-deleted \(batches.count) batch(es) and \(transactions.count) txn(s)")
        } catch {
            print("❌ [Delete] Failed to delete batches: \(error.localizedDescription)")
        }
    }
}
