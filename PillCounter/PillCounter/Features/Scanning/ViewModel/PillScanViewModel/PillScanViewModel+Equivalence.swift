//
//  PillScanViewModel+Equivalence.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/03/26.
//

extension PillScanViewModel {
    
    //
    func checkIsNdcMatch(rawValueFromBarcodeOrQr: String) -> Bool {
        
        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let scannedNdc = decoded.gtin ?? ""

        guard let expectedNdc = getExpectedPmsNdc() else {
            return true
        }
        print("Expected NDC: \(expectedNdc)")
        print("Scanned NDC: \(scannedNdc)")

        getControlledDrugInfo(
            targetNdc: expectedNdc,
            scannedNdc: scannedNdc
        )
        
        return false
    }
    
    func getControlledDrugInfo(targetNdc: String, scannedNdc: String) {

        let request = NdcValidationRequest(
            targetNdc: targetNdc,
            scannedNdc: scannedNdc
        )

        isCheckingNdc = true

        Task {
            do {
                let response = try await controlledRepo
                    .getControlledDrugInfo(ndcValidationRequest: request)

                ndcComparisonResponse = response
                isNdcEquivalent = response.data?.isNdcEquivalent ?? false

                showNdcEquivalencePopup = true

            } catch {
                // API failure → allow rescan without freezing
                showNdcEquivalencePopup = true
                isNdcEquivalent = false // make it false

            }
            isCheckingNdc = false
        }
    }
    

    func markNdcVerified() {
        if let txnId = selectedTransaction?.txn_id {
            PillsDataLocalStorage.shared.updateNdcVerified(
                txnId: txnId,
                verified: true
            )
        } else {
        }
    }
    
    // Get Only Pms transaction
    func getExpectedPmsNdc() -> String? {
        guard let txn = selectedTransaction,
              txn.is_from_pms,
              let ndc = txn.drug?.ndc,
              !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return ndc
    }
}
