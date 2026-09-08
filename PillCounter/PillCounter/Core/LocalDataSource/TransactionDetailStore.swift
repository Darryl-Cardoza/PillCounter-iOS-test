//
//  TransactionDetailDAO.swift
//  PillCounter
//

import CoreData

final class TransactionDetailStore: BaseDataStore<PillCountTransactionDetailsEntity> {

    static let shared = TransactionDetailStore()
    private override init() {}

    override func postFetch(_ entity: PillCountTransactionDetailsEntity) {
        entity.decryptEncryptedFieldsInPlace()
    }

    // MARK: - Create

    @discardableResult
    func add(
        txnId: Int64,
        pillCount: Int32,
        imagePath: String? = nil,
        type: String? = nil,
        isManual: Bool = false
    ) -> PillCountTransactionDetailsEntity? {
        guard let parent = TransactionStore.shared.fetchById(txnId) else { return nil }

        return sync {
            let detail = PillCountTransactionDetailsEntity(context: context)
            detail.txn_details_id = generateUniqueId()
            detail.txn_id = txnId
            detail.pill_count = pillCount
            detail.image_path = imagePath
            detail.type = type
            detail.is_manual = isManual
            detail.is_deleted = false

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            detail.created_at = now
            detail.updated_at = now

            detail.pillCountTransaction = parent
            parent.addToPillCountTransactionDetails(detail)

            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🔍 [TransactionDetailDAO] CREATED — detailId: \(detail.txn_details_id), txnId: \(txnId), pillCount: \(pillCount), type: \(type ?? "-"), isManual: \(isManual)")
            return detail
        }
    }

    func addOrReplaceVial(txnId: Int64, imagePath: String?) {
        sync {
            softDeleteForStepNoWrap(txnId: txnId, step: .vial)
            context.refreshAllObjects()
        }
        add(
            txnId: txnId,
            pillCount: 0,
            imagePath: imagePath,
            type: ControlledStep.vial.rawValue
        )
    }

    // MARK: - Read

    func fetchById(_ detailId: Int64) -> PillCountTransactionDetailsEntity? {
        sync {
            fetchOne(predicate: NSPredicate(format: "txn_details_id == %lld", detailId), sort: nil, in: context)
        }
    }

    func fetchAll(txnId: Int64) -> [PillCountTransactionDetailsEntity] {
        sync {
            fetchAllMatching(
                predicate: NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId),
                sort: [NSSortDescriptor(key: "created_at", ascending: true)],
                in: context
            )
        }
    }

    /// Same as `fetchAll(txnId:)`, but reads via an explicit context — see
    /// `TransactionStore.fetchById(_:in:)`.
    func fetchAll(txnId: Int64, in context: NSManagedObjectContext) -> [PillCountTransactionDetailsEntity] {
        context.performAndWait {
            fetchAllMatching(
                predicate: NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId),
                sort: [NSSortDescriptor(key: "created_at", ascending: true)],
                in: context
            )
        }
    }

    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity] {
        sync {
            fetchAllMatching(
                predicate: NSPredicate(
                    format: "txn_id == %lld AND type == %@ AND is_deleted == false",
                    txnId, step.rawValue
                ),
                sort: [NSSortDescriptor(key: "created_at", ascending: true)],
                in: context
            )
        }
    }

    /// Reverse lookup used by the image web server to resolve a delivered
    /// detail-image filename back to the owning transaction. `image_path` is
    /// field-level encrypted at rest, so it cannot be matched via an
    /// NSPredicate against the SQLite row (that would compare against
    /// ciphertext) — fetch and compare the decrypted in-memory value instead.
    func txnId(forImagePath filename: String) -> Int64? {
        sync {
            let results = fetchAllMatching(predicate: NSPredicate(format: "is_deleted == false"), sort: nil, in: context)
            return results.first { $0.image_path == filename }?.txn_id
        }
    }

    func totalCount(txnId: Int64) -> Int {
        fetchAll(txnId: txnId).reduce(0) { $0 + Int($1.pill_count) }
    }

    func totalCountForStep(txnId: Int64, step: ControlledStep) -> Int32 {
        fetchForStep(txnId: txnId, step: step).reduce(Int32(0)) { $0 + $1.pill_count }
    }

    /// Batched variant of `totalCountForStep` — one query covering every id
    /// in `txnIds` instead of one query per transaction, so a screen listing
    /// N transactions doesn't issue N synchronous Core Data round trips just
    /// to show each one's pill count for `step`.
    func totalCountsForSteps(txnIds: [Int64], step: ControlledStep) -> [Int64: Int32] {
        guard !txnIds.isEmpty else { return [:] }
        return sync {
            let results = fetchAllMatching(
                predicate: NSPredicate(
                    format: "txn_id IN %@ AND type == %@ AND is_deleted == false",
                    txnIds, step.rawValue
                ),
                sort: nil,
                in: context
            )
            var totals: [Int64: Int32] = Dictionary(uniqueKeysWithValues: txnIds.map { ($0, 0) })
            for detail in results {
                totals[detail.txn_id, default: 0] += detail.pill_count
            }
            return totals
        }
    }

    /// Same as `totalCountsForSteps(txnIds:step:)`, but queries via an
    /// explicit context — see `TransactionStore.fetchPartial(for:isDispense:in:)`.
    func totalCountsForSteps(txnIds: [Int64], step: ControlledStep, in context: NSManagedObjectContext) -> [Int64: Int32] {
        guard !txnIds.isEmpty else { return [:] }
        return context.performAndWait {
            let results = fetchAllMatching(
                predicate: NSPredicate(
                    format: "txn_id IN %@ AND type == %@ AND is_deleted == false",
                    txnIds, step.rawValue
                ),
                sort: nil,
                in: context
            )
            var totals: [Int64: Int32] = Dictionary(uniqueKeysWithValues: txnIds.map { ($0, 0) })
            for detail in results {
                totals[detail.txn_id, default: 0] += detail.pill_count
            }
            return totals
        }
    }

    /// Sums pill_count for a set of detail-row ids, excluding soft-deleted rows.
    /// Used to compute a bottle's live pill count from `BottleInfo.txnDetailsIds` —
    /// never cached, so a later delete/redo of a detail row is automatically reflected.
    func sumPillCount(detailIds: [Int64]) -> Int {
        guard !detailIds.isEmpty else { return 0 }
        return sync {
            let results = fetchAllMatching(
                predicate: NSPredicate(format: "txn_details_id IN %@ AND is_deleted == false", detailIds),
                sort: nil,
                in: context
            )
            return results.reduce(0) { $0 + Int($1.pill_count) }
        }
    }

    /// Same as `sumPillCount(detailIds:)`, but reads via an explicit context
    /// — see `TransactionStore.fetchById(_:in:)`.
    func sumPillCount(detailIds: [Int64], in context: NSManagedObjectContext) -> Int {
        guard !detailIds.isEmpty else { return 0 }
        return context.performAndWait {
            let results = fetchAllMatching(
                predicate: NSPredicate(format: "txn_details_id IN %@ AND is_deleted == false", detailIds),
                sort: nil,
                in: context
            )
            return results.reduce(0) { $0 + Int($1.pill_count) }
        }
    }

    func lastCompletedStep(txnId: Int64) -> ControlledStep? {
        sync {
            guard let detail = fetchOne(
                predicate: NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId),
                sort: [NSSortDescriptor(key: "created_at", ascending: false)],
                in: context
            ), let type = detail.type else { return nil }
            return ControlledStep(rawValue: type)
        }
    }

    // MARK: - Update

    func update(detailId: Int64, block: (PillCountTransactionDetailsEntity) -> Void) {
        sync {
            guard let detail = fetchByIdNoWrap(detailId) else { return }
            block(detail)
            detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🔍 [TransactionDetailDAO] UPDATED — detailId: \(detailId), txnId: \(detail.txn_id)")
        }
    }

    // MARK: - Delete

    func softDelete(detailId: Int64) {
        sync {
            guard let detail = fetchByIdNoWrap(detailId) else { return }
            detail.is_deleted = true
            detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🔍 [TransactionDetailDAO] SOFT DELETED — detailId: \(detailId), txnId: \(detail.txn_id)")
        }
    }

    func softDeleteAll(txnId: Int64) {
        sync {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
            guard let details = try? context.fetch(request), !details.isEmpty else { return }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            details.forEach { $0.is_deleted = true; $0.updated_at = now }
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🔍 [TransactionDetailDAO] SOFT DELETED ALL — txnId: \(txnId), count: \(details.count)")
        }
    }

    func softDeleteForStep(txnId: Int64, step: ControlledStep) {
        sync {
            softDeleteForStepNoWrap(txnId: txnId, step: step)
        }
    }

    func deleteAll() {
        sync {
            let request: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionDetailsEntity.fetchRequest()
            do {
                try context.execute(NSBatchDeleteRequest(fetchRequest: request))
                StoreLogger.debug("🔍 [TransactionDetailDAO] DELETED ALL — all transaction details removed")
            } catch {
                StoreLogger.debug("Failed to delete PillCountTransactionDetailsEntity: \(error)")
            }
        }
    }

    /// Hard-deletes every detail row for `txnId` (including soft-deleted ones)
    /// and returns the `image_path` filenames that were on them, so the caller
    /// can delete the backing image files — batch-deleting rows first would
    /// lose that information, since `NSBatchDeleteRequest` never materializes
    /// the objects. Used by transaction reset.
    ///
    /// `success` is `false` if the underlying save failed — the rows were
    /// NOT actually removed, so `imagePaths` is empty and the caller must
    /// not delete any files.
    @discardableResult
    func hardDeleteAll(txnId: Int64) -> (success: Bool, imagePaths: [String]) {
        sync {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
            guard let details = try? context.fetch(request), !details.isEmpty else { return (true, []) }
            let imagePaths = details.compactMap { $0.image_path }
            details.forEach { context.delete($0) }
            guard CoreDataManager.shared.saveReturningSuccess(context: context) else {
                StoreLogger.debug("🔍 [TransactionDetailDAO] HARD DELETE ALL FAILED — txnId: \(txnId), count: \(details.count)")
                return (false, [])
            }
            StoreLogger.debug("🔍 [TransactionDetailDAO] HARD DELETED ALL — txnId: \(txnId), count: \(details.count)")
            return (true, imagePaths)
        }
    }

    // MARK: - Private

    /// Same lookup as `fetchById`, but assumes the caller is already inside
    /// a `sync { }` block on this context — "NoWrap" because nothing here is
    /// locking anything: the sync{} wrapping already happened at the call
    /// site, so this variant skips wrapping again.
    private func fetchByIdNoWrap(_ detailId: Int64) -> PillCountTransactionDetailsEntity? {
        fetchOne(predicate: NSPredicate(format: "txn_details_id == %lld", detailId), sort: nil, in: context)
    }

    /// Same as `softDeleteForStep`, but assumes the caller is already inside
    /// a `sync { }` block on this context — same "NoWrap" convention as
    /// `fetchByIdNoWrap`.
    private func softDeleteForStepNoWrap(txnId: Int64, step: ControlledStep) {
        let details = fetchAllMatching(
            predicate: NSPredicate(format: "txn_id == %lld AND type == %@ AND is_deleted == false", txnId, step.rawValue),
            sort: nil,
            in: context
        )
        guard !details.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        details.forEach { $0.is_deleted = true; $0.updated_at = now }
        CoreDataManager.shared.save(context: context)
        StoreLogger.debug("🔍 [TransactionDetailDAO] SOFT DELETED step — txnId: \(txnId), step: \(step.rawValue), count: \(details.count)")
    }

    private func generateUniqueId() -> Int64 {
        let key = "txnDetailIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
