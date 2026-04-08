import SwiftUI

extension PillScanViewModel {
    
    func checkIsNdcMatch(rawValueFromBarcodeOrQr: String) -> Bool {
        
        print("🔍 [SCAN] Raw Value:", rawValueFromBarcodeOrQr)

        let decoded = decoder.decode(rawValueFromBarcodeOrQr)
        let scannedNdc = decoded.gtin ?? ""

        print("🔍 [SCAN] Decoded GTIN:", scannedNdc)

        guard let expectedNdc = getExpectedPmsNdc() else {
            print("⚠️ [NDC] No expected PMS NDC found → skipping validation")
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
        
        print("✍️ [MANUAL ENTRY]")
        print("✅ [NDC] Expected:", expectedNdc)
        print("✅ [NDC] Scanned:", scannedNdc)

        getControlledDrugInfo(
            targetNdc: expectedNdc,
            scannedNdc: scannedNdc
        )
    }
    
    func getControlledDrugInfo(targetNdc: String, scannedNdc: String) {
        print("🌐 [API CALL] Validating NDC...")
        print("➡️ Target NDC:", targetNdc)
        print("➡️ Scanned NDC:", scannedNdc)

        let request = NdcValidationRequest(
            targetNdc: targetNdc,
            scannedNdc: scannedNdc
        )

        isCheckingNdc = true

        Task {
            do {
                let response = try await controlledRepo
                    .getControlledDrugInfo(ndcValidationRequest: request)

                print("✅ [API SUCCESS] Full Response:", response)

                ndcComparisonResponse = response

                let isEquivalent = response.data?.isNdcEquivalent ?? false
                let isSame = response.data?.isNdcSame ?? false

                print("🔎 [RESULT] isEquivalent:", isEquivalent)
                print("🔎 [RESULT] isSame:", isSame)

                isNdcEquivalent = isEquivalent

                if isEquivalent && !isSame {
                    print("⚠️ [FLOW] Equivalent but NOT same → show popup")
                    showNdcEquivalencePopup = true
                } else if !isEquivalent && isSame{
                    print("✅ [FLOW] Safe to proceed → auto count")
                    shouldAutoProceedToCount = true
                } else {
                    showNdcEquivalencePopup = true
                    isNdcEquivalent = false
                }

            } catch {
                print("❌ [API ERROR] Failed to get controlled drug info:", error.localizedDescription)
                showNdcEquivalencePopup = true
                isNdcEquivalent = false
            }

            isCheckingNdc = false
            print("🔄 [STATE] isCheckingNdc = false")
        }
    }
    
    func markNdcVerified() {
        print("✔️ [VERIFY] Marking NDC as verified")

        if let txnId = selectedTransaction?.txn_id {
            print("🆔 [VERIFY] txnId:", txnId)

            PillsDataLocalStorage.shared.updateNdcVerified(
                txnId: txnId,
                verified: true
            )

            print("✅ [VERIFY] Updated in local DB")

        } else {
            print("❌ [VERIFY] No transaction found")
        }
    }
    
    // Get Only PMS transaction
    func getExpectedPmsNdc() -> String? {
        guard let txn = selectedTransaction else {
            print("❌ [NDC] No selected transaction")
            return nil
        }

        print("📦 [TXN] is_from_pms:", txn.is_from_pms)
        print("📦 [TXN] count_type:", txn.count_type)
        print("📦 [TXN] drug ndc:", txn.drug?.ndc ?? "nil")

        guard txn.is_from_pms,
              let ndc = txn.drug?.ndc,
              !ndc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              txn.count_type == CountType.FIXED.rawValue
        else {
            print("⚠️ [NDC] Conditions not met → skipping PMS NDC")
            return nil
        }

        print("✅ [NDC] Using PMS NDC:", ndc)
        return ndc
    }
}
