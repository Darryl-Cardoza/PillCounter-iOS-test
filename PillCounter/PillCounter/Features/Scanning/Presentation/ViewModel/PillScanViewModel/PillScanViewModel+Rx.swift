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
            // MARK: 1️⃣ Extract keys inside { } from barcode format
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

            let ndc    = mappedData["NDCNO"] ?? ""
            let bucket = mappedData["BUCKET"]?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? mappedData["BUCKET"]!
                : "NORMAL"

            self.selectedBucket = bucket
            print("[RxScan] Bucket Id: \(selectedBucket)")

            // MARK: 3️⃣ Resolve drug name then show popup
            // Always show popup — even if drug name resolution fails entirely
            Task {
                let resolvedDrugName = await resolveDrugName(for: ndc)

                // Build ParsedScanData with whatever we have.
                // resolvedDrugName may be nil if both local DB and API failed —
                // the popup will still appear so the user can review RX/NDC/QTY.
                scannedRxData = ParsedScanData(
                    rxNo:     mappedData["RXNO"],
                    ndcNo:    ndc.isEmpty ? nil : ndc,
                    drugName: resolvedDrugName,   // nil is fine — popup handles it
                    qty:      mappedData["QTY"],
                    rawMap:   mappedData
                )

                print("[RxScan] Showing Rx popup → rxNo: \(scannedRxData?.rxNo ?? "nil"), ndc: \(scannedRxData?.ndcNo ?? "nil"), drug: \(scannedRxData?.drugName ?? "UNKNOWN"), qty: \(scannedRxData?.qty ?? "nil")")

                // Always show the popup regardless of drug name resolution outcome
                showRxFlowPopup = true
            }

        } catch {
            print("[RxScan] Error parsing scan data: \(error.localizedDescription)")
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
            print("[RxScan] No scanned Rx data available")
            return
        }

        let ndc       = rxData.ndcNo ?? ""
        let name      = rxData.drugName ?? ""   // empty string if unresolved — still proceeds
        let rxNo      = rxData.rxNo
        let targetQty = Int32(rxData.qty ?? "") ?? 0

        print("🧾 [RxScan] Creating transaction → NDC: \(ndc), Name: \(name.isEmpty ? "UNKNOWN" : name), Qty: \(targetQty), RxNo: \(rxNo ?? "nil"), Bucket: \(selectedBucket)")

        // MARK: 1️⃣ Get or create drug
        var drugIdToUse = generateUniqueDrugId()
        if let existing = drugMasterDAO.fetchByNdc(ndc) {
            print("[RxScan] Drug found in local DB → id: \(existing.drug_id)")
            drugIdToUse = existing.drug_id
        } else {
            drugMasterDAO.saveManual(
                ndc: ndc,
                drugId: drugIdToUse,
                drugName: name
            )
            print("🆕 [RxScan] New drug saved → id: \(drugIdToUse)")
        }

//        self.drugName = name

        // MARK: 2️⃣ Create transaction
        await createTransaction(
            drugId:           drugIdToUse,
            countType:        countType,
            barcodeImage:     nil,
            isComingFromPms:  false,
            targetCount:      targetQty > 0 ? targetQty : nil,
            drugName:         name,
            rxNo:             rxNo,
            bucketId:         self.selectedBucket
        )

        // MARK: 3️⃣ UI update
        await MainActor.run {
            self.selectedTransaction = self.currentTransaction

            if targetQty > 0 {
                let digits = String(targetQty).map { String($0) }
                let padded = Array(repeating: "", count: max(0, 4 - digits.count)) + digits
                self.targetCount = Array(padded.suffix(4))
                self.updateTargetCountForCurrentTransaction()
            }

            self.showRxFlowPopup = false
            self.selectedBucket  = ""
        }
    }

    // MARK: - Format Match Check
    /// Builds a regex from the API barcodeFormat and tests the scanned value against it.
    /// Required fields (RXNO, NDCNO, QTY) must be present; BUCKET is optional.
    func matchesBarcodeFormat(_ value: String) -> Bool {
        let format = AppStorageManager.shared.barcodeFormat
        guard !format.isEmpty else { return false }

        do {
            let placeholderRegex = try NSRegularExpression(pattern: "\\{[^}]+\\}")
            let formatRange      = NSRange(format.startIndex..., in: format)
            let matches          = placeholderRegex.matches(in: format, range: formatRange)
            guard !matches.isEmpty else { return false }

            var regexParts: [String] = []
            var lastEnd = format.startIndex

            for (i, match) in matches.enumerated() {
                guard let matchRange = Range(match.range, in: format) else { continue }

                let literal = String(format[lastEnd..<matchRange.lowerBound])
                let keyName = String(format[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    .uppercased()

                let isLastPlaceholder = i == matches.count - 1
                let isOptional = isLastPlaceholder && keyName == "BUCKET"

                if isOptional {
                    // Make the separator + BUCKET value entirely optional
                    let escapedLiteral = NSRegularExpression.escapedPattern(for: literal)
                    regexParts.append("(?:\(escapedLiteral)(.+?))?")
                } else {
                    if !literal.isEmpty {
                        regexParts.append(NSRegularExpression.escapedPattern(for: literal))
                    }
                    regexParts.append("(.+?)")
                }

                lastEnd = matchRange.upperBound
            }

            let trailing = String(format[lastEnd...])
            if !trailing.isEmpty {
                regexParts.append(NSRegularExpression.escapedPattern(for: trailing))
            }

            let pattern    = "^" + regexParts.joined() + "$"
            let valueRegex = try NSRegularExpression(pattern: pattern)
            let valueRange = NSRange(value.startIndex..., in: value)
            return valueRegex.firstMatch(in: value, range: valueRange) != nil

        } catch {
            print("[RxScan] matchesBarcodeFormat error: \(error)")
            return false
        }
    }

    // MARK: - Drug Name Resolution (Local → API → Fallback nil)
    /// Resolution order:
    ///   1. Local DB  → return name immediately
    ///   2. Controlled API  → save to local DB, return name
    ///   3. Both failed  → return **nil** (caller still shows the popup)
    private func resolveDrugName(for ndc: String) async -> String? {
        guard !ndc.isEmpty else {
            print("[RxScan] NDC is empty — skipping resolution")
            return nil
        }

        // STEP 1 — LOCAL DB
        if let localDrug = drugMasterDAO.fetchByNdc(ndc) {
            let localName = localDrug.drug_name ?? ""
            print("[RxScan] Drug found in local DB → '\(localName)'")
            // Return even if localName is empty string — avoids unnecessary API call
            return localName.isEmpty ? nil : localName
        }

        print("[RxScan] Not in local DB → calling Controlled API")

        // STEP 2 — CONTROLLED API
        let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
        do {
            let response = try await controlledRepo.getControlledDrugInfo(
                ndcValidationRequest: request
            )

            guard let data = response.data else {
                print("[RxScan] API returned no data — will show popup with available info")
                return nil   // ← nil, NOT a rescan trigger
            }

            let resolvedName = data.scannedNdc?.lookupName ?? ""

            // STEP 3 — SAVE FULL DATA LOCALLY
            let drugId = generateUniqueDrugId()
            drugMasterDAO.saveManual(
                ndc:        ndc,
                drugId:     drugId,
                drugName:   resolvedName,
                drugType:   data.scannedNdc?.deaSchedule,
                packageQty: data.scannedNdc?.safeQuantity ?? 0
            )

            print("[RxScan] Drug resolved from API → '\(resolvedName)'")
            return resolvedName.isEmpty ? nil : resolvedName

        } catch {
            // API threw an error — log it but DO NOT trigger a rescan.
            // Return nil so parseScanData still shows the popup with RX/NDC/QTY.
            print("[RxScan] Controlled API error (will still show popup): \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - ParsedScanData
struct ParsedScanData {
    let rxNo:     String?
    let ndcNo:    String?
    let drugName: String?
    let qty:      String?
    let rawMap:   [String: String]

    init(
        rxNo:      String?           = nil,
        ndcNo:     String?           = nil,
        drugName:  String?           = nil,
        qty:       String?           = nil,
        rawMap:    [String: String]  = [:],
        drugType:  String?           = nil
    ) {
        self.rxNo     = rxNo
        self.ndcNo    = ndcNo
        self.drugName = drugName
        self.qty      = qty
        self.rawMap   = rawMap
    }
}
