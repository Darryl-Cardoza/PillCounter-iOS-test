//
//  BatchDAO.swift
//  PillCounter
//

import CoreData
import Combine

final class BatchStore {

    static let shared = BatchStore()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    /// Confines every Core Data touch to `context`'s owning queue — see
    /// `TransactionStore.sync` for why this exists (HL7 sync queues call
    /// into this store from their own background DispatchQueue).
    private func sync<T>(_ block: () -> T) -> T {
        context.performAndWait(block)
    }

    // Fired after every write that affects batches. Subscribers reload derived state automatically.
    let transactionsDidChange = PassthroughSubject<Void, Never>()

    private var currentUserId: String {
        AppStorageManager.shared.userId ?? ""
    }

    // MARK: - Create

    @discardableResult
    func create(bucketId: String, requestId: String? = nil) -> BatchCountEntity? {
        let userId = currentUserId
        guard !userId.isEmpty else {
            StoreLogger.debug("📦 [BatchDAO] CREATE skipped — no logged-in user")
            return nil
        }
        let batch: BatchCountEntity = sync {
            let batchId = Int64(Date().timeIntervalSince1970 * 1000)
            let batch = BatchCountEntity(context: context)
            batch.batch_id = batchId
            batch.start_date_time = batchId
            batch.status = CountStatus.PARTIAL.rawValue
            batch.is_deleted = false
            batch.bucket_id = bucketId
            batch.req_id_from_pms = requestId
            batch.is_synced = false
            batch.user_id = userId
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📦 [BatchDAO] CREATED — batchId: \(batchId), bucketId: \(bucketId), userId: \(userId), requestId: \(requestId ?? "-")")
            return batch
        }
        transactionsDidChange.send()
        return batch
    }

    // MARK: - Read

    func fetchById(_ batchId: Int64) -> BatchCountEntity? {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
    }

    /// Same as `fetchById(_:)`, but fetches via an explicit context — see
    /// `TransactionStore.fetchById(_:in:)`.
    func fetchById(_ batchId: Int64, in context: NSManagedObjectContext) -> BatchCountEntity? {
        context.performAndWait {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
    }

    func fetchAll() -> [BatchCountEntity] {
        sync {
            let userId = currentUserId
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(format: "user_id == %@", userId)
            let results = (try? context.fetch(request)) ?? []
            #if DEBUG
            StoreLogger.log(
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
            #endif
            return results
        }
    }

    func fetchAllPartial() -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@",
                currentUserId, CountStatus.PARTIAL.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Same as `fetchAllPartial()`, but fetches via an explicit context —
    /// see `TransactionStore.fetchPartial(for:isDispense:in:)`.
    func fetchAllPartial(in context: NSManagedObjectContext) -> [BatchCountEntity] {
        context.performAndWait {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@",
                currentUserId, CountStatus.PARTIAL.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Paginated variant of `fetchAllPartial` — bounded to `limit` rows
    /// starting at `offset`.
    func fetchAllPartialPage(limit: Int, offset: Int) -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@",
                currentUserId, CountStatus.PARTIAL.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            return (try? context.fetch(request)) ?? []
        }
    }

    func fetchAllCompleted() -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@",
                currentUserId, CountStatus.COMPLETED.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Paginated variant of `fetchAllCompleted` — bounded to `limit` rows
    /// starting at `offset`.
    func fetchAllCompletedPage(limit: Int, offset: Int) -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@",
                currentUserId, CountStatus.COMPLETED.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            return (try? context.fetch(request)) ?? []
        }
    }

    func fetchLastCreated() -> BatchCountEntity? {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@",
                currentUserId, CountStatus.PARTIAL.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
    }

    func fetchByDateRange(startTs: Int64, endTs: Int64) -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld",
                currentUserId, startTs, endTs
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Same as `fetchByDateRange(startTs:endTs:)`, but fetches via an
    /// explicit context — see `TransactionStore.fetchPartial(for:isDispense:in:)`.
    func fetchByDateRange(startTs: Int64, endTs: Int64, in context: NSManagedObjectContext) -> [BatchCountEntity] {
        context.performAndWait {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld",
                currentUserId, startTs, endTs
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Paginated variant of `fetchByDateRange` — bounded to `limit` rows
    /// starting at `offset`, so browsing a large date range doesn't pull
    /// every batch in that range into memory at once.
    func fetchByDateRangePage(startTs: Int64, endTs: Int64, limit: Int, offset: Int) -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld",
                currentUserId, startTs, endTs
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: false)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            return (try? context.fetch(request)) ?? []
        }
    }

    func fetchCompletedUnsynced() -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@ AND is_synced == false",
                currentUserId, CountStatus.COMPLETED.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: true)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Paginated variant of `fetchCompletedUnsynced` — bounded to `limit`
    /// rows starting at `offset`.
    func fetchCompletedUnsyncedPage(limit: Int, offset: Int) -> [BatchCountEntity] {
        sync {
            let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@ AND is_synced == false",
                currentUserId, CountStatus.COMPLETED.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "start_date_time", ascending: true)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            return (try? context.fetch(request)) ?? []
        }
    }

    /// True count of batches in `[startTs, endTs]` for the current user,
    /// optionally narrowed to a status — independent of any page size, so a
    /// paginated display list can show an accurate status-filter count
    /// without fetching every row in the range.
    func countByDateRange(startTs: Int64, endTs: Int64, status: CountStatus?) -> Int {
        sync {
            let request = NSFetchRequest<NSNumber>(entityName: "BatchCountEntity")
            request.resultType = .countResultType
            if let status {
                request.predicate = NSPredicate(
                    format: "user_id == %@ AND is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld AND status == %@",
                    currentUserId, startTs, endTs, status.rawValue
                )
            } else {
                request.predicate = NSPredicate(
                    format: "user_id == %@ AND is_deleted == false AND start_date_time >= %lld AND start_date_time <= %lld",
                    currentUserId, startTs, endTs
                )
            }
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// True count of pending (PARTIAL, not deleted) batches for the current
    /// user, matching the same base predicate as `fetchAllPartial`/the
    /// dashboard's `allPendingInventory`, optionally narrowed to whether the
    /// batch originated from a PMS cycle-count request — independent of row
    /// count, so the dashboard's stat cards don't need to fetch every
    /// pending batch just to report how many match each facet.
    enum PendingBatchFacet {
        case all
        /// Has a non-empty `req_id_from_pms` — a PMS-initiated cycle count.
        case cycleCount
        /// Empty `req_id_from_pms` — a manually started pending batch.
        case pendingBatch
    }

    func countPendingInventory(facet: PendingBatchFacet) -> Int {
        sync {
            let request = NSFetchRequest<NSNumber>(entityName: "BatchCountEntity")
            request.resultType = .countResultType
            var format = "user_id == %@ AND is_deleted == false AND status == %@"
            var args: [Any] = [currentUserId, CountStatus.PARTIAL.rawValue]
            switch facet {
            case .all:
                break
            case .cycleCount:
                format += " AND req_id_from_pms != nil AND req_id_from_pms != %@"
                args.append("")
            case .pendingBatch:
                format += " AND (req_id_from_pms == nil OR req_id_from_pms == %@)"
                args.append("")
            }
            request.predicate = NSPredicate(format: format, argumentArray: args)
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// True total matching `fetchCompletedUnsynced`, independent of any page
    /// size — so a capped/paginated display list can still show an accurate
    /// "N unsynced" count without fetching every matching row.
    func countCompletedUnsynced() -> Int {
        sync {
            let request = NSFetchRequest<NSNumber>(entityName: "BatchCountEntity")
            request.resultType = .countResultType
            request.predicate = NSPredicate(
                format: "user_id == %@ AND is_deleted == false AND status == %@ AND is_synced == false",
                currentUserId, CountStatus.COMPLETED.rawValue
            )
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// StockTxnEntity already has exactly one row per NDC per batch, so a plain count works
    /// (no distinct-query needed, unlike the legacy PillCountTransactionEntity model).
    func getTransactionCount(for batchId: Int64) -> Int {
        sync {
            let request = NSFetchRequest<NSNumber>(entityName: "StockTxnEntity")
            request.resultType = .countResultType
            request.predicate = NSPredicate(
                format: "batch_id == %lld AND is_deleted == false AND drug.ndc != nil",
                batchId
            )
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// Batched variant of `getTransactionCount(for:)` — one query for every
    /// id in `batchIds` instead of one query per batch, so a screen listing
    /// N batches doesn't issue N synchronous Core Data round trips just to
    /// show each batch's item count.
    func transactionCounts(for batchIds: [Int64]) -> [Int64: Int] {
        guard !batchIds.isEmpty else { return [:] }
        return sync {
            let request = NSFetchRequest<NSDictionary>(entityName: "StockTxnEntity")
            request.predicate = NSPredicate(
                format: "batch_id IN %@ AND is_deleted == false AND drug.ndc != nil",
                batchIds
            )
            request.propertiesToFetch = ["batch_id"]
            request.resultType = .dictionaryResultType
            let rows = (try? context.fetch(request)) ?? []
            var counts: [Int64: Int] = Dictionary(uniqueKeysWithValues: batchIds.map { ($0, 0) })
            for row in rows {
                guard let batchIdNumber = row["batch_id"] as? NSNumber else { continue }
                counts[batchIdNumber.int64Value, default: 0] += 1
            }
            return counts
        }
    }

    /// Same as `transactionCounts(for:)`, but queries via an explicit
    /// context — see `TransactionStore.fetchPartial(for:isDispense:in:)`.
    func transactionCounts(for batchIds: [Int64], in context: NSManagedObjectContext) -> [Int64: Int] {
        guard !batchIds.isEmpty else { return [:] }
        return context.performAndWait {
            let request = NSFetchRequest<NSDictionary>(entityName: "StockTxnEntity")
            request.predicate = NSPredicate(
                format: "batch_id IN %@ AND is_deleted == false AND drug.ndc != nil",
                batchIds
            )
            request.propertiesToFetch = ["batch_id"]
            request.resultType = .dictionaryResultType
            let rows = (try? context.fetch(request)) ?? []
            var counts: [Int64: Int] = Dictionary(uniqueKeysWithValues: batchIds.map { ($0, 0) })
            for row in rows {
                guard let batchIdNumber = row["batch_id"] as? NSNumber else { continue }
                counts[batchIdNumber.int64Value, default: 0] += 1
            }
            return counts
        }
    }

    // MARK: - Update

    func updateStatus(batchId: Int64, status: CountStatus, completion: (() -> Void)? = nil) {
        let saved: Bool = sync {
            guard let batch = fetchByIdLocked(batchId) else { return false }
            batch.status = status.rawValue
            batch.is_synced = false
            if status == .COMPLETED {
                batch.end_date_time = Int64(Date().timeIntervalSince1970 * 1000)
            }
            do {
                try context.save()
                StoreLogger.debug("📦 [BatchDAO] UPDATED status — batchId: \(batchId), status: \(status.rawValue)")
                return true
            } catch {
                StoreLogger.debug("❌ BatchDAO.updateStatus save failed: \(error)")
                return false
            }
        }
        guard saved else { return }
        transactionsDidChange.send()
        completion?()
    }

    func updateNote(batchId: Int64, note: String) {
        sync {
            guard let batch = fetchByIdLocked(batchId) else { return }
            batch.note = note
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📦 [BatchDAO] UPDATED note — batchId: \(batchId)")
        }
    }

    // MARK: - Delete

    func markSynced(batchId: Int64) {
        sync {
            guard let batch = fetchByIdLocked(batchId) else { return }
            batch.is_synced = true
            try? context.save()
            StoreLogger.debug("📦 [BatchDAO] SYNCED — batchId: \(batchId)")
        }
        transactionsDidChange.send()
    }

    func softDelete(ids: Set<Int64>) {
        let succeeded: Bool = sync {
            let batchReq: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
            batchReq.predicate = NSPredicate(format: "batch_id IN %@", ids)

            let txnReq: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            txnReq.predicate = NSPredicate(format: "batch_id IN %@", ids)

            let stockTxnReq: NSFetchRequest<StockTxnEntity> = StockTxnEntity.fetchRequest()
            stockTxnReq.predicate = NSPredicate(format: "batch_id IN %@", ids)

            do {
                let batches = try context.fetch(batchReq)
                batches.forEach { $0.is_deleted = true }
                let transactions = try context.fetch(txnReq)
                transactions.forEach { $0.is_deleted = true }
                let stockTxns = try context.fetch(stockTxnReq)
                stockTxns.forEach { $0.is_deleted = true }
                try context.save()
                StoreLogger.debug("📦 [BatchDAO] SOFT DELETED — batchIds: \(ids), batches: \(batches.count), transactions: \(transactions.count), stockTxns: \(stockTxns.count)")
                return true
            } catch {
                StoreLogger.debug("❌ BatchDAO.softDelete failed: \(error)")
                return false
            }
        }
        guard succeeded else { return }
        transactionsDidChange.send()
    }

    func deleteAll() {
        sync {
            let request: NSFetchRequest<NSFetchRequestResult> = BatchCountEntity.fetchRequest()
            do {
                try context.execute(NSBatchDeleteRequest(fetchRequest: request))
                StoreLogger.debug("📦 [BatchDAO] DELETED ALL — all batch records removed")
            } catch {
                StoreLogger.debug("Failed to delete BatchCountEntity: \(error)")
            }
        }
    }

    // MARK: - Private

    /// Same lookup as `fetchById`, but assumes the caller is already inside
    /// a `sync { }` block on this context.
    private func fetchByIdLocked(_ batchId: Int64) -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Same as `fetchByIdLocked(_:)`, but against an explicit context — see
    /// `TransactionStore.fetchByIdLocked(_:in:)`.
    private func fetchByIdLocked(_ batchId: Int64, in context: NSManagedObjectContext) -> BatchCountEntity? {
        let request: NSFetchRequest<BatchCountEntity> = BatchCountEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Same as `markSynced(batchId:)`, but writes via an explicit context —
    /// for the HL7 batch sync queue's ACK-success write, which previously
    /// hopped to `viewContext`/the main thread per synced batch. See
    /// `TransactionStore.updateSynced(txnId:in:)` for the equivalent
    /// transaction-side fix and its rationale.
    func markSynced(batchId: Int64, in context: NSManagedObjectContext) {
        context.performAndWait {
            guard let batch = fetchByIdLocked(batchId, in: context) else { return }
            batch.is_synced = true
            try? context.save()
            StoreLogger.debug("📦 [BatchDAO] SYNCED — batchId: \(batchId)")
        }
        transactionsDidChange.send()
    }
}
