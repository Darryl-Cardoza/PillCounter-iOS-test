//
//  PIllScanViewModel+Controlled.swift
//  PillCounter
//
//  Created by Bhushan Patil on 17/03/26.
//
import SwiftUI
import Hl7Core

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

    /// Open-ended step — the user pours ALL pills and there is no meaningful
    /// target to compare against (parent / container-initiate count). The UI
    /// hides the target progress bar and the button is always an explicit "Done"
    /// (completion is the user's decision, not a count == target check).
    var isOpenEndedCountStep: Bool {
        currentControlledStep == .containerInitiate ||
        currentControlledStep == .containerPending
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
            if currentTransaction?.is_dispense == true {
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

        // Fetch active step
        guard let lastStep = transactionDAO.getWorkflowStep(txn: txn) else {
            if let type = txn.drug?.drug_type, !type.trimmingCharacters(in: .whitespaces).isEmpty {
                currentControlledStep = .containerInitiate
            } else {
                currentControlledStep = .targetVerification
            }
            updateControlledTargetCount()
            return
        }
        let activeSteps = PillCountingStepResolver.getActiveSteps(txn: txn)

        // If the stored step is no longer in the active steps (e.g. double-count or
        // back-count step was removed because settings changed), advance to vial.
        if !activeSteps.contains(lastStep) {
            currentControlledStep = .vial
            transactionDAO.updateWorkflowStep(txnId: txn.txn_id, step: .vial)
        } else {
            currentControlledStep = lastStep
        }
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
        transactionDAO.updateWorkflowStep(txnId: txn.txn_id, step: next)
        updateControlledTargetCount()
    }
    
    //Update Drug Data
    func updateSubstitutedDrug(
        txnId: Int64,
        rawValue: String,
        isDispense: Bool,
        image: UIImage?
    ) async {
        
        let decoded = decoder.decode(rawValue)
        let gtin = decoded.gtin ?? ""

        guard !gtin.isEmpty else { return }

        // Resolve drug info — prefer API response, fall back to local drug master
        // (local path is taken when getControlledDrugInfo resolved from cache and
        // never populated ndcComparisonResponse).
        let actualDrugId: Int64
        if let scannedNdc = ndcComparisonResponse?.data?.scannedNdc,
           let apiNdc = scannedNdc.drugCode, !apiNdc.isEmpty {
            let newDrugId = generateUniqueDrugId()
            drugMasterDAO.upsertFromApi(
                ndc:    apiNdc,
                drugId: newDrugId,
                drug:   scannedNdc,
                gtin:   gtin
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
            isDispense: isDispense,
            targetCount: nil,
            barcodeImagePath: savedPath,
            substituedDrugId: isNdcEquivalent ? nil : actualDrugId,
            isSubstitue: isNdcEquivalent
        )

        isDrugFound = true
    }
}
