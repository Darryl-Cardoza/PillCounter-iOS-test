//
//  PillScanRepositoryImpl.swift
//  PillCounter
//

import UIKit
import ComposeApp

final class PillScanRepositoryImpl: PillScanRepository {

    // MARK: - DAOs
    private let drugDAO = DrugMasterDAO.shared
    private let txnDAO = TransactionDAO.shared
    private let detailDAO = TransactionDetailDAO.shared
    private let userDAO = UserDAO.shared

    // MARK: - Remote
    private let controlledRepo = ControlledRepository.shared
    private let userRepo = UserRepository.shared

    // MARK: - Singleton
    static let shared = PillScanRepositoryImpl()
    private init() {}

    // MARK: - Drug

    func resolveDrug(ndc: String, fallbackName: String?) async throws -> DrugMasterEntity {
        // 1. Local first
        if let local = drugDAO.fetchByNdc(ndc) {
            return local
        }

        // 2. Remote
        let result = try await userRepo.getDrug(ndc: ndc)

        if result.isSuccess ?? false, let data = result.data {
            let drugId = generateDrugId()
            drugDAO.fetchOrCreate(ndc: ndc, drugId: drugId)
            drugDAO.update(drugId: drugId, drugName: data.genericName, ndc: ndc)
        } else if let fallback = fallbackName {
            let drugId = generateDrugId()
            drugDAO.fetchOrCreate(ndc: ndc, drugId: drugId)
            drugDAO.update(drugId: drugId, drugName: fallback, ndc: ndc)
        } else {
            throw PillScanRepositoryError.drugNotFound
        }

        guard let saved = drugDAO.fetchByNdc(ndc) else {
            throw PillScanRepositoryError.drugNotFound
        }
        return saved
    }

    func resolveDrugName(for ndc: String) async -> String? {
        guard !ndc.isEmpty else { return nil }

        // 1. Local first
        if let local = drugDAO.fetchByNdc(ndc),
           let name = local.drug_name, !name.isEmpty {
            return name
        }

        // 2. Controlled API fallback
        let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
        do {
            let response = try await controlledRepo.getControlledDrugInfo(ndcValidationRequest: request)
            guard let data = response.data else { return nil }

            let resolvedName = data.scannedNdc?.lookupName ?? ""
            let drugId = generateDrugId()
            drugDAO.fetchOrCreate(ndc: ndc, drugId: drugId)
            drugDAO.update(
                drugId: drugId,
                drugName: resolvedName,
                ndc: ndc,
                drugType: data.scannedNdc?.deaSchedule,
                packageQty: data.scannedNdc?.safeQuantity ?? 0
            )
            return resolvedName.isEmpty ? nil : resolvedName
        } catch {
            return nil
        }
    }

    func saveManualDrug(ndc: String, drugName: String) -> DrugMasterEntity {
        if let existing = drugDAO.fetchByNdc(ndc) { return existing }
        let drugId = generateDrugId()
        let entity = drugDAO.fetchOrCreate(ndc: ndc, drugId: drugId)
        drugDAO.update(drugId: drugId, drugName: drugName, ndc: ndc)
        return entity
    }

    // MARK: - Transaction

    func createTransaction(
        drugId: Int64,
        countType: CountType,
        barcodeImage: UIImage? = nil,
        isFromPms: Bool = false,
        isControlled: Bool? = nil,
        targetCount: Int32? = nil,
        drugName: String? = nil,
        batchId: Int64? = nil,
        expirationDate: String? = nil,
        lotNumber: String? = nil,
        rxNo: String? = nil,
        bucketId: String? = nil
    ) async -> PillCountTransactionEntity? {
        guard let user = userDAO.fetchByUserId(AppStorageManager.shared.userId ?? "") else {
            return nil
        }

        var savedPath = ""
        if let img = barcodeImage, let path = PhotoFileManager.shared.saveImage(img) {
            savedPath = path
        }

        return txnDAO.create(
            for: user,
            drugId: drugId,
            countType: countType,
            batchId: batchId ?? 0,
            barcodeImagePath: savedPath,
            isFromPms: isFromPms,
            drugName: drugName,
            targetCount: targetCount ?? 0,
            isControlled: isControlled,
            expirationDate: expirationDate,
            lotNumber: lotNumber,
            rxNo: rxNo,
            bucketId: bucketId
        )
    }

    func updateTransaction(
        txnId: Int64,
        drugId: Int64?,
        countType: CountType,
        targetCount: Int32?,
        barcodeImagePath: String?
    ) {
        txnDAO.update(
            txnId: txnId,
            drugId: drugId,
            countType: countType,
            targetCount: targetCount,
            barcodeImagePath: barcodeImagePath
        )
    }

    func updateTargetCount(txnId: Int64, targetCount: Int32) {
        txnDAO.updateTargetCount(txnId: txnId, targetCount: targetCount)
    }

    func updateNote(txnId: Int64, note: String) {
        txnDAO.updateNote(txnId: txnId, note: note)
    }

    func updateNdcVerified(txnId: Int64, verified: Bool) {
        txnDAO.updateNdcVerified(txnId: txnId, verified: verified)
    }

    func updateSubstitutedDrug(txnId: Int64, drugId: Int64, countType: CountType, barcodeImagePath: String) {
        txnDAO.update(
            txnId: txnId,
            drugId: drugId,
            countType: countType,
            targetCount: nil,
            barcodeImagePath: barcodeImagePath.isEmpty ? nil : barcodeImagePath
        )
    }

    func softDeleteTransaction(txnId: Int64) {
        txnDAO.softDelete(txnId: txnId)
    }

    func fetchTransaction(txnId: Int64) -> PillCountTransactionEntity? {
        txnDAO.fetchById(txnId)
    }

    // MARK: - Transaction Details

    func addTransactionDetail(txnId: Int64, pillCount: Int32, imagePath: String?, type: String?, isManual: Bool) {
        detailDAO.add(txnId: txnId, pillCount: pillCount, imagePath: imagePath, type: type, isManual: isManual)
    }

    func addOrReplaceVialDetail(txnId: Int64, imagePath: String?) {
        detailDAO.addOrReplaceVial(txnId: txnId, imagePath: imagePath)
    }

    func getTransactionDetails(txnId: Int64, step: ControlledStep) -> [PillCountTransactionDetailsEntity] {
        detailDAO.fetchForStep(txnId: txnId, step: step)
    }

    func getTotalCountForStep(txnId: Int64, step: ControlledStep) -> Int32 {
        detailDAO.totalCountForStep(txnId: txnId, step: step)
    }

    func getLastCompletedStep(txnId: Int64) -> ControlledStep? {
        detailDAO.lastCompletedStep(txnId: txnId)
    }

    func softDeleteDetail(detailId: Int64) {
        detailDAO.softDelete(detailId: detailId)
    }

    func softDeleteDetailsForStep(txnId: Int64, step: ControlledStep) {
        detailDAO.softDeleteForStep(txnId: txnId, step: step)
    }

    // MARK: - NDC Equivalence

    func checkNdcEquivalence(targetNdc: String, scannedNdc: String) async throws -> NdcComparisonResponse {
        let request = NdcValidationRequest(targetNdc: targetNdc, scannedNdc: scannedNdc)
        return try await controlledRepo.getControlledDrugInfo(ndcValidationRequest: request)
    }

    // MARK: - Stock

    func resolveOrCreateDrugForStock(ndc: String, gtin: String, drugName: String, quantity: Int32) async -> DrugMasterEntity? {
        // 1. By NDC
        if let existing = drugDAO.fetchByNdc(ndc) {
            if (existing.gtin ?? "").isEmpty, !gtin.isEmpty {
                existing.gtin = gtin
                CoreDataManager.shared.save(context: CoreDataManager.shared.context)
            }
            return existing
        }

        // 2. By GTIN
        if !gtin.isEmpty, let existing = drugDAO.fetchByGtin(gtin) {
            return existing
        }

        // 3. API fallback
        let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
        do {
            let response = try await controlledRepo.getControlledDrugInfo(ndcValidationRequest: request)
            if let lookup = response.data?.scannedNdc?.lookupName, !lookup.isEmpty {
                let newId = generateDrugId()
                drugDAO.fetchOrCreate(ndc: response.data?.scannedNdc?.packageNdc ?? ndc, drugId: newId)
                drugDAO.update(
                    drugId: newId,
                    drugName: lookup,
                    ndc: response.data?.scannedNdc?.packageNdc ?? ndc,
                    gtin: gtin.isEmpty ? nil : gtin,
                    drugType: response.data?.scannedNdc?.deaSchedule,
                    packageQty: response.data?.scannedNdc?.safeQuantity ?? quantity
                )
                return drugDAO.fetchById(newId)
            }
        } catch {}

        // 4. Local fallback
        let newId = generateDrugId()
        drugDAO.fetchOrCreate(ndc: ndc, drugId: newId)
        drugDAO.update(drugId: newId, drugName: drugName, ndc: ndc, gtin: gtin.isEmpty ? nil : gtin, packageQty: quantity)
        return drugDAO.fetchById(newId)
    }

    func fetchTransactionsByBatch(batchId: Int64) -> [PillCountTransactionEntity] {
        txnDAO.fetchByBatch(batchId: batchId)
    }

    func updateCounts(txnId: Int64, bottleQty: Int32?, looseQty: Int32?) {
        txnDAO.updateCounts(txnId: txnId, bottleQty: bottleQty, looseQty: looseQty)
    }

    func createBatch(bucketId: String, requestId: String?) -> BatchCountEntity? {
        BatchDAO.shared.create(bucketId: bucketId, requestId: requestId)
    }

    // MARK: - Private

    private func generateDrugId() -> Int64 {
        let key = AppStorageManager.AppStorageKeys.drugIdCounter
        let current = UserDefaults.standard.integer(forKey: key)
        let newId = current + 1
        UserDefaults.standard.set(newId, forKey: key)
        return Int64(newId)
    }
}
