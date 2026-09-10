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
            currentControlledTargetCount = containerPendingTarget()
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
            return stepTotal == containerPendingTarget()
            
        case .vial:
            return stepTotal == 0

        default:
            return false
        }
    }
    
    
    /// Pills expected in the back count: what was poured into the container minus
    /// what was dispensed. 0 means there is nothing left to scan.
    func containerPendingTarget() -> Int {
        guard let txn = currentTransaction else { return 0 }

        let containerCount = transactionDetailDAO.totalCountForStep(
            txnId: txn.txn_id,
            step: .containerInitiate
        )

        return max(Int(containerCount) - Int(txn.target_count), 0)
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
        guard let next = steps[safe: currentIndex + 1] else { return }

        // Back count with 0 remaining can never satisfy `stepTotal == expected`, and
        // handleAdd rejects every add against a 0 target — entering the step would
        // strand the transaction in PARTIAL. Skip it instead of proceeding.
        if next == .containerPending, containerPendingTarget() == 0 {
            showSkipBackCountPopup = true
            return
        }

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
        
        if let img = image {
            pendingBarcodeImagePath = PhotoFileManager.shared.saveImage(img)
        }

        transactionDAO.update(
            txnId: txnId,
            drugId: isNdcEquivalent ? actualDrugId : nil,
            isDispense: isDispense,
            targetCount: nil,
            substituedDrugId: isNdcEquivalent ? nil : actualDrugId,
            isSubstitue: isNdcEquivalent
        )

        isDrugFound = true
    }
}
