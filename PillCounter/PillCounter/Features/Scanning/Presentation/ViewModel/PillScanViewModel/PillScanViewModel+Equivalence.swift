import SwiftUI

extension PillScanViewModel {
    
    func checkIsNdcMatch(rawValueFromBarcodeOrQr: String) -> Bool {
        
        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let scannedNdc = decoded.gtin ?? ""

        guard let expectedNdc = getExpectedNdc() else {
            return true
        }

        getControlledDrugInfo(
            targetNdc: expectedNdc, // NDC
            scannedNdc: scannedNdc  // Gtin
        )
        
        return false
    }

    func getControlledDrugInfo(targetNdc: String, scannedNdc: String) {
        isCheckingNdc = true

        // Check drug master first — if the scanned GTIN is already cached locally,
        // resolve same/equivalent synchronously and skip the network round-trip.
        if let localDrug = drugMasterDAO.fetchByGtin(scannedNdc),
           let localNdc = localDrug.ndc, !localNdc.isEmpty,
           let localName = localDrug.drug_name, !localName.isEmpty {
            print("LocalName \(localName)")
            let isSame = localNdc == targetNdc
            isNdcEquivalent = false
            updateScannedDrugData(drugName: localName, ndcNo: localNdc)
            if isSame {
                isCheckingNdc = false
                showScannedDrugInfoPopoup = true
            } else {
                // NDCs differ locally — fall through to API for equivalence check.
                isCheckingNdc = false
                callControlledDrugInfoAPI(targetNdc: targetNdc, scannedNdc: scannedNdc)
            }
            return
        }

        callControlledDrugInfoAPI(targetNdc: targetNdc, scannedNdc: scannedNdc)
    }

    private func callControlledDrugInfoAPI(targetNdc: String, scannedNdc: String) {
        let request = NdcValidationRequest(
            targetNdc: targetNdc,
            scannedNdc: scannedNdc
        )

        Task {
            do {
                let response = try await controlledRepo
                    .getControlledDrugInfo(ndcValidationRequest: request)

                ndcComparisonResponse = response

                let isEquivalent = response.data?.isNdcEquivalent ?? false
                let isSame = response.data?.isNdcSame ?? false

                isNdcEquivalent = isEquivalent
                updateScannedDrugData(drugName: response.data?.scannedNdc?.lookupName ?? "", ndcNo: response.data?.scannedNdc?.packageNdc ?? "")

                if isEquivalent && !isSame {
                    showNdcEquivalencePopup = true
                } else if !isEquivalent && isSame {
                    // Backfill GTIN in drug master if not stored yet, so future scans resolve locally.
                    if let localDrug = drugMasterDAO.fetchByNdc(targetNdc),
                       (localDrug.gtin == nil || localDrug.gtin!.isEmpty),
                       !scannedNdc.isEmpty {
                        drugMasterDAO.update(drugId: localDrug.drug_id,drugName: localDrug.drug_name, gtin: scannedNdc)
                    }
                    self.showScannedDrugInfoPopoup = true
                } else {
                    isNdcEquivalent = false
                    showToastMessage(text: L10n.BarcodeScan.ndcDoesNotMatch)
                    ndcMismatchRestartFlow = true
                }

            } catch {
                isNdcEquivalent = false
                showToastMessage(text: L10n.BarcodeScan.ndcDoesNotMatch)
                ndcMismatchRestartFlow = true
            }

            isCheckingNdc = false
        }
    }
    
    func updateScannedDrugData(drugName:String, ndcNo: String){
        self.scannedRxData = ParsedScanData(ndcNo: ndcNo,drugName: drugName)
    }
    
    func markNdcVerified() {
        if let txnId = selectedTransaction?.txn_id {
            transactionDAO.updateNdcVerified(txnId: txnId, verified: true)
        }
    }
    
    // Get Only PMS transaction
    func getExpectedNdc() -> String? {
        guard let txn = selectedTransaction else {
            return nil
        }

        guard 
              let ndc = txn.drug?.ndc,
              !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              txn.count_type == CountType.FIXED.rawValue
        else {
            return nil
        }

        return ndc
    }
}
