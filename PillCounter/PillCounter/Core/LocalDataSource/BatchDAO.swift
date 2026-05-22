//
//  BatchDAO.swift
//  PillCounter
//

import CoreData
import Combine

final class BatchDAO {

    static let shared = BatchDAO()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    // Fired after every write that affects batches. Subscribers reload derived state automatically.
    let transactionsDidChange = PassthroughSubject<Void, Never>()

    // MARK: - Create

    @discardableResult
    func create(bucketId: String, requestId: String? = nil) -> BatchCountEntity? {
        let batchId = Int64(Date().timeIntervalSince1970 * 1000)
        let batch = BatchCountEntity(context: context)
        batch.batch_id = batchId
        batch.start_date_time = batchId
        batch.status = CountStatus.PARTIAL.rawValue
        batch.is_deleted = false
        batch.bucket_id = bucketId
        batch.req_id_from_pms = requestId
        batch.is_synced = false
        CoreDataManager.shared.save(context: context)
        transactionsDidChange.send()
        print("📦 [BatchDAO] CREATED — batchId: \(batchId), bucketId: \(bucketId), requestId: \(requestId ?? "-")")
        return batch
    }

    // MARK: - Read

    func fetchById(_ batchId: Int64) -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchAll() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        let results = (try? context.fetch(request)) ?? []
        DAOLogger.log(
            dao: "BatchDAO", op: "fetchAll",
            columns: ["batch_id", "bucket_id", "status", "is_synced", "is_deleted", "start_date_time", "end_date_time"],
            rows: results.map { [
                "\($0.batch_id)",
                $0.bucket_id ?? "-",
                $0.status ?? "-",
                "\($0.is_synced)",
                "\($0.is_deleted)",
                "\($0.start_date_time)",
                "\($0.end_date_time)"
            ]}
        )
        return results
    }

    func fetchAllPartial() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@", CountStatus.PARTIAL.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchAllCompleted() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@", CountStatus.COMPLETED.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchLastCreated() -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@", CountStatus.PARTIAL.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchByDateRange(startTs: Int64, endTs: Int64) -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld",
            startTs, endTs
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchCompletedUnsynced() -> [BatchCountEntity] {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND status == %@ AND is_synced == false",
            CountStatus.COMPLETED.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func getTransactionCount(for batchId: Int64) -> Int {
        let request = NSFetchRequest<NSDictionary>(entityName: "PillCountTransactionEntity")
        request.predicate = NSPredicate(
            format: "batch_id == %lld AND is_deleted == false AND drug.ndc != nil", batchId
        )
        request.propertiesToFetch = ["drug.ndc"]
        request.returnsDistinctResults = true
        request.resultType = .dictionaryResultType
        return (try? context.fetch(request).count) ?? 0
    }

    // MARK: - Update

    func updateStatus(batchId: Int64, status: CountStatus, completion: (() -> Void)? = nil) {
        guard let batch = fetchById(batchId) else { return }
        batch.status = status.rawValue
        batch.is_synced = false
        if status == .COMPLETED {
            batch.end_date_time = Int64(Date().timeIntervalSince1970 * 1000)
        }
        do {
            try context.save()
            transactionsDidChange.send()
            print("📦 [BatchDAO] UPDATED status — batchId: \(batchId), status: \(status.rawValue)")
            completion?()
        } catch {
            print("❌ BatchDAO.updateStatus save failed:", error)
        }
    }

    func updateNote(batchId: Int64, note: String) {
        guard let batch = fetchById(batchId) else { return }
        batch.note = note
        CoreDataManager.shared.save(context: context)
        print("📦 [BatchDAO] UPDATED note — batchId: \(batchId)")
    }

    // MARK: - Delete

    func markSynced(batchId: Int64) {
        guard let batch = fetchById(batchId) else { return }
        batch.is_synced = true
        try? context.save()
        transactionsDidChange.send()
        print("📦 [BatchDAO] SYNCED — batchId: \(batchId)")
    }

    func softDelete(ids: Set<Int64>) {
        let batchReq: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        batchReq.predicate = NSPredicate(format: "batch_id IN %@", ids)

        let txnReq: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        txnReq.predicate = NSPredicate(format: "batch_id IN %@", ids)

        do {
            let batches = try context.fetch(batchReq)
            batches.forEach { $0.is_deleted = true }
            let transactions = try context.fetch(txnReq)
            transactions.forEach { $0.is_deleted = true }
            try context.save()
            transactionsDidChange.send()
            print("📦 [BatchDAO] SOFT DELETED — batchIds: \(ids), batches: \(batches.count), transactions: \(transactions.count)")
        } catch {
            print("❌ BatchDAO.softDelete failed:", error)
        }
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = BatchCountEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("📦 [BatchDAO] DELETED ALL — all batch records removed")
        } catch {
            print("Failed to delete BatchCountEntity: \(error)")
        }
    }
}
