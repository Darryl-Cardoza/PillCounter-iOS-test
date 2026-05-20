//
//  TransactionDAO.swift
//  PillCounter
//

import CoreData

final class TransactionDAO {

    static let shared = TransactionDAO()
    private init() {}

    private var context: NSManagedObjectContext {
        CoreDataManager.shared.context
    }

    // MARK: - Create

    func create(
        for user: UserEntity,
        drugId: Int64?,
        countType: CountType,
        batchId: Int64 = 0,
        barcodeImagePath: String = "",
        isFromPms: Bool = false,
        drugName: String? = nil,
        targetCount: Int32 = 0,
        isControlled: Bool? = nil,
        expirationDate: String? = nil,
        lotNumber: String? = nil,
        rxNo: String? = nil,
        bucketId: String? = nil
    ) -> PillCountTransactionEntity {
        let entity = PillCountTransactionEntity(context: context)
        entity.txn_id = generateUniqueId()
        entity.local_id = Int64(AppStorageManager.shared.userId ?? "") ?? 0
        entity.drug_id = drugId ?? 0
        entity.batch_id = batchId
        entity.rx_no = rxNo
        entity.count_type = countType.rawValue
        entity.status = CountStatus.PARTIAL.rawValue
        entity.is_deleted = false
        entity.barcode_image = barcodeImagePath
        entity.is_from_pms = isFromPms
        entity.is_synced = false
        entity.target_count = targetCount
        entity.is_ndc_verfied = false
        entity.expiry = expirationDate
        entity.lot_no = lotNumber
        entity.bucket_id = bucketId
        entity.user = user

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        entity.created_at = now
        entity.updated_at = now

        if let drugId, let drug = DrugMasterDAO.shared.fetchById(drugId) {
            entity.drug = drug
            drug.addToTransactions(entity)
        }

        CoreDataManager.shared.save(context: context)
        return entity
    }

    // MARK: - Read

    func fetchById(_ txnId: Int64) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchLatest(for user: UserEntity) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchPartial(
        for user: UserEntity,
        countType: CountType
    ) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND count_type == %@ AND status == %@",
            user, countType.rawValue, CountStatus.PARTIAL.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "is_from_pms", ascending: false),
            NSSortDescriptor(key: "created_at", ascending: false)
        ]
        return (try? context.fetch(request)) ?? []
    }

    func fetchByTimeRange(
        for user: UserEntity,
        startTime: Int64,
        endTime: Int64
    ) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND created_at >= %lld AND created_at <= %lld",
            user, startTime, endTime
        )
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchByBatch(batchId: Int64) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "batch_id == %lld AND is_deleted == false", batchId)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func fetchPartialFromPms(for user: UserEntity, countType: CountType) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND count_type == %@ AND status == %@ AND is_from_pms == true",
            user, countType.rawValue, CountStatus.PARTIAL.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "is_from_pms", ascending: false),
            NSSortDescriptor(key: "created_at", ascending: false)
        ]
        return (try? context.fetch(request)) ?? []
    }

    func fetchCompletedUnsynced() -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND is_synced == false AND status == %@ AND count_type == %@",
            CountStatus.COMPLETED.rawValue, CountType.FIXED.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func getContainerPendingTarget(txnId: Int64) -> Int32 {
        guard let txn = fetchById(txnId) else { return 0 }
        let containerCount = TransactionDetailDAO.shared.totalCountForStep(txnId: txnId, step: .containerInitiate)
        return max(containerCount - txn.target_count, 0)
    }

    func updateCounts(txnId: Int64, bottleQty: Int32? = nil, looseQty: Int32? = nil) {
        guard let txn = fetchById(txnId) else { return }
        if let bottleQty { txn.bottle_qty += bottleQty }
        if let looseQty { txn.loose_qty += looseQty }
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func countTransactions(for user: UserEntity, countType: CountType, status: CountStatus) -> Int {
        let request: NSFetchRequest<NSNumber> = NSFetchRequest(entityName: "PillCountTransactionEntity")
        request.resultType = .countResultType
        request.predicate = NSPredicate(
            format: "user == %@ AND count_type == %@ AND status == %@ AND is_deleted == false",
            user, countType.rawValue, status.rawValue
        )
        return (try? context.count(for: request)) ?? 0
    }

    // MARK: - Update

    func updateDrug(txnId: Int64, drugId: Int64) {
        guard let txn = fetchById(txnId),
              let drug = DrugMasterDAO.shared.fetchById(drugId) else { return }
        txn.drug_id = drugId
        txn.drug = drug
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func updateTargetCount(txnId: Int64, targetCount: Int32) {
        guard let txn = fetchById(txnId) else { return }
        txn.target_count = targetCount
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func updateNote(txnId: Int64, note: String) {
        guard let txn = fetchById(txnId) else { return }
        txn.note = note
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func updateStatus(txnId: Int64, status: CountStatus) {
        guard let txn = fetchById(txnId) else { return }
        txn.status = status.rawValue
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func updateNdcVerified(txnId: Int64, verified: Bool) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_ndc_verfied = verified
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func updateSynced(txnId: Int64) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_synced = true
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func update(
        txnId: Int64,
        drugId: Int64?,
        countType: CountType,
        targetCount: Int32?,
        barcodeImagePath: String?
    ) {
        guard let txn = fetchById(txnId) else { return }
        if let drugId, let drug = DrugMasterDAO.shared.fetchById(drugId) {
            txn.drug_id = drugId
            txn.drug = drug
        }
        txn.count_type = countType.rawValue
        txn.is_synced = false
        if let targetCount { txn.target_count = targetCount }
        if let barcodeImagePath, !barcodeImagePath.isEmpty { txn.barcode_image = barcodeImagePath }
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    // MARK: - Delete

    func softDelete(txnId: Int64) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_deleted = true
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        }catch {
            print("Failed to delete DrugMasterEntity: \(error)")
        }
    }

    // MARK: - Private

    private func generateUniqueId() -> Int64 {
        let key = "txnTransactionIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
