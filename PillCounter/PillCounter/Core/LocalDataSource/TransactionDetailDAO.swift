//
//  TransactionDetailDAO.swift
//  PillCounter
//

import CoreData

final class TransactionDetailDAO {

    static let shared = TransactionDetailDAO()
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
        guard let parent = TransactionDAO.shared.fetchById(txnId) else { return }

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
        return try? context.fetch(request).first
    }

    func fetchAll(txnId: Int64) -> [PillCountTransactionDetailsEntity] {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity] {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "txn_id == %lld AND type == %@ AND is_deleted == false",
            txnId, step.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        return (try? context.fetch(request)) ?? []
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
    }

    // MARK: - Delete

    func softDelete(detailId: Int64) {
        guard let detail = fetchById(detailId) else { return }
        detail.is_deleted = true
        detail.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func softDeleteAll(txnId: Int64) {
        let request: NSFetchRequest<PillCountTransactionDetailsEntity> = PillCountTransactionDetailsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld AND is_deleted == false", txnId)
        guard let details = try? context.fetch(request), !details.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        details.forEach { $0.is_deleted = true; $0.updated_at = now }
        CoreDataManager.shared.save(context: context)
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
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionDetailsEntity.fetchRequest()
        do{
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        }catch{
            print("Failed do delete all")
        }
    }

    // MARK: - Private

    private func generateUniqueId() -> Int64 {
        let key = "txnDetailIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}

