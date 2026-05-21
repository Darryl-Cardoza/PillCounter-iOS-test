import SwiftUI

extension PillScanViewModel {
    
    func checkIsNdcMatch(rawValueFromBarcodeOrQr: String) -> Bool {
        
        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let scannedNdc = decoded.gtin ?? ""

        guard let expectedNdc = getExpectedNdc() else {
            return true
        }

        getControlledDrugInfo(
            targetNdc: expectedNdc,
            scannedNdc: scannedNdc
        )
        
        return false
    }
//    
//    func manualEnterdControlledDrug(scannedNdc: String){
//        let expectedNdc = getExpectedNdc() ?? ""
//        getControlledDrugInfo(
//            targetNdc: expectedNdc,
//            scannedNdc: scannedNdc
//        )
//    }
//    
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

                let isEquivalent = response.data?.isNdcEquivalent ?? false
                let isSame = response.data?.isNdcSame ?? false

                isNdcEquivalent = isEquivalent
                updateScannedDrugData(drugName: response.data?.scannedNdc?.lookupName ?? "", ndcNo: response.data?.scannedNdc?.packageNdc ?? "")
                
                if isEquivalent && !isSame {
                    showNdcEquivalencePopup = true
                } else if !isEquivalent && isSame{
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
