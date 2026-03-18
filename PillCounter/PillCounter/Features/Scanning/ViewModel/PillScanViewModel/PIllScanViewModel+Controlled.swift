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
    
    func getCurrentControlledTransaction(txnId: Int64) async {

        // Fetch transaction
        currentTransaction =
        pillDataLocalStorage.fetchPillCountTransactionByTransactionId(
            txnId: txnId
        )

        // Drug name
        drugName = currentTransaction?.drug?.drug_name ?? "Unknown"

        // Load details
        getAllTransactionDetailsOfTheCurrentTransaction()

        // Restore correct step
        getControlledStep()

        // Calculate target for step
        updateControlledTargetCount()
    }
    
    
    // MARK: - Update Target Count
    func updateControlledTargetCount() {

        guard let txn = currentTransaction else { return }
        log("❌ updateControlledTargetCount: transaction missing")

        let target = Int(txn.target_count)
        log("Updating target for step \(currentControlledStep.rawValue) target \(target)")

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
            pillDataLocalStorage.getTotalCountForStep(
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
            return stepTotal > 0
            
        case .targetVerification:
            if currentTransaction?.count_type == CountType.FIXED.rawValue {
                return stepTotal == target
            } else {
                return stepTotal > 0
            }
            
        case .targetReverification:
            return stepTotal == target

        case .containerPending:
            let containerCount =
            pillDataLocalStorage.getTotalCountForStep(
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
    
    
    func getTotalCuntForCurrentStep() -> Int32 {

        guard let txnId = currentTransaction?.txn_id else {
            return 0
        }

        let total = pillDataLocalStorage.getTotalCountForStep(
            txnId: txnId,
            step: currentControlledStep
        )

        return total
    }
    
    
    // Get Last saved Controlled Step
    func getLastSavedControlledStep() -> ControlledStep? {
        guard let txn = selectedTransaction else { return nil }
        return pillDataLocalStorage.getLastCompletedStep(txnId: txn.txn_id)
    }
    
    
    // Get which Controlled step is now
    func getControlledStep(pillCountTxn: PillCountTransactionEntity? = nil) {

        guard let txn = pillCountTxn else {
            return
        }

        // Fetch last saved step
        guard let lastStep = pillDataLocalStorage.getLastCompletedStep(txnId: txn.txn_id) else {
            if txn.is_from_pms == true {
                currentControlledStep = .containerInitiate
            } else {
                currentControlledStep = .targetVerification
            }

            updateControlledTargetCount()
            return
        }

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

        // create new drug
        let drugId = generateUniqueDrugId()

        pillDataLocalStorage.saveManualPill(
            ndc: ndcComparisonResponse?.data?.scannedNdc.packageNdc ?? "",
            drugId: drugId,
            drugName: ndcComparisonResponse?.data?.scannedNdc.lookupName ?? "",
            drugType: ndcComparisonResponse?.data?.scannedNdc.deaSchedule ?? "",
        )

        var savedPath = ""

        if let img = image {
            if let path = PhotoFileManager.shared.saveImage(img) {
                savedPath = path
            }
        }

        pillDataLocalStorage.updateTransaction(
            txnId: txnId,
            drugId: drugId,
            countType: countType,
            targetCount: nil,
            barcodeImagePath: savedPath
        )

        isDrugFound = true
    }
}
