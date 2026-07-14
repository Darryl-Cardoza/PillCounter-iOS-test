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
                    showToastMessage(text: L10n.BarcodeScan.rxNotFound)
                    rxScanFailed = true
                    return
                }

                let rawRxNo = mappedData["RXNO"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rxNo: String? = rawRxNo.isEmpty ? nil : rawRxNo

                // Rx must exist in local DB — if not found, abort with a toast
                guard let rxNo, !rxNo.isEmpty else {
                    print("[RxScan] No RXNO in barcode — cannot proceed")
                    showToastMessage(text: L10n.BarcodeScan.rxNotFound)
                    rxScanFailed = true
                    return
                }

                let currentUser = userDataLocalStorage.fetchByUserId(userId)
                guard let currentUser else {
                    print("[RxScan] No current user — cannot look up Rx")
                    rxScanFailed = true
                    return
                }

                let allStoredRxNos = transactionDAO.fetchAllRxNos(for: currentUser)
                print("[RxScan] All rx_no values in DB: \(allStoredRxNos)")
                print("[RxScan] Looking up rxNo: '\(rxNo)'")

                let existingTxn = fetchRxTransaction(rxNo: rxNo, for: currentUser)
                print("[RxScan] fetchByRxNo('\(rxNo)') → \(existingTxn == nil ? "nil" : "txnId=\(existingTxn!.txn_id) status=\(existingTxn!.status ?? "nil")")")

                guard let existingTxn else {
                    print("[RxScan] Rx \(rxNo) not found in DB — aborting")
                    showToastMessage(text: L10n.BarcodeScan.rxNotSentByPms)
                    rxScanFailed = true
                    return
                }

                if existingTxn.status == CountStatus.ON_HOLD.rawValue {
                    print("[RxScan] Rx \(rxNo) is ON HOLD — showing hold popup")
                    showRxOnHoldPopup = true
                    return
                }

                scannedRxData = ParsedScanData(
                    rxNo:     rxNo,
                    ndcNo:    ndc.isEmpty ? nil : ndc,
                    drugName: drugName,
                    qty:      mappedData["QTY"],
                    rawMap:   mappedData
                )
                fetchedRxTransaction = existingTxn

                if existingTxn.is_ndc_verfied {
                    print("[RxScan] Rx \(rxNo) is_ndc_verfied=true — resuming inline")
                    self.selectedTransaction  = existingTxn
                    self.currentTransaction   = existingTxn
                    self.fetchedRxTransaction = nil
                    self.rxResumeInline       = true
                } else {
                    print("[RxScan] Rx popup → rxNo: \(scannedRxData?.rxNo ?? "nil"), ndc: \(scannedRxData?.ndcNo ?? "nil"), drug: \(scannedRxData?.drugName ?? "UNKNOWN"), qty: \(scannedRxData?.qty ?? "nil")")
                    showRxFlowPopup = true
                }
                
                
            }

        } catch {
            print("[RxScan] Error parsing scan data: \(error.localizedDescription)")
            scannedRxData   = ParsedScanData()
            showRxFlowPopup = false
        }
    }

    /// Looks up the transaction for the given Rx number. Checks active transactions first;
    /// falls back to the most-recently deleted one (which can be restored).
    func fetchRxTransaction(rxNo: String, for user: UserEntity) -> PillCountTransactionEntity? {
        if let txn = transactionDAO.fetchByRxNo(rxNo, for: user).first {
            return txn
        }
        return transactionDAO.fetchDeletedByRxNo(rxNo, for: user)
    }

    // MARK: Proceed with Rx Transaction

    /// Called when user taps PROCEED on the Rx popup.
    /// Fetches the existing transaction for the scanned Rx and sets it as the selected transaction
    /// so the normal barcode-scan flow (scan stock bottle → NDC match → pill count) can continue.
    /// Does NOT modify any Rx data.
    func proceedFromRxScan() {
        guard let rxNo = scannedRxData?.rxNo, !rxNo.isEmpty else {
            print("[RxScan] proceedFromRxScan — no rxNo, cannot proceed")
            rxScanFailed = true
            return
        }

        let currentUser = userDataLocalStorage.fetchByUserId(userId)
        guard let currentUser,
              let existingTxn = fetchRxTransaction(rxNo: rxNo, for: currentUser) else {
            print("[RxScan] proceedFromRxScan — Rx \(rxNo) not found in DB")
            rxScanFailed = true
            return
        }

        print("[RxScan] proceedFromRxScan — setting selectedTransaction txnId=\(existingTxn.txn_id) for rxNo=\(rxNo)")
        self.selectedTransaction  = existingTxn
        self.currentTransaction   = existingTxn
        self.fetchedRxTransaction = nil
        self.showRxFlowPopup      = false
    }

    /// Called when user taps PROCEED on the Rx popup.
    /// Always updates the existing transaction found during parseScanData — never creates a new one.
    func createTransactionFromRxScan(isDispense: Bool = true) async {
        guard let rxData = scannedRxData else {
            print("[RxScan] No scanned Rx data available")
            return
        }

        let ndc       = rxData.ndcNo  ?? ""
        let rxNo      = rxData.rxNo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetQty = Int32(rxData.qty ?? "") ?? 0

        guard let drug = drugMasterDAO.fetchByNdc(ndc) else {
            print("[RxScan] Drug not found in local DB — cannot proceed")
            showToastMessage(text: L10n.BarcodeScan.rxNotFound)
            return
        }

        guard let rxNo, !rxNo.isEmpty else {
            print("[RxScan] No rxNo on scannedRxData — cannot proceed")
            showToastMessage(text: L10n.BarcodeScan.rxNotFound)
            return
        }

        let currentUser = userDataLocalStorage.fetchByUserId(userId)
        guard let currentUser,
              let existingTxn = fetchRxTransaction(rxNo: rxNo, for: currentUser) else {
            print("[RxScan] Rx \(rxNo) no longer found in DB on proceed — aborting")
            showToastMessage(text: L10n.BarcodeScan.rxNotSentByPms)
            return
        }

        // Restore soft-deleted transaction if needed
        if existingTxn.is_deleted {
            transactionDAO.restoreDeleted(txnId: existingTxn.txn_id)
        }

        let txnId = existingTxn.txn_id
        print("[RxScan] Updating existing txnId=\(txnId) for rxNo=\(rxNo)")

        transactionDAO.updateFromHL7Edit(
            txnId: txnId,
            drugId: drug.drug_id,
            targetCount: targetQty,
            priority: existingTxn.txn_priority
        )

        await MainActor.run {
            self.currentTransaction  = transactionDAO.fetchById(txnId)
            self.selectedTransaction = self.currentTransaction

            getAllTransactionDetailsOfTheCurrentTransaction()

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

    // MARK: Rx Number Extraction (no side effects)

    /// Pulls just the RXNO field out of a scanned barcode using the configured
    /// barcodeFormat, without running any of the lookup/popup flow that
    /// `parseScanData` performs. Used by the vial auto-capture step to match a
    /// scanned vial label against the current transaction's rx_no.
    /// Returns nil if the value doesn't match the format or has no RXNO field.
    func extractRxNo(from value: String) -> String? {
        let barcodeFormat = AppStorageManager.shared.barcodeFormat
        guard let keys = try? extractKeys(from: barcodeFormat) else { return nil }
        let values = extractValues(from: value)
        guard !keys.isEmpty, !values.isEmpty else { return nil }

        let mapped = zip(keys, values).reduce(into: [String: String]()) { $0[$1.0] = $1.1 }
        let rxNo = mapped["RXNO"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rxNo.isEmpty ? nil : rxNo
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

            if let scannedNdc = data.scannedNdc {
                drugMasterDAO.upsertFromApi(
                    ndc:    ndc,
                    drugId: generateUniqueDrugId(),
                    drug:   scannedNdc
                )
            }
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
