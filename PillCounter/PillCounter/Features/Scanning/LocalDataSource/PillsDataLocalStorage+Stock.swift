//
//  PillsDataLocalStorage+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/04/26.
//
import Foundation
import CoreData
import Combine

extension PillsDataLocalStorage {

    // MARK: - Reactive publisher
    //
    // Fired after every write that affects batches or transactions.
    // StockCountViewModel subscribes once in init() and reloads all
    // derived state automatically — no manual reload calls needed at call sites.
    //
    // Declared as a stored property via associated objects so it lives on the
    // shared instance without requiring a stored-property extension.

    private enum AssociatedKeys {
        // Must be a stored var — UnsafeRawPointer needs a stable address
        static var subject: UInt8 = 0  
    }

    var transactionsDidChange: PassthroughSubject<Void, Never> {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.subject)
            as? PassthroughSubject<Void, Never> {
            return existing
        }
        let subject = PassthroughSubject<Void, Never>()
        objc_setAssociatedObject(
            self,
            &AssociatedKeys.subject,
            subject,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return subject
    }
    
    
    // MARK: - Create batch
    func createBatch(
        bucketId: String,
        requestId: String? = nil
    ) -> BatchCountEntity? {
        let context = mainThreadContext
        let batchId = Int64(Date().timeIntervalSince1970 * 1000)

        let batch = BatchCountEntity(context: context)
        batch.batch_id        = batchId
        batch.start_date_time = batchId
        batch.status          = CountStatus.PARTIAL.rawValue
        batch.is_deleted      = false
        batch.bucket_id       = bucketId
        batch.req_id_from_pms = requestId
        batch.is_synced = false
        
        do {
            try context.save()
            debugPrintFullDatabase()
            transactionsDidChange.send()
            return batch
        } catch {
            print("❌ [createBatch] Save failed:", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Delete batches
    func deleteBatches(ids: Set<Int64>) {
        let context = mainThreadContext

        let batchRequest: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        batchRequest.predicate = NSPredicate(format: "batch_id IN %@", ids)

        let txnRequest: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()
        txnRequest.predicate = NSPredicate(format: "batch_id IN %@", ids)

        do {
            let batches = try context.fetch(batchRequest)
            batches.forEach { $0.is_deleted = true }

            let transactions = try context.fetch(txnRequest)
            transactions.forEach { $0.is_deleted = true }

            try context.save()
            transactionsDidChange.send()
            print("✅ [Delete] Soft-deleted \(batches.count) batch(es) and \(transactions.count) txn(s)")
        } catch {
            print("❌ [Delete] Failed:", error.localizedDescription)
        }
    }

    // MARK: - Read-only fetches (no publisher call needed)
    func getTransactionCount(for batchId: Int64) -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "PillCountTransactionEntity")
        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false AND drug.ndc != nil",
            batchId
        )
        request.propertiesToFetch  = ["drug.ndc"]
        request.returnsDistinctResults = true
        request.resultType         = .dictionaryResultType

        do {
            return try mainThreadContext.fetch(request).count
        } catch {
            print("❌ Distinct NDC count failed:", error)
            return 0
        }
    }

    func fetchAllBatches() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@", CountStatus.PARTIAL.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        return (try? mainThreadContext.fetch(request)) ?? []
    }

    func fetchCompletedBatches() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@", CountStatus.COMPLETED.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        return (try? mainThreadContext.fetch(request)) ?? []
    }

    func fetchTransactionsByBatch(batchId: Int64) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false", batchId
        )
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        return (try? mainThreadContext.fetch(request)) ?? []
    }

    func fetchBatchById(_ batchId: Int64) -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false", batchId
        )
        request.fetchLimit = 1
        return try? mainThreadContext.fetch(request).first
    }

    func fetchLastCreatedBatch() -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate    = NSPredicate(format: "is_deleted == false")
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        request.fetchLimit   = 1
        do {
            return try mainThreadContext.fetch(request).first
        } catch {
            print("❌ fetchLastCreatedBatch failed:", error)
            return nil
        }
    }
    
    func getBatchesForUserFilteredByDate(
        startDateTs: Int64,
        endDateTs: Int64
    ) -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld",
            startDateTs, endDateTs
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        return (try? mainThreadContext.fetch(request)) ?? []
    }
    
    
    // Fetch No Send to pms batches
    func fetchCompletedUnsyncedBatches() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@ AND is_synced == false",
            CountStatus.COMPLETED.rawValue
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "start_date_time", ascending: true)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }
    
    func updateBatchStatus(batchId: Int64, status: CountStatus, completion: (() -> Void)? = nil) {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld", batchId)

        if let batch = try? mainThreadContext.fetch(request).first {
            batch.status = status.rawValue
            batch.is_synced = false  // ensure it's picked up as unsynced

            do {
                try mainThreadContext.save()         // ← explicit save, not CoreDataManager.shared.save
                print("✅ Batch status updated to \(status)")
                completion?()                        // ← fires AFTER confirmed save
            } catch {
                print("❌ updateBatchStatus save failed:", error)
            }
        } else {
            print("Batch not found")
        }
    }
    
    func fetchCompletedUnsyncedTransactions() -> [PillCountTransactionEntity] {

        let request: NSFetchRequest<PillCountTransactionEntity> =
            PillCountTransactionEntity.fetchRequest()

        request.predicate = NSPredicate(
            format: "is_deleted == false AND is_synced == false AND status == %@ AND count_type == %@",
            CountStatus.COMPLETED.rawValue,
            CountType.FIXED.rawValue
        )

        request.sortDescriptors = [
            NSSortDescriptor(key: "created_at", ascending: true)
        ]

        return (try? mainThreadContext.fetch(request)) ?? []
    }
}
