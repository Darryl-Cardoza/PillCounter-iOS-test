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

// MARK: - Batch store seam

protocol BatchDataSource: AnyObject {
    var transactionsDidChange: PassthroughSubject<Void, Never> { get }

    func fetchById(_ batchId: Int64) -> BatchCountEntity?
    func fetchByDateRange(startTs: Int64, endTs: Int64) -> [BatchCountEntity]
    func fetchAllPartial() -> [BatchCountEntity]
    func fetchAllCompleted() -> [BatchCountEntity]
    func fetchCompletedUnsynced() -> [BatchCountEntity]
    func fetchLastCreated() -> BatchCountEntity?
    func getTransactionCount(for batchId: Int64) -> Int
    func create(bucketId: String, requestId: String?) -> BatchCountEntity?
    func updateStatus(batchId: Int64, status: CountStatus, completion: (() -> Void)?)
    func updateNote(batchId: Int64, note: String)
    func softDelete(ids: Set<Int64>)
}

// MARK: - Transaction store seam

protocol TransactionDataSource: AnyObject {
    var transactionsDidChange: PassthroughSubject<Void, Never> { get }

    func fetchById(_ txnId: Int64) -> PillCountTransactionEntity?
    func fetchByBatch(batchId: Int64) -> [PillCountTransactionEntity]
    func fetchByTimeRange(for user: UserEntity, startTime: Int64, endTime: Int64) -> [PillCountTransactionEntity]
    func fetchPartial(for user: UserEntity, countType: CountType) -> [PillCountTransactionEntity]
    func fetchPartialFromPms(for user: UserEntity, countType: CountType) -> [PillCountTransactionEntity]
    func fetchAll(for user: UserEntity) -> [PillCountTransactionEntity]
    func fetchCompletedUnsynced() -> [PillCountTransactionEntity]
    func fetchLatest(for user: UserEntity) -> PillCountTransactionEntity?
    func fetchAllRxNos(for user: UserEntity) -> [String]
    func fetchByRxNo(_ rxNo: String, for user: UserEntity) -> [PillCountTransactionEntity]
    func fetchDeletedByRxNo(_ rxNo: String, for user: UserEntity) -> PillCountTransactionEntity?
    func countTransactions(for user: UserEntity, countType: CountType, status: CountStatus) -> Int
    func getWorkflowStep(txn: PillCountTransactionEntity) -> ControlledStep?
    func restoreDeleted(txnId: Int64)
    func updateStatus(txnId: Int64, status: CountStatus)
    func updateCounts(txnId: Int64, bottleQty: Int32?, looseQty: Int32?, openBottleQty: Int32?)
    func setAbsoluteCounts(txnId: Int64, bottleQty: Int32?, looseQty: Int32?, openBottleQty: Int32?)
    func updateNote(txnId: Int64, note: String)
    func updateTargetCount(txnId: Int64, targetCount: Int32)
    func updateWorkflowStep(txnId: Int64, step: ControlledStep)
    func updateGlovesDetected(txnId: Int64, detected: Bool)
    func updateHazardousTrayDetected(txnId: Int64, detected: Bool)
    func updateNdcVerified(txnId: Int64, verified: Bool)
    func updateFromHL7Edit(txnId: Int64, drugId: Int64, targetCount: Int32, priority: String?)
    func create(
        for user: UserEntity, drugId: Int64?, countType: CountType, batchId: Int64,
        barcodeImagePath: String, isFromPms: Bool, drugName: String?, targetCount: Int32,
        isControlled: Bool?, expirationDate: String?, lotNumber: String?, serialNumber: String?,
        rxNo: String?, bucketId: String?, priority: String?, workFlowStep: String?
    ) -> PillCountTransactionEntity
    func update(
        txnId: Int64, drugId: Int64?, countType: CountType, targetCount: Int32?,
        barcodeImagePath: String?, substituedDrugId: Int64?, isSubstitue: Bool
    )
    func softDelete(txnId: Int64)
}

// MARK: - Transaction-detail store seam

protocol TransactionDetailDataSource: AnyObject {
    func totalCountForStep(txnId: Int64, step: ControlledStep) -> Int32
    func totalCount(txnId: Int64) -> Int
    func add(txnId: Int64, pillCount: Int32, imagePath: String?, type: String?, isManual: Bool)
    func addOrReplaceVial(txnId: Int64, imagePath: String?)
    func fetchForStep(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity]
    func lastCompletedStep(txnId: Int64) -> ControlledStep?
    func softDeleteForStep(txnId: Int64, step: ControlledStep)
    func update(detailId: Int64, block: (PillCountTransactionDetailsEntity) -> Void)
}

// MARK: - Drug-catalog store seam

protocol DrugCatalogDataSource: AnyObject {
    func fetchByGtin(_ gtin: String) -> DrugMasterEntity?
    func fetchByNdc(_ ndc: String) -> DrugMasterEntity?
    func saveManual(
        ndc: String,
        gtin: String,
        drugId: Int64,
        drugName: String,
        drugType: String?,
        packageQty: Int32,
        isHazardous: Bool?
    )
    func update(
        drugId: Int64,
        drugName: String?,
        ndc: String?,
        gtin: String?,
        drugType: String?,
        packageQty: Int32?,
        isHazardous: Bool?
    )
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
    func updateCounts(txnId: Int64, bottleQty: Int32? = nil, looseQty: Int32? = nil, openBottleQty: Int32? = nil) {
        updateCounts(txnId: txnId, bottleQty: bottleQty, looseQty: looseQty, openBottleQty: openBottleQty)
    }
    func setAbsoluteCounts(txnId: Int64, bottleQty: Int32? = nil, looseQty: Int32? = nil, openBottleQty: Int32? = nil) {
        setAbsoluteCounts(txnId: txnId, bottleQty: bottleQty, looseQty: looseQty, openBottleQty: openBottleQty)
    }

    /// Convenience matching the store's defaulted `create` so call sites keep
    /// their short forms when working against the protocol type.
    func create(
        for user: UserEntity, drugId: Int64?, countType: CountType, batchId: Int64 = 0,
        barcodeImagePath: String = "", isFromPms: Bool = false, drugName: String? = nil,
        targetCount: Int32 = 0, isControlled: Bool? = nil, expirationDate: String? = nil,
        lotNumber: String? = nil, serialNumber: String? = nil, rxNo: String? = nil,
        bucketId: String? = nil, priority: String? = nil, workFlowStep: String? = nil
    ) -> PillCountTransactionEntity {
        create(
            for: user, drugId: drugId, countType: countType, batchId: batchId,
            barcodeImagePath: barcodeImagePath, isFromPms: isFromPms, drugName: drugName,
            targetCount: targetCount, isControlled: isControlled, expirationDate: expirationDate,
            lotNumber: lotNumber, serialNumber: serialNumber, rxNo: rxNo, bucketId: bucketId,
            priority: priority, workFlowStep: workFlowStep
        )
    }

    func update(
        txnId: Int64, drugId: Int64?, countType: CountType, targetCount: Int32?,
        barcodeImagePath: String?, substituedDrugId: Int64? = nil, isSubstitue: Bool = false
    ) {
        update(
            txnId: txnId, drugId: drugId, countType: countType, targetCount: targetCount,
            barcodeImagePath: barcodeImagePath, substituedDrugId: substituedDrugId,
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
        drugType: String? = nil, packageQty: Int32 = 0, isHazardous: Bool? = nil
    ) {
        saveManual(
            ndc: ndc, gtin: gtin, drugId: drugId, drugName: drugName,
            drugType: drugType, packageQty: packageQty, isHazardous: isHazardous
        )
    }
    func update(
        drugId: Int64, drugName: String? = nil, ndc: String? = nil, gtin: String? = nil,
        drugType: String? = nil, packageQty: Int32? = nil, isHazardous: Bool? = nil
    ) {
        update(
            drugId: drugId, drugName: drugName, ndc: ndc, gtin: gtin,
            drugType: drugType, packageQty: packageQty, isHazardous: isHazardous
        )
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
extension TransactionStore: TransactionDataSource {}
extension TransactionDetailStore: TransactionDetailDataSource {}
extension UserStore: UserDataSource {}
extension AppStorageManager: UserIdProviding {}
extension DrugCatalogStore: DrugCatalogDataSource {}
