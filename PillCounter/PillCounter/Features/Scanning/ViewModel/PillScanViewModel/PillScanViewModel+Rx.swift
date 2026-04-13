//
//  PillScanViewModel+Rx.swift
//  PillCounter
//
//  Created by Bhushan Patil on 10/04/26.
//

import Foundation
extension PillScanViewModel {
    // MARK: - Parse + Drug Lookup
    func parseScanData(actualValue: String) {
        
        let barcodeFormat = AppStorageManager.shared.barcodeFormat
        do {
            // MARK: Extract keys inside { } from barcode format
            let regex = try NSRegularExpression(pattern: "\\{(.*?)\\}")
            let matches = regex.matches(
                in: barcodeFormat,
                range: NSRange(barcodeFormat.startIndex..., in: barcodeFormat)
            )
            let keys: [String] = matches.compactMap { match in
                if let range = Range(match.range(at: 1), in: barcodeFormat) {
                    return String(barcodeFormat[range])
                        .trimmingCharacters(in: .whitespaces)
                        .uppercased()
                }
                return nil
            }
            let values = actualValue
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !keys.isEmpty, !values.isEmpty else {
                scannedRxData = ParsedScanData()
                showRxFlowPopup = false
                return
            }
            // MARK: 2️⃣ Map keys → values
            var mappedData: [String: String] = [:]
            for (index, key) in keys.enumerated() {
                if index < values.count {
                    mappedData[key] = values[index]
                }
            }
            let ndc = mappedData["NDCNO"] ?? ""
            // MARK: 3️⃣ Resolve drug name then show popup
            Task {
                let resolvedDrugName = await resolveDrugName(for: ndc)
                scannedRxData = ParsedScanData(
                    rxNo: mappedData["RXNO"],
                    ndcNo: ndc.isEmpty ? nil : ndc,
                    drugName: resolvedDrugName,
                    qty: mappedData["QTY"],
                    rawMap: mappedData
                )
                showRxFlowPopup = true
            }
        } catch {
            print("❌ [RxScan] Error parsing scan data: \(error.localizedDescription)")
            scannedRxData = ParsedScanData()
            showRxFlowPopup = false
        }
    }
    // MARK: - Create Transaction from Scanned Rx Data
    /// Called when user taps PROCEED on the Rx popup.
    /// Uses the already-resolved `scannedRxData` to get/create a drug and
    /// then creates a FIXED transaction with rx number and target count.
    func createTransactionFromRxScan(countType: CountType = .FIXED) async {
        guard let rxData = scannedRxData else {
            print("❌ [RxScan] No scanned Rx data available")
            return
        }
        let ndc       = rxData.ndcNo ?? ""
        let name      = rxData.drugName ?? ""
        let rxNo      = rxData.rxNo
        let targetQty = Int32(rxData.qty ?? "") ?? 0
        print("🧾 [RxScan] Creating transaction → NDC: \(ndc), Name: \(name), Qty: \(targetQty), RxNo: \(rxNo ?? "nil"), Bucket: \(selectedBucket)")
        // MARK: 1️⃣ Get or create drug (SAME AS handleDrugFlow)
        var drugIdToUse = generateUniqueDrugId()
        if let existing = pillDataLocalStorage.getPillByNdc(by: ndc) {
            print("✅ [RxScan] Drug found in local DB → id: \(existing.drug_id)")
            drugIdToUse = existing.drug_id
        } else {
            pillDataLocalStorage.saveManualPill(
                ndc: ndc,
                drugId: drugIdToUse,
                drugName: name
            )
            print("🆕 [RxScan] New drug saved → id: \(drugIdToUse)")
        }
        self.drugName = name
        // MARK: 2️⃣ CREATE TRANSACTION (🔥 SAME FLOW)
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            barcodeImage: nil,
            isComingFromPms: false,
            targetCount: targetQty > 0 ? targetQty : nil,
            drugName: name,
            rxNo: rxNo,
            bucketId: self.selectedBucket
        )
        // MARK: 3️⃣ UI UPDATE (same pattern)
        await MainActor.run {
            self.selectedTransaction = self.currentTransaction
            if targetQty > 0 {
                let digits = String(targetQty).map { String($0) }
                let padded = Array(repeating: "", count: max(0, 4 - digits.count)) + digits
                self.targetCount = Array(padded.suffix(4))
                self.updateTargetCountForCurrentTransaction()
            }
     
            self.showRxFlowPopup = false
            self.selectedBucket = ""
        }
    }
    
    // MARK: - Format Match Check
    /// Builds a regex from the API barcodeFormat and tests the scanned value against it.
    /// Returns true only if the scanned value structurally matches the format.
    func matchesBarcodeFormat(_ value: String) -> Bool {
        let format = AppStorageManager.shared.barcodeFormat
        guard !format.isEmpty else { return false }
        do {
            let placeholderRegex = try NSRegularExpression(pattern: "\\{[^}]+\\}")
            let formatRange = NSRange(format.startIndex..., in: format)
            let matches = placeholderRegex.matches(in: format, range: formatRange)
            guard !matches.isEmpty else { return false }
            // Build a full regex by escaping literal separators and replacing
            // each {KEY} placeholder with a non-greedy capture group
            var regexParts: [String] = []
            var lastEnd = format.startIndex
            for match in matches {
                guard let matchRange = Range(match.range, in: format) else { continue }
                // Escape the literal separator before this placeholder (e.g. "|")
                let literal = String(format[lastEnd..<matchRange.lowerBound])
                if !literal.isEmpty {
                    regexParts.append(NSRegularExpression.escapedPattern(for: literal))
                }
                regexParts.append("(.+?)")
                lastEnd = matchRange.upperBound
            }
            // Escape any trailing literal after last placeholder
            let trailing = String(format[lastEnd...])
            if !trailing.isEmpty {
                regexParts.append(NSRegularExpression.escapedPattern(for: trailing))
            }
            let pattern = "^" + regexParts.joined() + "$"
            let valueRegex = try NSRegularExpression(pattern: pattern)
            let valueRange = NSRange(value.startIndex..., in: value)
            return valueRegex.firstMatch(in: value, range: valueRange) != nil
        } catch {
            print("❌ [RxScan] matchesBarcodeFormat error: \(error)")
            return false
        }
    }
    // MARK: - Drug Name Resolution (Local → API)
    private func resolveDrugName(for ndc: String) async -> String? {
        
        guard !ndc.isEmpty else { return nil }

        // ✅ STEP 1 — LOCAL DB
        if let localDrug = pillDataLocalStorage.getPillByNdc(by: ndc) {
            print("✅ [RxScan] Drug found in local DB → \(localDrug.drug_name ?? "")")
            return localDrug.drug_name
        }

        print("🌐 [RxScan] Not in local DB → calling CONTROLLED API")

        // ✅ STEP 2 — CALL CONTROLLED API
        let request = NdcValidationRequest(
            targetNdc: ndc,
            scannedNdc: ndc
        )

        do {
            let response = try await controlledRepo.getControlledDrugInfo(
                ndcValidationRequest: request
            )

            guard let data = response.data else {
                print("[RxScan] No data from controlled API")
                return nil
            }


            //STEP 3 — SAVE FULL DATA LOCALLY
            let drugId = generateUniqueDrugId()

            pillDataLocalStorage.saveManualPill(
                ndc: ndc,
                drugId: drugId,
                drugName: data.scannedNdc?.lookupName ?? "",
                drugType: data.scannedNdc?.deaSchedule,
                packageQty: data.scannedNdc?.safeQuantity ?? 0
            )

            return data.scannedNdc?.lookupName ?? ""

        } catch {
            print("❌ [RxScan] Controlled API error:", error.localizedDescription)
            return nil
        }
    }
    

}
struct ParsedScanData {
    let rxNo: String?
    let ndcNo: String?
    let drugName: String?
    let qty: String?
    let rawMap: [String: String]
    
    init(
        rxNo: String? = nil,
        ndcNo: String? = nil,
        drugName: String? = nil,
        qty: String? = nil,
        rawMap: [String: String] = [:],
        drugType: String? = nil,
    ) {
        self.rxNo = rxNo
        self.ndcNo = ndcNo
        self.drugName = drugName
        self.qty = qty
        self.rawMap = rawMap
    }
}
