//
//  StockTxnStore.swift
//  PillCounter
//

import CoreData
import Combine

final class StockTxnStore {

    static let shared = StockTxnStore()
    private init() {}

    let stockTxnsDidChange = PassthroughSubject<Void, Never>()

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    private let isoFormatter = ISO8601DateFormatter()

    // MARK: - Create / fetch-or-create

    /// One StockTxnEntity per (batch, drugId). Returns the existing row if already
    /// present for this batch+NDC, otherwise creates it.
    @discardableResult
    func fetchOrCreate(batch: BatchCountEntity, drugId: Int64, bucketId: String?) -> StockTxnEntity {
        let request: NSFetchRequest<StockTxnEntity> = StockTxnEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "batch == %@ AND drug_id == %lld AND is_deleted == false",
            batch, drugId
        )
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }

        let entity = StockTxnEntity(context: context)
        entity.stock_txn_id = generateUniqueId()
        entity.batch_id = batch.batch_id
        entity.bucket_id = bucketId
        entity.drug_id = drugId
        entity.status = CountStatus.PARTIAL.rawValue
        entity.is_deleted = false
        entity.batch = batch

        let now = isoFormatter.string(from: Date())
        entity.created_at = now
        entity.updated_at = now

        if let drug = DrugCatalogStore.shared.fetchById(drugId) {
            entity.drug = drug
        }

        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("📦 [StockTxnDAO] CREATED — stockTxnId: \(entity.stock_txn_id), batchId: \(batch.batch_id), drugId: \(drugId)")
        stockTxnsDidChange.send()
        return entity
    }

    // MARK: - Read

    func fetchById(_ stockTxnId: Int64) -> StockTxnEntity? {
        let request: NSFetchRequest<StockTxnEntity> = StockTxnEntity.fetchRequest()
        request.predicate = NSPredicate(format: "stock_txn_id == %lld", stockTxnId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchByBatch(batchId: Int64) -> [StockTxnEntity] {
        let request: NSFetchRequest<StockTxnEntity> = StockTxnEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
        return (try? context.fetch(request)) ?? []
    }

    /// Same as `fetchByBatch(batchId:)`, but fetches via an explicit context
    /// — see `TransactionStore.fetchById(_:in:)`. This store has no `sync`
    /// helper of its own (every other method here assumes the caller is
    /// already on `viewContext`'s queue); `performAndWait` is added here
    /// explicitly since this overload is for callers on a different queue.
    func fetchByBatch(batchId: Int64, in context: NSManagedObjectContext) -> [StockTxnEntity] {
        context.performAndWait {
            let request: NSFetchRequest<StockTxnEntity> = StockTxnEntity.fetchRequest()
            request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
            return (try? context.fetch(request)) ?? []
        }
    }

    /// HIPAA-normalized (11-digit 5-4-2) match — a freshly-scanned barcode NDC
    /// and the NDC a StockTxn's drug was originally created/stored under (e.g.
    /// via a PMS inventory request, API-normalized) can differ in hyphenation,
    /// FDA segment layout, or digit count for the same physical drug. Exact-
    /// string match missed these, causing a second StockTxnEntity (and a
    /// second HL7 INV group) to be created for a drug already tracked in this
    /// batch.
    func fetchByBatchAndNdc(batchId: Int64, ndc: String) -> StockTxnEntity? {
        let target = ndc.ndcNormalized
        guard !target.isEmpty else { return nil }
        return fetchByBatch(batchId: batchId).first {
            ($0.drug?.ndc ?? "").ndcNormalized == target
        }
    }

    // MARK: - Update

    func updateStatus(stockTxnId: Int64, status: CountStatus) {
        guard let stockTxn = fetchById(stockTxnId) else { return }
        stockTxn.status = status.rawValue
        stockTxn.updated_at = isoFormatter.string(from: Date())
        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("📦 [StockTxnDAO] UPDATED status — stockTxnId: \(stockTxnId), status: \(status.rawValue)")
        stockTxnsDidChange.send()
    }

    // MARK: - Delete

    /// BottleInfoStore shares this same viewContext, so staging the flag flip here first
    /// and letting softDeleteByStockTxn's save carry both changes keeps this one atomic
    /// transaction (matching the original single-`save()` behavior) instead of splitting
    /// into two saves with a partial-failure window between them.
    @discardableResult
    func softDelete(stockTxnId: Int64) -> Bool {
        guard let stockTxn = fetchById(stockTxnId) else { return false }
        stockTxn.is_deleted = true
        stockTxn.updated_at = isoFormatter.string(from: Date())
        // softDeleteByStockTxn already reverts its own bottle-row deletes on failure —
        // only this object's two fields are left dirty here, so refresh just this one.
        guard BottleInfoStore.shared.softDeleteByStockTxn(stockTxnId: stockTxnId) else {
            context.refresh(stockTxn, mergeChanges: false)
            return false
        }
        guard CoreDataManager.shared.saveReturningSuccess(context: context) else {
            // Bottle rows were already deleted+saved successfully by softDeleteByStockTxn
            // (that succeeded, or we wouldn't be here) — only this StockTxn's two fields
            // are still dirty and unsaved, so only they need reverting.
            context.refresh(stockTxn, mergeChanges: false)
            return false
        }
        StoreLogger.debug("📦 [StockTxnDAO] SOFT DELETED — stockTxnId: \(stockTxnId)")
        stockTxnsDidChange.send()
        return true
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = StockTxnEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            StoreLogger.debug("📦 [StockTxnDAO] DELETED ALL — all stock txns removed")
        } catch {
            StoreLogger.debug("Failed to delete StockTxnEntity: \(error)")
        }
    }

    // MARK: - Private

    private func generateUniqueId() -> Int64 {
        let key = "stockTxnIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
