//
//  PillScanViewModel+Rx.swift
//  PillCounter
//
//  Created by Bhushan Patil on 10/04/26.
//

import Foundation

// MARK: - ParsedScanData

struct ParsedScanData {
    let rxNo:     String?
    let ndcNo:    String?
    let drugName: String?
    let qty:      String?
    let rawMap:   [String: String]

    init(
        rxNo:     String?           = nil,
        ndcNo:    String?           = nil,
        drugName: String?           = nil,
        qty:      String?           = nil,
        rawMap:   [String: String]  = [:]
    ) {
        self.rxNo     = rxNo
        self.ndcNo    = ndcNo
        self.drugName = drugName
        self.qty      = qty
        self.rawMap   = rawMap
    }
}

// MARK: - PillScanViewModel Rx Extension

extension PillScanViewModel {

    // MARK: Parse Scanned Barcode

    func parseScanData(actualValue: String) {
        let barcodeFormat = AppStorageManager.shared.barcodeFormat

        do {
            let keys   = try extractKeys(from: barcodeFormat)
            let values = extractValues(from: actualValue)

            guard !keys.isEmpty, !values.isEmpty else {
                scannedRxData   = ParsedScanData()
                showRxFlowPopup = false
                return
            }

            let mappedData = zip(keys, values).reduce(into: [String: String]()) { result, pair in
                result[pair.0] = pair.1
            }

            let ndc    = mappedData["NDCNO"] ?? ""
            let bucket = mappedData["BUCKET"]?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? mappedData["BUCKET"]!
                : "NORMAL"

            self.selectedBucket = bucket
            print("[RxScan] Bucket: \(selectedBucket)")

            Task {
                let resolvedDrugName = await resolveDrugName(for: ndc)

                guard let drugName = resolvedDrugName else {
                    showToastMessage(text: "Rx not found")
                    rxScanFailed = true
                    return
                }

                scannedRxData = ParsedScanData(
                    rxNo:     mappedData["RXNO"],
                    ndcNo:    ndc.isEmpty ? nil : ndc,
                    drugName: drugName,
                    qty:      mappedData["QTY"],
                    rawMap:   mappedData
                )

                print("[RxScan] Rx popup → rxNo: \(scannedRxData?.rxNo ?? "nil"), ndc: \(scannedRxData?.ndcNo ?? "nil"), drug: \(scannedRxData?.drugName ?? "UNKNOWN"), qty: \(scannedRxData?.qty ?? "nil")")

                showRxFlowPopup = true
            }

        } catch {
            print("[RxScan] Error parsing scan data: \(error.localizedDescription)")
            scannedRxData   = ParsedScanData()
            showRxFlowPopup = false
        }
    }

    // MARK: Create Transaction from Scanned Rx Data

    /// Called when user taps PROCEED on the Rx popup.
    func createTransactionFromRxScan(countType: CountType = .FIXED) async {
        guard let rxData = scannedRxData else {
            print("[RxScan] No scanned Rx data available")
            return
        }

        let ndc       = rxData.ndcNo  ?? ""
        let name      = rxData.drugName ?? ""
        let rxNo      = rxData.rxNo
        let targetQty = Int32(rxData.qty ?? "") ?? 0

        guard let drug = drugMasterDAO.fetchByNdc(ndc) else {
            print("[RxScan] Drug not found in local DB — cannot create transaction")
            showToastMessage(text: "Rx not found")
            return
        }

        print("[RxScan] Creating transaction → NDC: \(ndc), Name: \(name.isEmpty ? "UNKNOWN" : name), Qty: \(targetQty), RxNo: \(rxNo ?? "nil"), Bucket: \(selectedBucket)")

        let workFlowStep: String
        if let type = drug.drug_type, !type.trimmingCharacters(in: .whitespaces).isEmpty {
            workFlowStep = ControlledStep.containerInitiate.rawValue
        } else {
            workFlowStep = ControlledStep.targetVerification.rawValue
        }

        await createTransaction(
            drugId:          drug.drug_id,
            countType:       countType,
            barcodeImage:    nil,
            isComingFromPms: false,
            targetCount:     targetQty > 0 ? targetQty : nil,
            drugName:        name,
            rxNo:            rxNo,
            bucketId:        selectedBucket,
            workFlowStep:    workFlowStep
        )

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

    // MARK: Barcode Format Match Check

    /// Builds a regex from the configured barcodeFormat and tests the scanned value against it.
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

            for (index, match) in matches.enumerated() {
                guard let matchRange = Range(match.range, in: format) else { continue }

                let literal = String(format[lastEnd..<matchRange.lowerBound])
                let keyName = String(format[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    .uppercased()

                let isLastPlaceholder = index == matches.count - 1
                let isOptional        = isLastPlaceholder && keyName == "BUCKET"

                if isOptional {
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

    // MARK: Drug Name Resolution (Local DB → API → nil)

    /// Resolution order:
    ///   1. Local DB  → return name immediately
    ///   2. Controlled API  → save to local DB, return name
    ///   3. Both failed  → return nil (caller shows toast)
    private func resolveDrugName(for ndc: String) async -> String? {
        guard !ndc.isEmpty else {
            print("[RxScan] NDC is empty — skipping resolution")
            return nil
        }

        // STEP 1 — LOCAL DB
        if let localDrug = drugMasterDAO.fetchByNdc(ndc) {
            let name = localDrug.drug_name ?? ""
            print("[RxScan] Drug found in local DB → '\(name)'")
            return name.isEmpty ? nil : name
        }

        print("[RxScan] Not in local DB → calling Controlled API")

        // STEP 2 — CONTROLLED API
        let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
        do {
            let response = try await controlledRepo.getControlledDrugInfo(ndcValidationRequest: request)

            guard let data = response.data else {
                print("[RxScan] API returned no data")
                return nil
            }

            let resolvedName = data.scannedNdc?.lookupName ?? ""

            drugMasterDAO.saveManual(
                ndc:          ndc,
                drugId:       generateUniqueDrugId(),
                drugName:     resolvedName,
                drugType:     data.scannedNdc?.deaSchedule,
                packageQty:   data.scannedNdc?.safeQuantity ?? 0,
                isHazardous:  data.scannedNdc?.isHazardous
            )
            print("[resolve Drug Name : isHazardous : ] \(data.scannedNdc?.isHazardous ?? false)")

            print("[RxScan] Drug resolved from API → '\(resolvedName)'")
            return resolvedName.isEmpty ? nil : resolvedName

        } catch {
            print("[RxScan] Controlled API error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Private Helpers

    private func extractKeys(from format: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "\\{(.*?)\\}")
        let range = NSRange(format.startIndex..., in: format)
        return regex.matches(in: format, range: range).compactMap { match in
            guard let keyRange = Range(match.range(at: 1), in: format) else { return nil }
            return String(format[keyRange])
                .trimmingCharacters(in: .whitespaces)
                .uppercased()
        }
    }

    private func extractValues(from rawValue: String) -> [String] {
        rawValue
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
