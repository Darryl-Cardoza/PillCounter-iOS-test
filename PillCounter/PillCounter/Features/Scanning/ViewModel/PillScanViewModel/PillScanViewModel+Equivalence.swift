import SwiftUI

extension PillScanViewModel {
    
    func checkIsNdcMatch(rawValueFromBarcodeOrQr: String) -> Bool {


        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let scannedNdc = decoded.gtin ?? ""


        guard let expectedNdc = getExpectedPmsNdc() else {
            return true
        }

        print("✅ [NDC] Expected:", expectedNdc)
        print("✅ [NDC] Scanned:", scannedNdc)

        getControlledDrugInfo(
            targetNdc: expectedNdc,
            scannedNdc: scannedNdc
        )
        
        return false
    }
    
    func manualEnterdControlledDrug(scannedNdc: String){
        let expectedNdc = getExpectedPmsNdc() ?? ""
        getControlledDrugInfo(
            targetNdc: expectedNdc,
            scannedNdc: scannedNdc
        )
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

                let isEquivalent = response.data?.isNdcEquivalent ?? false
                let isSame = response.data?.isNdcSame ?? false

                isNdcEquivalent = isEquivalent
                updateScannedDrugData(drugName: response.data?.scannedNdc?.lookupName ?? "", ndcNo: response.data?.scannedNdc?.packageNdc ?? "")
                
                if isEquivalent && !isSame {
                    showNdcEquivalencePopup = true
                } else if !isEquivalent && isSame{
                    self.showScannedDrugInfoPopoup = true
                } else {
                    showNdcEquivalencePopup = true
                    isNdcEquivalent = false
                }

            } catch {
                showNdcEquivalencePopup = true
                isNdcEquivalent = false
            }

            isCheckingNdc = false
        }
    }
    
    func updateScannedDrugData(drugName:String, ndcNo: String){
        self.scannedRxData = ParsedScanData(ndcNo: ndcNo,drugName: drugName)
    }
    
    func markNdcVerified() {
        if let txnId = selectedTransaction?.txn_id {
            PillsDataLocalStorage.shared.updateNdcVerified(
                txnId: txnId,
                verified: true
            )
        }
    }
    
    // Get Only PMS transaction
    func getExpectedPmsNdc() -> String? {
        guard let txn = selectedTransaction else {
            print("[NDC] No selected transaction")
            return nil
        }

        guard 
              let ndc = txn.drug?.ndc,
              !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              txn.count_type == CountType.FIXED.rawValue
        else {
            print("[NDC] Conditions not met → skipping PMS NDC")
            return nil
        }

        print("[NDC] Using PMS NDC:", ndc)
        return ndc
    }
}
