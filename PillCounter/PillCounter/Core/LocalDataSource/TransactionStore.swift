//
//  TransactionDAO.swift
//  PillCounter
//

import CoreData
import Combine

final class TransactionStore {

    static let shared = TransactionStore()
    private init() {}

    let transactionsDidChange = PassthroughSubject<Void, Never>()

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
        serialNumber: String? = nil,
        rxNo: String? = nil,
        bucketId: String? = nil,
        priority: String? = nil,
        workFlowStep: String? = nil
    ) -> PillCountTransactionEntity {
        let entity = PillCountTransactionEntity(context: context)
        entity.txn_id = generateUniqueId()
        entity.local_id = Int64(AppStorageManager.shared.userId ?? "") ?? 0
        entity.drug_id = drugId ?? 0
        entity.batch_id = batchId
        entity.rx_no = rxNo
        entity.txn_priority = priority
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
        entity.serial_no = serialNumber
        entity.bucket_id = bucketId
        entity.workflow_step = workFlowStep
        entity.user = user

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        entity.created_at = now
        entity.updated_at = now

        if let drugId, let drug = DrugCatalogStore.shared.fetchById(drugId) {
            entity.drug = drug
            drug.addToTransactions(entity)
        }

        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] CREATED — txnId: \(entity.txn_id), drugId: \(entity.drug_id), countType: \(countType.rawValue), batchId: \(batchId), isFromPms: \(isFromPms), lotNo: \(lotNumber ?? "-"), serialNo: \(serialNumber ?? "-"), expiry: \(expirationDate ?? "-")")
        transactionsDidChange.send()
        return entity
    }

    // MARK: - Read

    func fetchById(_ txnId: Int64) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        refreshDecrypted(result)
        return result
    }

    func fetchLatest(for user: UserEntity) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        refreshDecrypted(result)
        return result
    }

    func fetchPartial(
        for user: UserEntity,
        countType: CountType
    ) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        let completedStatuses = [CountStatus.COMPLETED.rawValue]
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND batch_id == 0 AND count_type == %@ AND NOT (status IN %@)",
            user, countType.rawValue, completedStatuses
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "is_from_pms", ascending: false),
            NSSortDescriptor(key: "created_at", ascending: false)
        ]
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
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
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
    }

    func fetchAllRxNos(for user: UserEntity) -> [String] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND status != %@",
            user, CountStatus.COMPLETED.rawValue
        )
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results.compactMap { $0.rx_no }.filter { !$0.isEmpty }
    }

    func fetchByRxNo(_ rxNo: String, for user: UserEntity) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND status != %@",
            user, CountStatus.COMPLETED.rawValue
        )
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results.filter { $0.rx_no == rxNo }
    }

    /// Convenience overload for callers without a UserEntity reference (e.g. the image web server).
    /// Resolves the currently logged-in user from storage; returns [] when no user is active.
    func fetchByRxNo(_ rxNo: String) -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        return fetchByRxNo(rxNo, for: user)
    }

    /// Reverse lookup used by the image web server to resolve a delivered
    /// barcode-image filename back to the owning transaction. `barcode_image`
    /// is field-level encrypted at rest, so it cannot be matched via an
    /// NSPredicate against the SQLite row (that would compare against
    /// ciphertext) — fetch and compare the decrypted in-memory value instead.
    func txnId(forBarcodeImage filename: String) -> Int64? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        guard let results = try? context.fetch(request) else { return nil }
        results.forEach { refreshDecrypted($0) }
        return results.first { $0.barcode_image == filename }?.txn_id
    }

    func fetchDeletedByRxNo(_ rxNo: String, for user: UserEntity) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND is_deleted == true", user)
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
            .filter { $0.rx_no == rxNo }
            .sorted { $0.updated_at > $1.updated_at }
            .first
    }

    func restoreDeleted(txnId: Int64) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_deleted = false
        txn.status = CountStatus.PARTIAL.rawValue
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] RESTORED deleted — txnId: \(txnId)")
        transactionsDidChange.send()
    }

    func updatePriority(txnId: Int64, priority: String?) {
        guard let txn = fetchById(txnId) else { return }
        txn.txn_priority = priority
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED priority — txnId: \(txnId), priority: \(priority ?? "nil")")
    }

    func updateFromHL7Edit(txnId: Int64, drugId: Int64, targetCount: Int32, priority: String?) {
        guard let txn = fetchById(txnId),
              let drug = DrugCatalogStore.shared.fetchById(drugId) else { return }
        txn.drug_id = drugId
        txn.drug = drug
        txn.target_count = targetCount
        txn.txn_priority = priority
        txn.is_synced = false
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] HL7 EDIT applied — txnId: \(txnId), drugId: \(drugId), targetCount: \(targetCount), priority: \(priority ?? "nil")")
        transactionsDidChange.send()
    }

    func fetchByBatch(batchId: Int64) -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND batch_id == %lld AND is_deleted == false",
            user, batchId
        )
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
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
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
    }

    func fetchCompletedUnsynced(for user: UserEntity) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND is_deleted == false AND is_synced == false AND status == %@ AND count_type == %@",
            user, CountStatus.COMPLETED.rawValue, CountType.FIXED.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        return results
    }

    /// Convenience overload for callers without a UserEntity reference (e.g. HL7 sync queues).
    /// Resolves the currently logged-in user from storage; returns [] when no user is active.
    func fetchCompletedUnsynced() -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        return fetchCompletedUnsynced(for: user)
    }

    func fetchAll(for user: UserEntity) -> [PillCountTransactionEntity] {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND is_deleted == false", user)
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        let results = (try? context.fetch(request)) ?? []
        results.forEach { refreshDecrypted($0) }
        StoreLogger.log(
            dao: "TransactionDAO", op: "fetchAll",
            columns: ["txn_id", "rx_no", "drug_name", "count_type", "status", "batch_id", "target_count", "lot_no", "serial_no"],
            rows: results.map { [
                "\($0.txn_id)",
                $0.rx_no ?? "-",
                $0.drug?.drug_name ?? "-",
                $0.count_type ?? "-",
                $0.status ?? "-",
                "\($0.batch_id)",
                "\($0.target_count)",
//                "\($0.is_from_pms)",
//                "\($0.is_synced)",
                "\($0.lot_no)",
//                "\($0.expiry_date)",
                $0.serial_no ?? "",
            ]}
        )
        return results
    }

    func getWorkflowStep(txn: PillCountTransactionEntity) -> ControlledStep? {
        guard
            let stepValue = txn.workflow_step,
            let step = ControlledStep(rawValue: stepValue)
        else {
            return nil
        }
        return step
    }

    func updateWorkflowStep(txnId: Int64, step: ControlledStep) {
        guard let txn = fetchById(txnId) else { return }
        txn.workflow_step = step.rawValue
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        transactionsDidChange.send()
    }

    func getContainerPendingTarget(txnId: Int64) -> Int32 {
        guard let txn = fetchById(txnId) else { return 0 }
        let containerCount = TransactionDetailStore.shared.totalCountForStep(txnId: txnId, step: .containerInitiate)
        return max(containerCount - txn.target_count, 0)
    }

    /// Increments the given count fields by the provided amounts (additive).
    func updateCounts(txnId: Int64, bottleQty: Int32? = nil, looseQty: Int32? = nil, openBottleQty: Int32? = nil) {
        guard let txn = fetchById(txnId) else { return }
        if let bottleQty { txn.bottle_qty += bottleQty }
        if let looseQty { txn.loose_qty += looseQty }
        if let openBottleQty { txn.open_bottle_qty += openBottleQty }
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        transactionsDidChange.send()
        print("📋 [TransactionDAO] UPDATED counts — txnId: \(txnId), bottleQty: \(bottleQty.map { "+\($0)" } ?? "-"), looseQty: \(looseQty.map { "+\($0)" } ?? "-"), openBottleQty: \(openBottleQty.map { "+\($0)" } ?? "-")")
    }

    /// Sets the given count fields to absolute values (non-additive). Use for open pill count finalization.
    func setAbsoluteCounts(txnId: Int64, bottleQty: Int32? = nil, looseQty: Int32? = nil, openBottleQty: Int32? = nil) {
        guard let txn = fetchById(txnId) else { return }
        if let bottleQty { txn.bottle_qty = bottleQty }
        if let looseQty { txn.loose_qty = looseQty }
        if let openBottleQty { txn.open_bottle_qty = openBottleQty }
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        transactionsDidChange.send()
        print("📋 [TransactionDAO] SET absolute counts — txnId: \(txnId), bottleQty: \(String(describing: bottleQty)), looseQty: \(String(describing: looseQty)), openBottleQty: \(String(describing: openBottleQty))")
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
              let drug = DrugCatalogStore.shared.fetchById(drugId) else { return }
        txn.drug_id = drugId
        txn.drug = drug
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED drug — txnId: \(txnId), drugId: \(drugId)")
    }

    func updateTargetCount(txnId: Int64, targetCount: Int32) {
        guard let txn = fetchById(txnId) else { return }
        txn.target_count = targetCount
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED targetCount — txnId: \(txnId), targetCount: \(targetCount)")
    }

    func updateNote(txnId: Int64, note: String) {
        guard let txn = fetchById(txnId) else { return }
        txn.note = note
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED note — txnId: \(txnId)")
    }

    func updateStatus(txnId: Int64, status: CountStatus) {
        guard let txn = fetchById(txnId) else { return }
        txn.status = status.rawValue
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED status — txnId: \(txnId), status: \(status.rawValue)")
        transactionsDidChange.send()
    }

    func updateGlovesDetected(txnId: Int64, detected: Bool) {
        guard let txn = fetchById(txnId) else { return }
        txn.gloves_detected = detected
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED glovesDetected — txnId: \(txnId), detected: \(detected)")
    }

    func updateHazardousTrayDetected(txnId: Int64, detected: Bool) {
        guard let txn = fetchById(txnId) else { return }
        txn.hazardous_tray_detected = detected
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED hazardousTrayDetected — txnId: \(txnId), detected: \(detected)")
    }

    func updateNdcVerified(txnId: Int64, verified: Bool) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_ndc_verfied = verified
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        transactionsDidChange.send()
        print("📋 [TransactionDAO] UPDATED ndcVerified — txnId: \(txnId), verified: \(verified)")
    }

    func updateSynced(txnId: Int64) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_synced = true
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED synced — txnId: \(txnId)")

        if attemptHardDeleteIfEligible(txnId: txnId) { return }

        transactionsDidChange.send()
    }

    /// All image filenames (barcode + detail images) that belong to this
    /// transaction and must be confirmed delivered to the PMS before the
    /// transaction is eligible for hard deletion.
    func expectedImageFilenames(txnId: Int64) -> [String] {
        guard let txn = fetchById(txnId) else { return [] }
        var filenames: [String] = []
        if let barcodeImage = txn.barcode_image, !barcodeImage.isEmpty {
            filenames.append(barcodeImage)
        }
        filenames += TransactionDetailStore.shared.fetchAll(txnId: txnId)
            .compactMap { $0.image_path }
            .filter { !$0.isEmpty }
        return filenames
    }

    /// Hard-deletes the transaction (and, via cascade, its details) once the
    /// PMS has ACKed the dispense AND every one of its images has been
    /// confirmed delivered — but only when local storage is not allowed for
    /// this account. Called both after a positive ACK (`updateSynced`) and
    /// after an image delivery is confirmed (`ImageWebServer`), since either
    /// event can be the one that completes the pair. Returns true if the
    /// transaction was deleted.
    @discardableResult
    func attemptHardDeleteIfEligible(txnId: Int64) -> Bool {
        guard let txn = fetchById(txnId) else { return false }
        guard !AppStorageManager.shared.allowLocalStorage,
              txn.count_type == CountType.FIXED.rawValue,
              txn.status == CountStatus.COMPLETED.rawValue
                || txn.status == CountStatus.FORCE_COMPLETED.rawValue,
              txn.is_synced
        else { return false }

        guard ImageDeliveryTracker.shared.allDelivered(expectedImageFilenames(txnId: txnId)) else {
            return false
        }

        hardDelete(txnId: txnId)
        return true
    }

    func update(
        txnId: Int64,
        drugId: Int64?,
        countType: CountType,
        targetCount: Int32?,
        barcodeImagePath: String?,
        substituedDrugId: Int64? = nil,
        isSubstitue: Bool = false
    ) {
        guard let txn = fetchById(txnId) else { return }
        if let drugId, let drug = DrugCatalogStore.shared.fetchById(drugId) {
            txn.drug_id = drugId
            txn.drug = drug
        }

        txn.is_substitute = isSubstitue

        if let substituedDrugId,
           let substituteDrugEntity = DrugCatalogStore.shared.fetchById(substituedDrugId) {
            txn.substitute_drug_id = substituedDrugId
            txn.substitueDrug = substituteDrugEntity
        }

        txn.count_type = countType.rawValue
        txn.is_synced = false
        if let targetCount { txn.target_count = targetCount }
        if let barcodeImagePath, !barcodeImagePath.isEmpty { txn.barcode_image = barcodeImagePath }
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] UPDATED — txnId: \(txnId), drugId: \(drugId ?? 0), countType: \(countType.rawValue), targetCount: \(targetCount ?? 0)")
    }

    // MARK: - Delete

    func softDelete(txnId: Int64) {
        guard let txn = fetchById(txnId) else { return }
        txn.is_deleted = true
        txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] SOFT DELETED — txnId: \(txnId)")
        transactionsDidChange.send()
    }

    /// Permanently removes the transaction row; its details cascade-delete
    /// via the CoreData model's Cascade delete rule on
    /// `pillCountTransactionDetails`.
    func hardDelete(txnId: Int64) {
        guard let txn = fetchById(txnId) else { return }
        context.delete(txn)
        CoreDataManager.shared.save(context: context)
        print("📋 [TransactionDAO] HARD DELETED — txnId: \(txnId)")
        transactionsDidChange.send()
    }

    /// Backstop for when PMS image delivery never completes (misconfigured
    /// rx number, integration abandoned, PMS offline indefinitely). Hard-
    /// deletes any synced, completed FIXED transaction older than `maxAge`
    /// once local storage is disallowed, regardless of image-delivery state
    /// — bounding worst-case on-device retention. The primary deletion path
    /// (`attemptHardDeleteIfEligible`) already deletes promptly once images
    /// are confirmed delivered; this only catches what that path never will.
    func sweepStaleSyncedTransactions(olderThan maxAge: TimeInterval) {
        guard !AppStorageManager.shared.allowLocalStorage else { return }

        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(maxAge * 1000)
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "is_deleted == false AND is_synced == true AND count_type == %@ AND (status == %@ OR status == %@) AND updated_at <= %lld",
            CountType.FIXED.rawValue, CountStatus.COMPLETED.rawValue, CountStatus.FORCE_COMPLETED.rawValue, cutoff
        )
        guard let stale = try? context.fetch(request), !stale.isEmpty else { return }

        for txn in stale {
            print("📋 [TransactionDAO] TTL SWEEP hard-deleting stale synced txn — txnId: \(txn.txn_id), updatedAt: \(txn.updated_at)")
            context.delete(txn)
        }
        CoreDataManager.shared.save(context: context)
        transactionsDidChange.send()
    }

    func deleteAll() {
        let request: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionEntity.fetchRequest()
        do {
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
            print("📋 [TransactionDAO] DELETED ALL — all transactions removed")
        } catch {
            print("Failed to delete DrugMasterEntity: \(error)")
        }
    }

    // MARK: - Private

    /// Deterministically decrypts the object's encrypted fields in place
    /// (e.g. rx_no, barcode_image, lot_no, note). Replaces the old
    /// context.refresh(_, mergeChanges: false) refault, which did NOT reliably
    /// re-run awakeFromFetch and could surface ciphertext written by willSave
    /// in the same session.
    private func refreshDecrypted(_ object: NSManagedObject) {
        object.decryptEncryptedFieldsInPlace()
    }

    /// Resolves the currently logged-in user from CoreData.
    /// Returns nil when no user ID is stored (e.g. during or after logout).
    private func currentUserEntity() -> UserEntity? {
        guard let userId = AppStorageManager.shared.userId, !userId.isEmpty else { return nil }
        return UserStore.shared.fetchByUserId(userId)
    }

    private func generateUniqueId() -> Int64 {
        let key = "txnTransactionIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
