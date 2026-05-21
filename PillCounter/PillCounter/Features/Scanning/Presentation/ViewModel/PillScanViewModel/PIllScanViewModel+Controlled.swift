//
//  PIllScanViewModel+Controlled.swift
//  PillCounter
//
//  Created by Bhushan Patil on 17/03/26.
//
import SwiftUI
import ComposeApp

extension PillScanViewModel{
    
    var activeTransaction: PillCountTransactionEntity? {
        if let currentTransaction {
            return currentTransaction
        }

        if let selectedTransaction {
            return selectedTransaction
        }

        return nil
    }
    
    
    // MARK: - Update Target Count
    func updateControlledTargetCount() {

        guard let txn = currentTransaction else { return }

        let target = Int(txn.target_count)

        let txnId = txn.txn_id

        switch currentControlledStep {
            
        case .scan:
            currentControlledTargetCount = 0
            
        case .containerInitiate:
            currentControlledTargetCount = 0

        case .targetVerification,
             .targetReverification,
             .vial:
            currentControlledTargetCount = target

        case .containerPending:
            let containerCount =
            transactionDetailDAO.totalCountForStep(
                txnId: txnId,
                step: .containerInitiate
            )

            currentControlledTargetCount =
            max(Int(containerCount) - target, 0)
        }
    }
    
    // Check is this step can be completed or not
    func canCompleteStep(stepTotal: Int) -> Bool {

        guard let txn = currentTransaction else { return false }

        let target = Int(txn.target_count)

        switch currentControlledStep {

        case .containerInitiate:
            return stepTotal >= target
            
        case .targetVerification:
            if currentTransaction?.count_type == CountType.FIXED.rawValue {
                return stepTotal == target
            } else {
                return true
            }
            
        case .targetReverification:
            return stepTotal == target

        case .containerPending:
            let containerCount =
            transactionDetailDAO.totalCountForStep(
                txnId: txn.txn_id,
                step: .containerInitiate
            )
            let expected = Int(containerCount) - target
            return stepTotal == expected
            
        case .vial:
            return stepTotal == 0

        default:
            return false
        }
    }
    
    
    func isContainerPendingZero() -> Bool {
        guard let txn = currentTransaction else { return false }

        let target = Int(txn.target_count)

        let containerCount =
        transactionDetailDAO.totalCountForStep(
            txnId: txn.txn_id,
            step: .containerInitiate
        )

        let expected = Int(containerCount) - target

        return currentControlledStep == .containerPending && expected == 0
    }
    
    
    func getTotalCuntForCurrentStep() -> Int32 {
        guard let txnId = currentTransaction?.txn_id else {
            return 0
        }

        let total = transactionDetailDAO.totalCountForStep(
            txnId: txnId,
            step: currentControlledStep
        )

        return total
    }
    
    
    // Get Last saved Controlled Step
    func getLastSavedControlledStep() -> ControlledStep? {
        guard let txn = selectedTransaction else { return nil }
        return transactionDetailDAO.lastCompletedStep(txnId: txn.txn_id)
    }
    
    
    // Get which Controlled step is now
    func getControlledStep(pillCountTxn: PillCountTransactionEntity? = nil) {
        guard let txn = pillCountTxn else {
            return
        }

        // Fetch last saved step
        guard let lastStep = transactionDetailDAO.lastCompletedStep(txnId: txn.txn_id) else {
            if let type = txn.drug?.drug_type, !type.trimmingCharacters(in: .whitespaces).isEmpty {
                currentControlledStep = .containerInitiate
            } else {
                currentControlledStep = .targetVerification
            }
            updateControlledTargetCount()
            return
        }
        print("Last controlled step \(lastStep)")
        currentControlledStep = lastStep
        updateControlledTargetCount()
    }
    
    
    // When step completed
    func handleStepCompletion() {
        guard let txn = currentTransaction else {
            return
        }
        let steps = PillCountingStepResolver.getActiveSteps(txn: txn)

        guard let currentIndex = steps.firstIndex(of: currentControlledStep) else {
            return
        }
        let next = steps[currentIndex + 1]
        currentControlledStep = next
        updateControlledTargetCount()
    }
    
    //Update Drug Data
    func updateSubstitutedDrug(
        txnId: Int64,
        rawValue: String,
        countType: CountType,
        image: UIImage?
    ) async {
        
        let decoded = decoder.decode(rawValue)
        let gtin = decoded.gtin ?? ""

        guard !gtin.isEmpty else { return }

        // Resolve drug info — prefer API response, fall back to local drug master
        // (local path is taken when getControlledDrugInfo resolved from cache and
        // never populated ndcComparisonResponse).
        let actualDrugId: Int64
        if let apiNdc = ndcComparisonResponse?.data?.scannedNdc?.packageNdc, !apiNdc.isEmpty {
            let newDrugId = generateUniqueDrugId()
            drugMasterDAO.saveManual(
                ndc: apiNdc,
                gtin: gtin,
                drugId: newDrugId,
                drugName: ndcComparisonResponse?.data?.scannedNdc?.lookupName ?? "",
                drugType: ndcComparisonResponse?.data?.scannedNdc?.deaSchedule ?? "",
                packageQty: ndcComparisonResponse?.data?.scannedNdc?.safeQuantity ?? 0
            )
            actualDrugId = drugMasterDAO.fetchByNdc(apiNdc)?.drug_id ?? newDrugId
        } else if let localDrug = drugMasterDAO.fetchByGtin(gtin), let localNdc = localDrug.ndc, !localNdc.isEmpty {
            // Already in drug master from a previous API call — reuse the existing record.
            actualDrugId = localDrug.drug_id
        } else {
            return
        }
        
        var savedPath = ""

        if let img = image {
            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            }
        }

        transactionDAO.update(
            txnId: txnId,
            drugId: isNdcEquivalent ? actualDrugId : nil,
            countType: countType,
            targetCount: nil,
            barcodeImagePath: savedPath,
            substituedDrugId: isNdcEquivalent ? nil : actualDrugId,
            isSubstitue: isNdcEquivalent
        )

        isDrugFound = true
    }
}
