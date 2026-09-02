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

    /// Confines every Core Data touch to `context`'s owning queue (the main
    /// queue for `viewContext`). Background callers — HL7 sync queues, the
    /// image web server — previously called straight into `context.fetch`/
    /// `save` from their own DispatchQueue with no hop, racing main-thread
    /// ViewModel fetches on the same context and objects. `performAndWait`
    /// is safe to call re-entrantly when already on the right queue (runs
    /// the block immediately), so nested Store calls on the main thread are
    /// unaffected.
    private func sync<T>(_ block: () -> T) -> T {
        context.performAndWait(block)
    }

    // MARK: - Create

    func create(
        for user: UserEntity,
        drugId: Int64?,
        isDispense: Bool,
        batchId: Int64 = 0,
        isFromPms: Bool = false,
        drugName: String? = nil,
        targetCount: Int32 = 0,
        isControlled: Bool? = nil,
        rxNo: String? = nil,
        bucketId: String? = nil,
        priority: String? = nil,
        workFlowStep: String? = nil,
        refillNo: String? = nil
    ) -> PillCountTransactionEntity {
        sync {
            let entity = PillCountTransactionEntity(context: context)
            entity.txn_id = generateUniqueId()
            entity.local_id = Int64(AppStorageManager.shared.userId ?? "") ?? 0
            entity.drug_id = drugId ?? 0
            entity.batch_id = batchId
            entity.rx_no = rxNo
            entity.refill_no = refillNo
            entity.txn_priority = priority
            entity.is_dispense = isDispense
            entity.status = CountStatus.PARTIAL.rawValue
            entity.is_deleted = false
            entity.is_from_pms = isFromPms
            entity.is_synced = false
            entity.target_count = targetCount
            entity.is_ndc_verfied = false
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
            StoreLogger.debug("📋 [TransactionDAO] CREATED — txnId: \(entity.txn_id), drugId: \(entity.drug_id), isDispense: \(isDispense), batchId: \(batchId), isFromPms: \(isFromPms)")
            transactionsDidChange.send()
            return entity
        }
    }

    // MARK: - Read

    func fetchById(_ txnId: Int64) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    /// Same as `fetchById(_:)`, but fetches from an explicit context instead
    /// of the default `viewContext` — for callers (HL7 sync queues) that need
    /// the returned object, and everything reachable from it, to stay on a
    /// background context for the duration of a longer piece of work (e.g.
    /// building an HL7 message from its relationships) rather than crossing
    /// back to `viewContext` mid-operation.
    func fetchById(_ txnId: Int64, in context: NSManagedObjectContext) -> PillCountTransactionEntity? {
        context.performAndWait {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    func fetchLatest(for user: UserEntity) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "user == %@", user)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    func fetchPartial(
        for user: UserEntity,
        isDispense: Bool
    ) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            let completedStatuses = [CountStatus.COMPLETED.rawValue]
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND batch_id == 0 AND is_dispense == %@ AND NOT (status IN %@)",
                user, NSNumber(value: isDispense), completedStatuses
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "is_from_pms", ascending: false),
                NSSortDescriptor(key: "created_at", ascending: false)
            ]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            logRefillNos(op: "fetchPartial", results: results)
            return results
        }
    }

    /// Same as `fetchPartial(for:isDispense:)`, but fetches via an explicit
    /// context — see `fetchById(_:in:)`. `user` must already belong to
    /// `context` (fetch it via `UserStore.fetchByUserId(_:in:)` first).
    func fetchPartial(
        for user: UserEntity,
        isDispense: Bool,
        in context: NSManagedObjectContext
    ) -> [PillCountTransactionEntity] {
        context.performAndWait {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            let completedStatuses = [CountStatus.COMPLETED.rawValue]
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND batch_id == 0 AND is_dispense == %@ AND NOT (status IN %@)",
                user, NSNumber(value: isDispense), completedStatuses
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "is_from_pms", ascending: false),
                NSSortDescriptor(key: "created_at", ascending: false)
            ]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    /// Paginated variant of `fetchPartial` — same predicate/sort, bounded to
    /// `limit` rows starting at `offset`, so a large pending queue can be
    /// browsed via infinite scroll instead of being silently capped.
    func fetchPartialPage(
        for user: UserEntity,
        isDispense: Bool,
        limit: Int,
        offset: Int
    ) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            let completedStatuses = [CountStatus.COMPLETED.rawValue]
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND batch_id == 0 AND is_dispense == %@ AND NOT (status IN %@)",
                user, NSNumber(value: isDispense), completedStatuses
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "is_from_pms", ascending: false),
                NSSortDescriptor(key: "created_at", ascending: false)
            ]
            request.fetchLimit = limit
            request.fetchOffset = offset
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    func fetchByTimeRange(
        for user: UserEntity,
        startTime: Int64,
        endTime: Int64
    ) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND created_at >= %lld AND created_at <= %lld",
                user, startTime, endTime
            )
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            logRefillNos(op: "fetchByTimeRange", results: results)
            return results
        }
    }

    /// Same as `fetchByTimeRange(for:startTime:endTime:)`, but fetches via
    /// an explicit context — see `fetchPartial(for:isDispense:in:)`.
    func fetchByTimeRange(
        for user: UserEntity,
        startTime: Int64,
        endTime: Int64,
        in context: NSManagedObjectContext
    ) -> [PillCountTransactionEntity] {
        context.performAndWait {
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
    }

    /// Paginated variant of `fetchByTimeRange` — same predicate/sort, but
    /// only materializes/decrypts `limit` rows starting at `offset`, so
    /// browsing a large date range doesn't pull the whole range into memory
    /// (or decrypt every row) at once.
    func fetchByTimeRangePage(
        for user: UserEntity,
        startTime: Int64,
        endTime: Int64,
        limit: Int,
        offset: Int
    ) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND created_at >= %lld AND created_at <= %lld",
                user, startTime, endTime
            )
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    func fetchAllRxNos(for user: UserEntity) -> [String] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND status != %@",
                user, CountStatus.COMPLETED.rawValue
            )
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results.compactMap { $0.rx_no }.filter { !$0.isEmpty }
        }
    }

    func fetchByRxNo(_ rxNo: String, for user: UserEntity) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND status != %@",
                user, CountStatus.COMPLETED.rawValue
            )
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results.filter { $0.rx_no == rxNo }
        }
    }

    /// Convenience overload for callers without a UserEntity reference (e.g. the image web server).
    /// Resolves the currently logged-in user from storage; returns [] when no user is active.
    func fetchByRxNo(_ rxNo: String) -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        return fetchByRxNo(rxNo, for: user)
    }

    /// HL7 identifier lookups used by the image web server's `getby*` endpoints.
    /// Fields are encrypted at rest for some entities elsewhere in this store, but
    /// these HL7 id columns are not, so they can be matched directly via NSPredicate.

    func getByMessageControlId(_ messageControlId: String) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "hl7_message_control_id == %@ AND is_deleted == false", messageControlId)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    func getBySequenceNumber(_ sequenceNumber: String) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "hl7_sequence_number == %@ AND is_deleted == false", sequenceNumber)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    func getByTransactionOrderId(_ transactionOrderId: String) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "transaction_order_id == %@ AND is_deleted == false", transactionOrderId)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = 1
            guard let result = try? context.fetch(request).first else { return nil }
            refreshDecrypted(result)
            return result
        }
    }

    /// `rx_no` is field-level encrypted, so filter in-memory after decrypting rather
    /// than via NSPredicate (which would compare against ciphertext).
    func getByRxNoAndFillNo(_ rxNo: String, fillNo: String) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "is_deleted == false")
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
                .filter { $0.rx_no == rxNo && $0.refill_no == fillNo }
                .sorted { $0.created_at > $1.created_at }
                .first
        }
    }

    func getMostRecentByRxNo(_ rxNo: String) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "is_deleted == false")
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
                .filter { $0.rx_no == rxNo }
                .sorted { $0.created_at > $1.created_at }
                .first
        }
    }

    /// Reverse lookup used by the image web server to resolve a delivered
    /// bottle barcode-image filename back to the owning transaction. Bottle
    /// image paths live inside `bottle_info_list_json`, which is not itself
    /// field-level encrypted, but the parent row is fetched and decrypted
    /// like other lookups here for consistency.
    func txnId(forBarcodeImage filename: String) -> Int64? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            guard let results = try? context.fetch(request) else { return nil }
            results.forEach { refreshDecrypted($0) }
            return results.first { txn in
                [BottleInfo].decode(from: txn.bottle_info_list_json).contains { $0.barcodeImagePath == filename }
            }?.txn_id
        }
    }

    func fetchDeletedByRxNo(_ rxNo: String, for user: UserEntity) -> PillCountTransactionEntity? {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "user == %@ AND is_deleted == true", user)
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
                .filter { $0.rx_no == rxNo }
                .sorted { $0.updated_at > $1.updated_at }
                .first
        }
    }

    func restoreDeleted(txnId: Int64) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.is_deleted = false
            txn.status = CountStatus.PARTIAL.rawValue
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] RESTORED deleted — txnId: \(txnId)")
        }
        transactionsDidChange.send()
    }

    /// Stores the HL7 identifiers captured from an inbound order message, used as
    /// lookup keys by the on-device image server's `getby*` endpoints.
    func setHl7Identifiers(
        txnId: Int64,
        messageControlId: String? = nil,
        sequenceNumber: String? = nil,
        transactionOrderId: String? = nil
    ) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            if let messageControlId { txn.hl7_message_control_id = messageControlId }
            if let sequenceNumber { txn.hl7_sequence_number = sequenceNumber }
            if let transactionOrderId { txn.transaction_order_id = transactionOrderId }
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] SET HL7 identifiers — txnId: \(txnId), messageControlId: \(messageControlId ?? "nil"), sequenceNumber: \(sequenceNumber ?? "nil"), transactionOrderId: \(transactionOrderId ?? "nil")")
        }
    }

    func updatePriority(txnId: Int64, priority: String?) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.txn_priority = priority
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED priority — txnId: \(txnId), priority: \(priority ?? "nil")")
        }
    }

    func updateFromHL7Edit(txnId: Int64, drugId: Int64, targetCount: Int32, priority: String?, refillNo: String? = nil) {
        sync {
            guard let txn = fetchByIdLocked(txnId),
                  let drug = DrugCatalogStore.shared.fetchById(drugId) else { return }
            txn.drug_id = drugId
            txn.drug = drug
            txn.target_count = targetCount
            txn.txn_priority = priority
            if let refillNo { txn.refill_no = refillNo }
            txn.is_synced = false
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] HL7 EDIT applied — txnId: \(txnId), drugId: \(drugId), targetCount: \(targetCount), priority: \(priority ?? "nil"), refillNo: \(refillNo ?? "nil")")
        }
        transactionsDidChange.send()
    }

    func fetchByBatch(batchId: Int64) -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        return sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND batch_id == %lld AND is_deleted == false",
                user, batchId
            )
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            logRefillNos(op: "fetchByBatch", results: results)
            return results
        }
    }

    func fetchPartialFromPms(for user: UserEntity, isDispense: Bool) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND is_dispense == %@ AND status == %@ AND is_from_pms == true",
                user, NSNumber(value: isDispense), CountStatus.PARTIAL.rawValue
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "is_from_pms", ascending: false),
                NSSortDescriptor(key: "created_at", ascending: false)
            ]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            logRefillNos(op: "fetchPartialFromPms", results: results)
            return results
        }
    }

    func fetchCompletedUnsynced(for user: UserEntity) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND is_synced == false AND status == %@ AND is_dispense == %@",
                user, CountStatus.COMPLETED.rawValue, NSNumber(value: true)
            )
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            logRefillNos(op: "fetchCompletedUnsynced", results: results)
            return results
        }
    }

    /// Convenience overload for callers without a UserEntity reference (e.g. HL7 sync queues).
    /// Resolves the currently logged-in user from storage; returns [] when no user is active.
    func fetchCompletedUnsynced() -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        return fetchCompletedUnsynced(for: user)
    }

    /// Paginated variant — same predicate/sort as `fetchCompletedUnsynced`,
    /// bounded to `limit` rows starting at `offset` for screens (Unsynced)
    /// that page through this list instead of loading it all at once.
    func fetchCompletedUnsyncedPage(limit: Int, offset: Int) -> [PillCountTransactionEntity] {
        guard let user = currentUserEntity() else { return [] }
        return sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND is_synced == false AND status == %@ AND is_dispense == %@",
                user, CountStatus.COMPLETED.rawValue, NSNumber(value: true)
            )
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
    }

    func fetchAll(for user: UserEntity) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "user == %@ AND is_deleted == false", user)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            #if DEBUG
            StoreLogger.log(
                dao: "TransactionDAO", op: "fetchAll",
                columns: ["txn_id", "rx_no", "drug_name", "is_dispense", "status", "batch_id", "target_count", "refill_no" , "bottle_info_list_json" ],
                rows: results.map { [
                    "\($0.txn_id)",
                    $0.rx_no ?? "-",
                    $0.drug?.drug_name ?? "-",
                    "\($0.is_dispense)",
                    $0.status ?? "-",
                    "\($0.batch_id)",
                    "\($0.target_count)",
                    "\($0.refill_no ?? "-")",
                    "\($0.bottle_info_list_json)"
                ]}
            )
            #endif
            return results
        }
    }

    /// Paginated variant of `fetchAll(for:)` — bounded to `limit` rows
    /// starting at `offset` (sorted newest-first, same as `fetchAll`), so
    /// callers that only need "the most recent N" don't pull and decrypt
    /// the user's entire transaction history.
    func fetchAllPage(for user: UserEntity, limit: Int, offset: Int) -> [PillCountTransactionEntity] {
        sync {
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(format: "user == %@ AND is_deleted == false", user)
            request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
            request.fetchLimit = limit
            request.fetchOffset = offset
            let results = (try? context.fetch(request)) ?? []
            results.forEach { refreshDecrypted($0) }
            return results
        }
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
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.workflow_step = step.rawValue
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
        }
        transactionsDidChange.send()
    }

    func getContainerPendingTarget(txnId: Int64) -> Int32 {
        guard let txn = fetchById(txnId) else { return 0 }
        let containerCount = TransactionDetailStore.shared.totalCountForStep(txnId: txnId, step: .containerInitiate)
        return max(containerCount - txn.target_count, 0)
    }

    func countTransactions(for user: UserEntity, isDispense: Bool, status: CountStatus) -> Int {
        sync {
            let request: NSFetchRequest<NSNumber> = NSFetchRequest(entityName: "PillCountTransactionEntity")
            request.resultType = .countResultType
            request.predicate = NSPredicate(
                format: "user == %@ AND is_dispense == %@ AND status == %@ AND is_deleted == false",
                user, NSNumber(value: isDispense), status.rawValue
            )
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// True count of dispense transactions in `[startTime, endTime]` for
    /// `user`, optionally narrowed to a status — independent of any page
    /// size, so a paginated display list can show an accurate status-filter
    /// count without fetching/decrypting every row in the range.
    func countByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64, status: CountStatus?) -> Int {
        sync {
            let request = NSFetchRequest<NSNumber>(entityName: "PillCountTransactionEntity")
            request.resultType = .countResultType
            if let status {
                request.predicate = NSPredicate(
                    format: "user == %@ AND is_deleted == false AND created_at >= %lld AND created_at <= %lld AND is_dispense == true AND status == %@",
                    user, startTime, endTime, status.rawValue
                )
            } else {
                request.predicate = NSPredicate(
                    format: "user == %@ AND is_deleted == false AND created_at >= %lld AND created_at <= %lld AND is_dispense == true",
                    user, startTime, endTime
                )
            }
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// True count of pending (not completed, not on-hold, not yet batched)
    /// dispense transactions for `user`, matching the same base predicate as
    /// `fetchPartial`/the dashboard's `allPendingDispense` filter, further
    /// narrowed by a dashboard stat-card facet — independent of row count,
    /// so the dashboard's stat cards don't need to fetch/decrypt every
    /// pending row just to report how many match each facet.
    enum PendingDispenseFacet {
        /// No extra narrowing — total pending dispense count.
        case all
        case highPriority
        case hazardous
        case controlled
    }

    func countPendingDispense(for user: UserEntity, facet: PendingDispenseFacet) -> Int {
        sync {
            let request = NSFetchRequest<NSNumber>(entityName: "PillCountTransactionEntity")
            request.resultType = .countResultType
            var format = "user == %@ AND is_deleted == false AND batch_id == 0 AND is_dispense == true AND NOT (status IN %@) AND status != %@"
            var args: [Any] = [user, [CountStatus.COMPLETED.rawValue], CountStatus.ON_HOLD.rawValue]
            switch facet {
            case .all:
                break
            case .highPriority:
                format += " AND txn_priority ==[c] %@"
                args.append("high")
            case .hazardous:
                format += " AND drug.is_hazardous == true"
            case .controlled:
                format += " AND drug.drug_type != nil AND drug.drug_type != %@"
                args.append("")
            }
            request.predicate = NSPredicate(format: format, argumentArray: args)
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// True total matching `fetchCompletedUnsynced`, independent of any page
    /// size — so a capped/paginated display list can still show an accurate
    /// "N unsynced" count without fetching/decrypting every matching row.
    func countCompletedUnsynced() -> Int {
        guard let user = currentUserEntity() else { return 0 }
        return sync {
            let request: NSFetchRequest<NSNumber> = NSFetchRequest(entityName: "PillCountTransactionEntity")
            request.resultType = .countResultType
            request.predicate = NSPredicate(
                format: "user == %@ AND is_deleted == false AND is_synced == false AND status == %@ AND is_dispense == %@",
                user, CountStatus.COMPLETED.rawValue, NSNumber(value: true)
            )
            return (try? context.count(for: request)) ?? 0
        }
    }

    // MARK: - Update

    func updateDrug(txnId: Int64, drugId: Int64) {
        sync {
            guard let txn = fetchByIdLocked(txnId),
                  let drug = DrugCatalogStore.shared.fetchById(drugId) else { return }
            txn.drug_id = drugId
            txn.drug = drug
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED drug — txnId: \(txnId), drugId: \(drugId)")
        }
    }

    func updateTargetCount(txnId: Int64, targetCount: Int32) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.target_count = targetCount
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED targetCount — txnId: \(txnId), targetCount: \(targetCount)")
        }
    }

    func updateNote(txnId: Int64, note: String) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.note = note
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED note — txnId: \(txnId)")
        }
    }

    func updateStatus(txnId: Int64, status: CountStatus) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.status = status.rawValue
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED status — txnId: \(txnId), status: \(status.rawValue)")
        }
        transactionsDidChange.send()
    }

    func updateGlovesDetected(txnId: Int64, detected: Bool) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.gloves_detected = detected
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED glovesDetected — txnId: \(txnId), detected: \(detected)")
        }
    }

    func updateHazardousTrayDetected(txnId: Int64, detected: Bool) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.hazardous_tray_detected = detected
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED hazardousTrayDetected — txnId: \(txnId), detected: \(detected)")
        }
    }

    func updateNdcVerified(txnId: Int64, verified: Bool) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.is_ndc_verfied = verified
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED ndcVerified — txnId: \(txnId), verified: \(verified)")
        }
        transactionsDidChange.send()
    }

    // MARK: - Bottle tracking

    func getBottleList(txnId: Int64) -> [BottleInfo] {
        guard let txn = fetchById(txnId) else { return [] }
        return [BottleInfo].decode(from: txn.bottle_info_list_json)
    }

    /// Same as `getBottleList(txnId:)`, but reads via an explicit context —
    /// see `fetchById(_:in:)`.
    func getBottleList(txnId: Int64, in context: NSManagedObjectContext) -> [BottleInfo] {
        guard let txn = fetchById(txnId, in: context) else { return [] }
        return [BottleInfo].decode(from: txn.bottle_info_list_json)
    }

    func setBottleList(txnId: Int64, _ bottles: [BottleInfo]) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.bottle_info_list_json = bottles.encodedJson()
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED bottleList — txnId: \(txnId), bottleCount: \(bottles.count), json: \(txn.bottle_info_list_json ?? "nil")")
        }
    }

    @discardableResult
    func appendBottle(txnId: Int64, _ bottle: BottleInfo) -> [BottleInfo] {
        var bottles = getBottleList(txnId: txnId)
        bottles.append(bottle)
        setBottleList(txnId: txnId, bottles)
        return bottles
    }

    @discardableResult
    func replaceLastBottle(txnId: Int64, _ bottle: BottleInfo) -> [BottleInfo] {
        var bottles = getBottleList(txnId: txnId)
        guard !bottles.isEmpty else { return bottles }
        bottles[bottles.count - 1] = bottle
        setBottleList(txnId: txnId, bottles)
        return bottles
    }

    func updateSynced(txnId: Int64) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.is_synced = true
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED synced — txnId: \(txnId)")
        }

        if attemptHardDeleteIfEligible(txnId: txnId) { return }

        transactionsDidChange.send()
    }

    /// Same as `updateSynced(txnId:)`, but writes via an explicit context —
    /// for the HL7 sync queues, whose ACK-success write previously hopped to
    /// `viewContext`/the main thread per synced transaction (a real
    /// synchronous fetch+save, plus a further fetch+possible-hard-delete via
    /// `attemptHardDeleteIfEligible`), which under a fast-ACKing PMS was
    /// enough repeated main-thread work to read as app lag while sync was
    /// draining. `context`'s own `automaticallyMergesChangesFromParent`
    /// (set on `CoreDataManager.backgroundContext`) carries the write into
    /// `viewContext` without an explicit main-thread save; only the final
    /// `transactionsDidChange.send()` still needs to reach observers on
    /// main, which every one of them already does via `.receive(on: .main)`.
    func updateSynced(txnId: Int64, in context: NSManagedObjectContext) {
        context.performAndWait {
            guard let txn = fetchByIdLocked(txnId, in: context) else { return }
            txn.is_synced = true
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED synced — txnId: \(txnId)")
        }

        if attemptHardDeleteIfEligible(txnId: txnId, in: context) { return }

        transactionsDidChange.send()
    }

    /// All image filenames (barcode + detail images) that belong to this
    /// transaction and must be confirmed delivered to the PMS before the
    /// transaction is eligible for hard deletion.
    func expectedImageFilenames(txnId: Int64) -> [String] {
        guard let txn = fetchById(txnId) else { return [] }
        var filenames: [String] = []
        filenames += [BottleInfo].decode(from: txn.bottle_info_list_json)
            .compactMap { $0.barcodeImagePath }
            .filter { !$0.isEmpty }
        filenames += TransactionDetailStore.shared.fetchAll(txnId: txnId)
            .compactMap { $0.image_path }
            .filter { !$0.isEmpty }
        return filenames
    }

    /// Same as `expectedImageFilenames(txnId:)`, but reads via an explicit
    /// context — see `updateSynced(txnId:in:)`.
    func expectedImageFilenames(txnId: Int64, in context: NSManagedObjectContext) -> [String] {
        guard let txn = fetchById(txnId, in: context) else { return [] }
        var filenames: [String] = []
        filenames += [BottleInfo].decode(from: txn.bottle_info_list_json)
            .compactMap { $0.barcodeImagePath }
            .filter { !$0.isEmpty }
        filenames += TransactionDetailStore.shared.fetchAll(txnId: txnId, in: context)
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
              txn.is_dispense,
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

    /// Same as `attemptHardDeleteIfEligible(txnId:)`, but reads/writes via an
    /// explicit context — see `updateSynced(txnId:in:)`.
    @discardableResult
    func attemptHardDeleteIfEligible(txnId: Int64, in context: NSManagedObjectContext) -> Bool {
        guard let txn = fetchById(txnId, in: context) else { return false }
        guard !AppStorageManager.shared.allowLocalStorage,
              txn.is_dispense,
              txn.status == CountStatus.COMPLETED.rawValue
                || txn.status == CountStatus.FORCE_COMPLETED.rawValue,
              txn.is_synced
        else { return false }

        guard ImageDeliveryTracker.shared.allDelivered(expectedImageFilenames(txnId: txnId, in: context)) else {
            return false
        }

        hardDelete(txnId: txnId, in: context)
        return true
    }

    func update(
        txnId: Int64,
        drugId: Int64?,
        isDispense: Bool,
        targetCount: Int32?,
        substituedDrugId: Int64? = nil,
        isSubstitue: Bool = false
    ) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
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

            txn.is_dispense = isDispense
            txn.is_synced = false
            if let targetCount { txn.target_count = targetCount }
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] UPDATED — txnId: \(txnId), drugId: \(drugId ?? 0), isDispense: \(isDispense), targetCount: \(targetCount ?? 0)")
        }
    }

    // MARK: - Delete

    func softDelete(txnId: Int64) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            txn.is_deleted = true
            txn.updated_at = Int64(Date().timeIntervalSince1970 * 1000)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] SOFT DELETED — txnId: \(txnId)")
        }
        transactionsDidChange.send()
    }

    /// Permanently removes the transaction row; its details cascade-delete
    /// via the CoreData model's Cascade delete rule on
    /// `pillCountTransactionDetails`.
    func hardDelete(txnId: Int64) {
        sync {
            guard let txn = fetchByIdLocked(txnId) else { return }
            context.delete(txn)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] HARD DELETED — txnId: \(txnId)")
        }
        transactionsDidChange.send()
    }

    /// Same as `hardDelete(txnId:)`, but writes via an explicit context —
    /// see `updateSynced(txnId:in:)`.
    func hardDelete(txnId: Int64, in context: NSManagedObjectContext) {
        context.performAndWait {
            guard let txn = fetchByIdLocked(txnId, in: context) else { return }
            context.delete(txn)
            CoreDataManager.shared.save(context: context)
            StoreLogger.debug("📋 [TransactionDAO] HARD DELETED — txnId: \(txnId)")
        }
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

        let deletedAny: Bool = sync {
            let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(maxAge * 1000)
            let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "is_deleted == false AND is_synced == true AND is_dispense == %@ AND (status == %@ OR status == %@) AND updated_at <= %lld",
                NSNumber(value: true), CountStatus.COMPLETED.rawValue, CountStatus.FORCE_COMPLETED.rawValue, cutoff
            )
            guard let stale = try? context.fetch(request), !stale.isEmpty else { return false }

            for txn in stale {
                StoreLogger.debug("📋 [TransactionDAO] TTL SWEEP hard-deleting stale synced txn — txnId: \(txn.txn_id), updatedAt: \(txn.updated_at)")
                context.delete(txn)
            }
            CoreDataManager.shared.save(context: context)
            return true
        }
        if deletedAny {
            transactionsDidChange.send()
        }
    }

    func deleteAll() {
        sync {
            let request: NSFetchRequest<NSFetchRequestResult> = PillCountTransactionEntity.fetchRequest()
            do {
                try context.execute(NSBatchDeleteRequest(fetchRequest: request))
                StoreLogger.debug("📋 [TransactionDAO] DELETED ALL — all transactions removed")
            } catch {
                StoreLogger.debug("Failed to delete PillCountTransactionEntity: \(error)")
            }
        }
    }

    // MARK: - Private

    /// Deterministically decrypts the object's encrypted fields in place
    /// (e.g. rx_no, note). Replaces the old
    /// context.refresh(_, mergeChanges: false) refault, which did NOT reliably
    /// re-run awakeFromFetch and could surface ciphertext written by willSave
    /// in the same session.
    private func refreshDecrypted(_ object: NSManagedObject) {
        object.decryptEncryptedFieldsInPlace()
    }

    private func logRefillNos(op: String, results: [PillCountTransactionEntity]) {
        let rows = results.map { "txnId: \($0.txn_id), rxNo: \($0.rx_no ?? "-"), refillNo: \($0.refill_no ?? "-")" }
        StoreLogger.debug("📋 [TransactionDAO] \(op) refillNos — \(rows)")
    }

    /// Resolves the currently logged-in user from CoreData.
    /// Returns nil when no user ID is stored (e.g. during or after logout).
    private func currentUserEntity() -> UserEntity? {
        guard let userId = AppStorageManager.shared.userId, !userId.isEmpty else { return nil }
        return UserStore.shared.fetchByUserId(userId)
    }

    /// Same lookup as `fetchById`, but assumes the caller is already inside
    /// a `sync { }` block on this context — calling the public `fetchById`
    /// instead would re-enter `performAndWait`, which is safe but redundant.
    private func fetchByIdLocked(_ txnId: Int64) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        refreshDecrypted(result)
        return result
    }

    /// Same as `fetchByIdLocked(_:)`, but against an explicit context —
    /// assumes the caller is already inside that context's
    /// `performAndWait`, same convention as `fetchByIdLocked(_:)` itself.
    private func fetchByIdLocked(_ txnId: Int64, in context: NSManagedObjectContext) -> PillCountTransactionEntity? {
        let request: NSFetchRequest<PillCountTransactionEntity> = PillCountTransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "txn_id == %lld", txnId)
        request.fetchLimit = 1
        guard let result = try? context.fetch(request).first else { return nil }
        refreshDecrypted(result)
        return result
    }

    private func generateUniqueId() -> Int64 {
        let key = "txnTransactionIdCounter"
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
