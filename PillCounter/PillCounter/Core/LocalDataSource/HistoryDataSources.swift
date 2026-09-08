//
//  HistoryDataSources.swift
//  PillCounter
//
//  Narrow, role-based seams over the CoreData stores so the History and
//  Unsynced view models can be unit-tested with in-memory fakes instead of
//  the real CoreData stack. Each protocol declares ONLY the members its
//  consumers actually call — the concrete stores already implement them all,
//  so conformance is a one-line extension with no behaviour change.
//

import Foundation
import Combine
import CoreData

// MARK: - Batch store seam

protocol BatchDataSource: AnyObject {
    var transactionsDidChange: PassthroughSubject<Void, Never> { get }

    func fetchById(_ batchId: Int64) -> BatchCountEntity?
    func fetchByDateRange(startTs: Int64, endTs: Int64) -> [BatchCountEntity]
    /// Explicit-context variant — used by callers (e.g. DashboardViewModel's
    /// off-main queue load) that must keep every fetch in the pass on one
    /// background context instead of `viewContext`.
    func fetchByDateRange(startTs: Int64, endTs: Int64, in context: NSManagedObjectContext) -> [BatchCountEntity]
    func fetchByDateRangePage(startTs: Int64, endTs: Int64, limit: Int, offset: Int) -> [BatchCountEntity]
    func fetchAllPartial() -> [BatchCountEntity]
    /// Explicit-context variant — see `fetchByDateRange(startTs:endTs:in:)`.
    func fetchAllPartial(in context: NSManagedObjectContext) -> [BatchCountEntity]
    func fetchAllCompleted() -> [BatchCountEntity]
    func fetchCompletedUnsynced() -> [BatchCountEntity]
    func fetchAllPartialPage(limit: Int, offset: Int) -> [BatchCountEntity]
    func fetchAllCompletedPage(limit: Int, offset: Int) -> [BatchCountEntity]
    func fetchCompletedUnsyncedPage(limit: Int, offset: Int) -> [BatchCountEntity]
    func countCompletedUnsynced() -> Int
    func countByDateRange(startTs: Int64, endTs: Int64, status: CountStatus?) -> Int
    func countPendingInventory(facet: BatchStore.PendingBatchFacet) -> Int
    func fetchLastCreated() -> BatchCountEntity?
    func getTransactionCount(for batchId: Int64) -> Int
    func transactionCounts(for batchIds: [Int64]) -> [Int64: Int]
    /// Explicit-context variant — see `fetchByDateRange(startTs:endTs:in:)`.
    func transactionCounts(for batchIds: [Int64], in context: NSManagedObjectContext) -> [Int64: Int]
    func create(bucketId: String, requestId: String?) -> BatchCountEntity?
    func updateStatus(batchId: Int64, status: CountStatus, completion: (() -> Void)?)
    func updateNote(batchId: Int64, note: String)
    func softDelete(ids: Set<Int64>)
}

// MARK: - Transaction store seam

protocol TransactionDataSource: AnyObject {
    var transactionsDidChange: PassthroughSubject<Void, Never> { get }

    func fetchById(_ txnId: Int64) -> PillCountTransactionEntity?
    /// Explicit-context variant — see `BatchDataSource.fetchByDateRange(startTs:endTs:in:)`.
    func fetchById(_ txnId: Int64, in context: NSManagedObjectContext) -> PillCountTransactionEntity?
    func fetchByBatch(batchId: Int64) -> [PillCountTransactionEntity]
    func fetchByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64) -> [PillCountTransactionEntity]
    /// Explicit-context variant — see `BatchDataSource.fetchByDateRange(startTs:endTs:in:)`.
    func fetchByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64, in context: NSManagedObjectContext) -> [PillCountTransactionEntity]
    func fetchByTimeRangePage(for user: UserEntity, startTime: Int64, endTime: Int64, limit: Int, offset: Int) -> [PillCountTransactionEntity]
    func fetchPartial(for user: UserEntity, isDispense: Bool) -> [PillCountTransactionEntity]
    /// Explicit-context variant — see `BatchDataSource.fetchByDateRange(startTs:endTs:in:)`.
    func fetchPartial(for user: UserEntity, isDispense: Bool, in context: NSManagedObjectContext) -> [PillCountTransactionEntity]
    func fetchPartialPage(for user: UserEntity, isDispense: Bool, limit: Int, offset: Int) -> [PillCountTransactionEntity]
    func fetchPartialFromPms(for user: UserEntity, isDispense: Bool) -> [PillCountTransactionEntity]
    func fetchAll(for user: UserEntity) -> [PillCountTransactionEntity]
    func fetchAllPage(for user: UserEntity, limit: Int, offset: Int) -> [PillCountTransactionEntity]
    func fetchCompletedUnsynced() -> [PillCountTransactionEntity]
    func fetchCompletedUnsyncedPage(limit: Int, offset: Int) -> [PillCountTransactionEntity]
    func countCompletedUnsynced() -> Int
    func countByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64, status: CountStatus?) -> Int
    func countPendingDispense(for user: UserEntity, facet: TransactionStore.PendingDispenseFacet) -> Int
    func fetchLatest(for user: UserEntity) -> PillCountTransactionEntity?
    func fetchAllRxNos(for user: UserEntity) -> [String]
    func fetchByRxNo(_ rxNo: String, for user: UserEntity) -> [PillCountTransactionEntity]
    func fetchDeletedByRxNo(_ rxNo: String, for user: UserEntity) -> PillCountTransactionEntity?
    func countTransactions(for user: UserEntity, isDispense: Bool, status: CountStatus) -> Int
    func getWorkflowStep(txn: PillCountTransactionEntity) -> ControlledStep?
    func restoreDeleted(txnId: Int64)
    func updateStatus(txnId: Int64, status: CountStatus)
    func updateNote(txnId: Int64, note: String)
    func updateTargetCount(txnId: Int64, targetCount: Int32)
    func updateWorkflowStep(txnId: Int64, step: ControlledStep)
    func clearWorkflowStep(txnId: Int64)
    func updateGlovesDetected(txnId: Int64, detected: Bool)
    func updateHazardousTrayDetected(txnId: Int64, detected: Bool)
    func updateNdcVerified(txnId: Int64, verified: Bool)
    func updateFromHL7Edit(txnId: Int64, drugId: Int64, targetCount: Int32, priority: String?, refillNo: String?)
    func getBottleList(txnId: Int64) -> [BottleInfo]
    func setBottleList(txnId: Int64, _ bottles: [BottleInfo])
    @discardableResult
    func appendBottle(txnId: Int64, _ bottle: BottleInfo) -> [BottleInfo]
    @discardableResult
    func replaceLastBottle(txnId: Int64, _ bottle: BottleInfo) -> [BottleInfo]
    func create(
        for user: UserEntity, drugId: Int64?, isDispense: Bool, batchId: Int64,
        isFromPms: Bool, drugName: String?, targetCount: Int32,
        isControlled: Bool?, rxNo: String?, bucketId: String?, priority: String?,
        workFlowStep: String?, refillNo: String?
    ) -> PillCountTransactionEntity?
    func update(
        txnId: Int64, drugId: Int64?, isDispense: Bool, targetCount: Int32?,
        substituedDrugId: Int64?, isSubstitue: Bool
    )
    func softDelete(txnId: Int64)
}

// MARK: - StockTxn store seam

protocol StockTxnDataSource: AnyObject {
    var stockTxnsDidChange: PassthroughSubject<Void, Never> { get }

    @discardableResult
    func fetchOrCreate(batch: BatchCountEntity, drugId: Int64, bucketId: String?) -> StockTxnEntity
    func fetchById(_ stockTxnId: Int64) -> StockTxnEntity?
    func fetchByBatch(batchId: Int64) -> [StockTxnEntity]
    func fetchByBatchAndNdc(batchId: Int64, ndc: String) -> StockTxnEntity?
    func updateStatus(stockTxnId: Int64, status: CountStatus)
    func softDelete(stockTxnId: Int64)
}

// MARK: - BottleInfo store seam

protocol BottleInfoDataSource: AnyObject {
    var bottleInfosDidChange: PassthroughSubject<Void, Never> { get }

    @discardableResult
    func setSealedBottleQty(stockTxnId: Int64, bottleQty: Int32, lotNo: String?, expNo: String?) -> BottleInfoEntity?
    func sealedBottleQty(stockTxnId: Int64, lotNo: String?, expNo: String?) -> Int32
    @discardableResult
    func addOpenedBottle(
        stockTxnId: Int64, looseQty: Int32, lotNo: String?, expNo: String?, serialNo: String?,
        images: [BottleImageRecord]
    ) -> BottleInfoEntity?
    func fetchOpenedRow(stockTxnId: Int64, lotNo: String?, expNo: String?) -> BottleInfoEntity?
    func appendImages(bottleId: Int64, images: [BottleImageRecord])
    func updateOpenedBottleLooseQty(bottleId: Int64, looseQty: Int32)
    func fetchById(_ bottleId: Int64) -> BottleInfoEntity?
    func fetchByStockTxn(stockTxnId: Int64) -> [BottleInfoEntity]
    func fetchByBatch(batchId: Int64) -> [BottleInfoEntity]
    func setAbsolute(bottleId: Int64, bottleQty: Int32?, looseQty: Int32?)
    func softDelete(bottleId: Int64)
}

// MARK: - Transaction-detail store seam

protocol TransactionDetailDataSource: AnyObject {
    func totalCountForStep(txnId: Int64, step: ControlledStep) -> Int32
    func totalCountsForSteps(txnIds: [Int64], step: ControlledStep) -> [Int64: Int32]
    /// Explicit-context variant — see `BatchDataSource.fetchByDateRange(startTs:endTs:in:)`.
    func totalCountsForSteps(txnIds: [Int64], step: ControlledStep, in context: NSManagedObjectContext) -> [Int64: Int32]
    func totalCount(txnId: Int64) -> Int
    @discardableResult
    func add(txnId: Int64, pillCount: Int32, imagePath: String?, type: String?, isManual: Bool) -> PillCountTransactionDetailsEntity?
    func addOrReplaceVial(txnId: Int64, imagePath: String?)
    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity]
    func fetchAll(txnId: Int64) -> [PillCountTransactionDetailsEntity]
    /// Explicit-context variant — see `BatchDataSource.fetchByDateRange(startTs:endTs:in:)`.
    func fetchAll(txnId: Int64, in context: NSManagedObjectContext) -> [PillCountTransactionDetailsEntity]
    func lastCompletedStep(txnId: Int64) -> ControlledStep?
    func softDeleteForStep(txnId: Int64, step: ControlledStep)
    func update(detailId: Int64, block: (PillCountTransactionDetailsEntity) -> Void)
    func sumPillCount(detailIds: [Int64]) -> Int
    @discardableResult
    func hardDeleteAll(txnId: Int64) -> (success: Bool, imagePaths: [String])
}

// MARK: - Drug-catalog store seam

protocol DrugCatalogDataSource: AnyObject {
    func fetchByGtin(_ gtin: String) -> DrugMasterEntity?
    func fetchByNdc(_ ndc: String) -> DrugMasterEntity?
    func fetchByNdcDigitsOnly(_ ndc: String) -> DrugMasterEntity?
    func saveManual(
        ndc: String,
        gtin: String,
        drugId: Int64,
        drugName: String,
        drugType: String?,
        strength: String?,
        dosageForm: String?,
        packageQty: Int32,
        isHazardous: Bool?
    )
    func update(
        drugId: Int64,
        drugName: String?,
        ndc: String?,
        gtin: String?,
        drugType: String?,
        strength: String?,
        dosageForm: String?,
        packageQty: Int32?,
        isHazardous: Bool?
    )
    @discardableResult
    func upsertFromApi(
        ndc: String,
        drugId: Int64,
        drug: NdcDrug,
        gtin: String
    ) -> DrugMasterEntity?
}

// MARK: - Default-argument bridges
//
// Protocols can't declare default parameter values, but the concrete stores do.
// These extensions re-expose the convenient short forms so call sites that
// relied on defaults keep compiling against the protocol type.

extension BatchDataSource {
    func create(bucketId: String) -> BatchCountEntity? {
        create(bucketId: bucketId, requestId: nil)
    }
    func updateStatus(batchId: Int64, status: CountStatus) {
        updateStatus(batchId: batchId, status: status, completion: nil)
    }
}

extension TransactionDataSource {
    /// Convenience matching the store's defaulted `create` so call sites keep
    /// their short forms when working against the protocol type.
    func create(
        for user: UserEntity, drugId: Int64?, isDispense: Bool, batchId: Int64 = 0,
        isFromPms: Bool = false, drugName: String? = nil,
        targetCount: Int32 = 0, isControlled: Bool? = nil, rxNo: String? = nil,
        bucketId: String? = nil, priority: String? = nil, workFlowStep: String? = nil
    ) -> PillCountTransactionEntity {
        create(
            for: user, drugId: drugId, isDispense: isDispense, batchId: batchId,
            isFromPms: isFromPms, drugName: drugName,
            targetCount: targetCount, isControlled: isControlled, rxNo: rxNo,
            bucketId: bucketId, priority: priority, workFlowStep: workFlowStep
        )
    }

    func update(
        txnId: Int64, drugId: Int64?, isDispense: Bool, targetCount: Int32?,
        substituedDrugId: Int64? = nil, isSubstitue: Bool = false
    ) {
        update(
            txnId: txnId, drugId: drugId, isDispense: isDispense, targetCount: targetCount,
            substituedDrugId: substituedDrugId,
            isSubstitue: isSubstitue
        )
    }
}

extension TransactionDetailDataSource {
    func add(txnId: Int64, pillCount: Int32, imagePath: String? = nil, type: String? = nil, isManual: Bool = false) {
        add(txnId: txnId, pillCount: pillCount, imagePath: imagePath, type: type, isManual: isManual)
    }
}

extension DrugCatalogDataSource {
    func saveManual(
        ndc: String, gtin: String = "", drugId: Int64, drugName: String,
        drugType: String? = nil, strength: String? = nil, dosageForm: String? = nil,
        packageQty: Int32 = 0, isHazardous: Bool? = nil
    ) {
        saveManual(
            ndc: ndc, gtin: gtin, drugId: drugId, drugName: drugName,
            drugType: drugType, strength: strength, dosageForm: dosageForm,
            packageQty: packageQty, isHazardous: isHazardous
        )
    }
    func update(
        drugId: Int64, drugName: String? = nil, ndc: String? = nil, gtin: String? = nil,
        drugType: String? = nil, strength: String? = nil, dosageForm: String? = nil,
        packageQty: Int32? = nil, isHazardous: Bool? = nil
    ) {
        update(
            drugId: drugId, drugName: drugName, ndc: ndc, gtin: gtin,
            drugType: drugType, strength: strength, dosageForm: dosageForm,
            packageQty: packageQty, isHazardous: isHazardous
        )
    }
    @discardableResult
    func upsertFromApi(
        ndc: String, drugId: Int64, drug: NdcDrug, gtin: String = ""
    ) -> DrugMasterEntity? {
        upsertFromApi(ndc: ndc, drugId: drugId, drug: drug, gtin: gtin)
    }
}

// MARK: - User store seam

protocol UserDataSource: AnyObject {
    func fetchByUserId(_ userId: String) -> UserEntity?
    func fetchTransactionsByDateRange(
        for user: UserEntity,
        startDateTs: Int64,
        endDateTs: Int64
    ) -> [PillCountTransactionEntity]
    func save(from response: UserResponse)
    func update(userId: String, field: UserStore.UserField, value: Any?)
}

// MARK: - Current-user id seam (subset of AppStorageManager / TokenStore)

protocol UserIdProviding: AnyObject {
    var userId: String? { get }
}

// MARK: - Conformances (no behaviour change — methods already exist)

extension BatchStore: BatchDataSource {}
extension StockTxnStore: StockTxnDataSource {}
extension BottleInfoStore: BottleInfoDataSource {}
extension TransactionStore: TransactionDataSource {}
extension TransactionDetailStore: TransactionDetailDataSource {}
extension UserStore: UserDataSource {}
extension AppStorageManager: UserIdProviding {}
extension DrugCatalogStore: DrugCatalogDataSource {}
