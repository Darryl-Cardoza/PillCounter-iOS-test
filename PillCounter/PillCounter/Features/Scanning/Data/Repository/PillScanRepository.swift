//
//  PillScanRepository.swift
//  PillCounter
//

import UIKit
import ComposeApp

protocol PillScanRepository {

    // MARK: - Drug
    func resolveDrug(ndc: String, fallbackName: String?) async throws -> DrugMasterEntity
    func resolveDrugName(for ndc: String) async -> String?
    func saveManualDrug(ndc: String, drugName: String) -> DrugMasterEntity

    // MARK: - Transaction
    func createTransaction(
        drugId: Int64,
        countType: CountType,
        barcodeImage: UIImage?,
        isFromPms: Bool,
        isControlled: Bool?,
        targetCount: Int32?,
        drugName: String?,
        batchId: Int64?,
        expirationDate: String?,
        lotNumber: String?,
        rxNo: String?,
        bucketId: String?
    ) async -> PillCountTransactionEntity?

    func updateTransaction(
        txnId: Int64,
        drugId: Int64?,
        countType: CountType,
        targetCount: Int32?,
        barcodeImagePath: String?
    )

    func updateTargetCount(txnId: Int64, targetCount: Int32)
    func updateNote(txnId: Int64, note: String)
    func updateNdcVerified(txnId: Int64, verified: Bool)
    func updateSubstitutedDrug(txnId: Int64, drugId: Int64, countType: CountType, barcodeImagePath: String)
    func softDeleteTransaction(txnId: Int64)
    func fetchTransaction(txnId: Int64) -> PillCountTransactionEntity?

    // MARK: - Transaction Details
    func addTransactionDetail(txnId: Int64, pillCount: Int32, imagePath: String?, type: String?, isManual: Bool)
    func addOrReplaceVialDetail(txnId: Int64, imagePath: String?)
    func getTransactionDetails(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity]
    func getTotalCountForStep(txnId: Int64, step: ControlledStep) -> Int32
    func getLastCompletedStep(txnId: Int64) -> ControlledStep?
    func softDeleteDetail(detailId: Int64)
    func softDeleteDetailsForStep(txnId: Int64, step: ControlledStep)

    // MARK: - NDC Equivalence
    func checkNdcEquivalence(targetNdc: String, scannedNdc: String) async throws -> NdcComparisonResponse

    // MARK: - Stock
    func resolveOrCreateDrugForStock(ndc: String, gtin: String, drugName: String, quantity: Int32) async -> DrugMasterEntity?
    func fetchTransactionsByBatch(batchId: Int64) -> [PillCountTransactionEntity]
    func updateCounts(txnId: Int64, bottleQty: Int32?, looseQty: Int32?)
    func createBatch(bucketId: String, requestId: String?) -> BatchCountEntity?
}

enum PillScanRepositoryError: Error {
    case userNotFound
    case drugNotFound
    case imageSaveFailed
}
