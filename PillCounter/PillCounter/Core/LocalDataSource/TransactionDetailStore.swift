//
//  TransactionDetailDAO.swift
//  PillCounter
//

import CoreData

final class TransactionDetailStore {

    static let shared = TransactionDetailStore()
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
            softDeleteForStepLocked(txnId: txnId, step: .vial)
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
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_details_id == %lld", detailId)
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    func fetchAll(txnId: Int64) -> [PillCountTransactionDetailsEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    /// Same as `fetchAll(txnId:)`, but reads via an explicit context — see
    /// `TransactionStore.fetchById(_:in:)`.
    func fetchAll(txnId: Int64, in context: NSManagedObjectContext) -> [PillCountTransactionDetailsEntity] {
        context.performAndWait {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "txn_id == %lld AND type == %@ AND is_deleted == false",
                txnId, step.rawValue
            )
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    /// Reverse lookup used by the image web server to resolve a delivered
    /// detail-image filename back to the owning transaction. `image_path` is
    /// field-level encrypted at rest, so it cannot be matched via an
    /// NSPredicate against the SQLite row (that would compare against
    /// ciphertext) — fetch and compare the decrypted in-memory value instead.
    func txnId(forImagePath filename: String) -> Int64? {
        sync {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "is_deleted == false")
            guard let results = try? context.fetch(request) else { return nil }
            results.forEach { refreshDecrypted($0) }
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
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "txn_id IN %@ AND type == %@ AND is_deleted == false",
                txnIds, step.rawValue
            )
            let results = (try? context.fetch(request)) ?? []
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
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "txn_id IN %@ AND type == %@ AND is_deleted == false",
                txnIds, step.rawValue
            )
            let results = (try? context.fetch(request)) ?? []
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
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "txn_details_id IN %@ AND is_deleted == false",
                detailIds
            )
            let results = (try? context.fetch(request)) ?? []
            return results.reduce(0) { $0 + Int($1.pill_count) }
        }
    }

    /// Same as `sumPillCount(detailIds:)`, but reads via an explicit context
    /// — see `TransactionStore.fetchById(_:in:)`.
    func sumPillCount(detailIds: [Int64], in context: NSManagedObjectContext) -> Int {
        guard !detailIds.isEmpty else { return 0 }
        return context.performAndWait {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "txn_details_id IN %@ AND is_deleted == false",
                detailIds
            )
            let results = (try? context.fetch(request)) ?? []
            return results.reduce(0) { $0 + Int($1.pill_count) }
        }
    }

    func lastCompletedStep(txnId: Int64) -> ControlledStep? {
        sync {
            let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = 1
            guard let detail = try? context.fetch(request).first,
                  let type = detail.type else { return nil }
            return ControlledStep(rawValue: type)
        }
    }

    // MARK: - Update

    func update(detailId: Int64, block: (PillCountTransactionDetailsEntity) -> Void) {
        sync {
            guard let detail = fetchByIdLocked(detailId) else { return }
            block(detail)
            detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("🔍 [TransactionDetailDAO] UPDATED — detailId: \(detailId), txnId: \(detail.txn_id)")
        }
    }

    // MARK: - Delete

    func softDelete(detailId: Int64) {
        sync {
            guard let detail = fetchByIdLocked(detailId) else { return }
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
            softDeleteForStepLocked(txnId: txnId, step: step)
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

    // MARK: - Private

    /// Deterministically decrypts the object's encrypted fields in place
    /// (e.g. image_path). Replaces the old context.refresh(_, mergeChanges: false)
    /// refault, which did NOT reliably re-run awakeFromFetch and could surface
    /// ciphertext written by willSave in the same session.
    private func refreshDecrypted(_ object: NSManagedObject) {
        object.decryptEncryptedFieldsInPlace()
    }

    /// Same lookup as `fetchById`, but assumes the caller is already inside
    /// a `sync { }` block on this context.
    private func fetchByIdLocked(_ detailId: Int64) -> PillCountTransactionDetailsEntity? {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_details_id == %lld", detailId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        refreshDecrypted(result)
        return result
    }

    /// Same as `softDeleteForStep`, but assumes the caller is already inside
    /// a `sync { }` block on this context.
    private func softDeleteForStepLocked(txnId: Int64, step: ControlledStep) {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "txn_id == %lld AND type == %@ AND is_deleted == false",
            txnId, step.rawValue
        )
        guard let details = try? context.fetch(request), !details.isEmpty else { return }
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
