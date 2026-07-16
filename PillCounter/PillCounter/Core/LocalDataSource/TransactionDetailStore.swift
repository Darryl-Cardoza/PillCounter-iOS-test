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

    // MARK: - Create

    func add(
        txnId: Int64,
        pillCount: Int32,
        imagePath: String? = nil,
        type: String? = nil,
        isManual: Bool = false
    ) {
        guard let parent = TransactionStore.shared.fetchById(txnId) else { return }

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
        print("🔍 [TransactionDetailDAO] CREATED — detailId: \(detail.txn_details_id), txnId: \(txnId), pillCount: \(pillCount), type: \(type ?? "-"), isManual: \(isManual)")
    }

    func addOrReplaceVial(txnId: Int64, imagePath: String?) {
        context.performAndWait {
            softDeleteForStep(txnId: txnId, step: .vial)
            context.refreshAllObjects()
            add(
                txnId: txnId,
                pillCount: 0,
                imagePath: imagePath,
                type: ControlledStep.vial.rawValue
            )
        }
    }

    // MARK: - Read

    func fetchById(_ detailId: Int64) -> PillCountTransactionDetailsEntity? {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_details_id == %lld", detailId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        refreshDecrypted(result)
        return result
    }

    func fetchAll(txnId: Int64) -> [PillCountTransactionDetailsEntity] {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
    }

    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity] {
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

    /// Reverse lookup used by the image web server to resolve a delivered
    /// detail-image filename back to the owning transaction. `image_path` is
    /// field-level encrypted at rest, so it cannot be matched via an
    /// NSPredicate against the SQLite row (that would compare against
    /// ciphertext) — fetch and compare the decrypted in-memory value instead.
    func txnId(forImagePath filename: String) -> Int64? {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "is_deleted == false")
        guard let results = try? context.fetch(request) else { return nil }
        results.forEach { refreshDecrypted($0) }
        return results.first { $0.image_path == filename }?.txn_id
    }

    func totalCount(txnId: Int64) -> Int {
        fetchAll(txnId: txnId).reduce(0) { $0 + Int($1.pill_count) }
    }

    func totalCountForStep(txnId: Int64, step: ControlledStep) -> Int32 {
        fetchForStep(txnId: txnId, step: step).reduce(Int32(0)) { $0 + $1.pill_count }
    }

    func lastCompletedStep(txnId: Int64) -> ControlledStep? {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        request.fetchLimit = 1
        guard let detail = try? context.fetch(request).first,
              let type = detail.type else { return nil }
        return ControlledStep(rawValue: type)
    }

    // MARK: - Update

    func update(detailId: Int64, block: (PillCountTransactionDetailsEntity) -> Void) {
        guard let detail = fetchById(detailId) else { return }
        block(detail)
        detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("🔍 [TransactionDetailDAO] UPDATED — detailId: \(detailId), txnId: \(detail.txn_id)")
    }

    // MARK: - Delete

    func softDelete(detailId: Int64) {
        guard let detail = fetchById(detailId) else { return }
        detail.is_deleted = true
        detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("🔍 [TransactionDetailDAO] SOFT DELETED — detailId: \(detailId), txnId: \(detail.txn_id)")
    }

    func softDeleteAll(txnId: Int64) {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
        guard let details = try? context.fetch(request), !details.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        details.forEach { $0.is_deleted = true; $0.updated_at = now }
        CoreDataManager.shared.save(context: context)
        print("🔍 [TransactionDetailDAO] SOFT DELETED ALL — txnId: \(txnId), count: \(details.count)")
    }

    func softDeleteForStep(txnId: Int64, step: ControlledStep) {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "txn_id == %lld AND type == %@ AND is_deleted == false",
            txnId, step.rawValue
        )
        guard let details = try? context.fetch(request), !details.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        details.forEach { $0.is_deleted = true; $0.updated_at = now }
        CoreDataManager.shared.save(context: context)
        print("🔍 [TransactionDetailDAO] SOFT DELETED step — txnId: \(txnId), step: \(step.rawValue), count: \(details.count)")
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionDetailsEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("🔍 [TransactionDetailDAO] DELETED ALL — all transaction details removed")
        } catch {
            print("Failed do delete all")
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

    private func generateUniqueId() -> Int64 {
        let key = "txnDetailIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
