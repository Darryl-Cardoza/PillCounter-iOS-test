//
//  PillScanViewModel+Rx.swift
//  PillCounter
//
//  Created by Bhushan Patil on 10/04/26.
//

import Foundation

// MARK: - PillScanViewModel Rx Extension

extension PillScanViewModel {

    /// Local drug master record for the currently scanned Rx's NDC — used by the Rx details
    /// sheet to show strength/form/image when there's no existing transaction yet (new Rx).
    var scannedRxDrugMaster: DrugMasterEntity? {
        guard let ndc = scannedRxData?.ndcNo, !ndc.isEmpty else { return nil }
        return drugMasterDAO.fetchByNdc(ndc)
    }

    // MARK: Parse Scanned Barcode

    func parseScanData(actualValue: String) {
        let barcodeFormat = AppStorageManager.shared.barcodeFormat

        do {
            let mappedData = try BarcodeFormatParser.mappedData(format: barcodeFormat, actualValue: actualValue)

            guard !mappedData.isEmpty else {
                scannedRxData   = ParsedScanData()
                showRxFlowPopup = false
                return
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
                    showToastMessage(text: L10n.BarcodeScan.invalidNdc)
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
                    guard AppStorageManager.shared.isStandalone else {
                        print("[RxScan] Rx \(rxNo) not found in DB — isStandalone false, showing rx not found")
                        showToastMessage(text: L10n.BarcodeScan.rxNotSentByPms)
                        rxScanFailed = true
                        return
                    }

                    print("[RxScan] Rx \(rxNo) not found in DB — showing Rx popup to create new txn")

                    scannedRxData = ParsedScanData(
                        rxNo:     rxNo,
                        ndcNo:    ndc.isEmpty ? nil : ndc,
                        drugName: drugName,
                        qty:      mappedData["QTY"],
                        refil:    mappedData["REFILLNO"],
                        rawMap:   mappedData
                    )
                    fetchedRxTransaction = nil
                    showRxFlowPopup = true
                    return
                }

                let scannedRefil = mappedData["REFILLNO"]?.trimmingCharacters(in: .whitespaces) ?? ""
                let ndcMismatch  = !ndc.isEmpty && ndc != (existingTxn.drug?.ndc ?? "")
                let refilMismatch = !scannedRefil.isEmpty && scannedRefil != (existingTxn.refill_no ?? "")

                if ndcMismatch || refilMismatch {
                    print("[RxScan] Rx \(rxNo) mismatch — scanned ndc: \(ndc) vs stored: \(existingTxn.drug?.ndc ?? "nil"), scanned refil: \(scannedRefil) vs stored: \(existingTxn.refill_no ?? "nil")")
                    showToastMessage(text: L10n.BarcodeScan.rxNdcMismatch)
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
                    refil:    mappedData["REFILLNO"],
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
    /// If the Rx already exists locally, sets it as the selected transaction so the normal
    /// barcode-scan flow (scan stock bottle → NDC match → pill count) can continue.
    /// If the Rx is new, creates a transaction from the scanned data first.
    func proceedFromRxScan() async {
        guard let rxNo = scannedRxData?.rxNo, !rxNo.isEmpty else {
            print("[RxScan] proceedFromRxScan — no rxNo, cannot proceed")
            rxScanFailed = true
            return
        }

        guard let currentUser = userDataLocalStorage.fetchByUserId(userId) else {
            print("[RxScan] proceedFromRxScan — no current user")
            rxScanFailed = true
            return
        }

        guard let existingTxn = fetchRxTransaction(rxNo: rxNo, for: currentUser) else {
            print("[RxScan] proceedFromRxScan — Rx \(rxNo) not found in DB, creating new txn")
            await createTransactionFromRxScan()
            return
        }

        print("[RxScan] proceedFromRxScan — setting selectedTransaction txnId=\(existingTxn.txn_id) for rxNo=\(rxNo)")
        self.selectedTransaction  = existingTxn
        self.currentTransaction   = existingTxn
        self.fetchedRxTransaction = nil
        self.showRxFlowPopup      = false
    }

    /// Called when user taps PROCEED on the Rx popup.
    /// Updates the existing transaction found during parseScanData, or creates a new one
    /// if the Rx wasn't found in local DB.
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
            showToastMessage(text: L10n.BarcodeScan.invalidNdc)
            return
        }

        guard let rxNo, !rxNo.isEmpty else {
            print("[RxScan] No rxNo on scannedRxData — cannot proceed")
            showToastMessage(text: L10n.BarcodeScan.rxNotFound)
            return
        }

        let currentUser = userDataLocalStorage.fetchByUserId(userId)
        guard let currentUser else {
            print("[RxScan] No current user — cannot proceed")
            rxScanFailed = true
            return
        }

        guard let existingTxn = fetchRxTransaction(rxNo: rxNo, for: currentUser) else {
            guard AppStorageManager.shared.isStandalone else {
                print("[RxScan] Rx \(rxNo) not found in DB — isStandalone false, showing rx not found")
                showToastMessage(text: L10n.BarcodeScan.rxNotSentByPms)
                return
            }

            print("[RxScan] Rx \(rxNo) not found in DB — creating new txn")

            await createTransaction(
                drugId: drug.drug_id,
                isDispense: isDispense,
                drugName: rxData.drugName,
                rxNo: rxNo,
                bucketId: selectedBucket,
                refillNo: rxData.refil
            )

            await MainActor.run {
                guard let txnId = currentTransaction?.txn_id else { return }

                if targetQty > 0 {
                    transactionDAO.updateFromHL7Edit(
                        txnId: txnId,
                        drugId: drug.drug_id,
                        targetCount: targetQty,
                        priority: currentTransaction?.txn_priority,
                        refillNo: rxData.refil
                    )
                    self.currentTransaction = transactionDAO.fetchById(txnId)
                }

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
            priority: existingTxn.txn_priority,
            refillNo: rxData.refil
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
        guard let mapped = try? BarcodeFormatParser.mappedData(format: barcodeFormat, actualValue: value),
              !mapped.isEmpty else { return nil }

        let rxNo = mapped["RXNO"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rxNo.isEmpty ? nil : rxNo
    }

    // MARK: Barcode Format Match Check

    /// Builds a regex from the configured barcodeFormat and tests the scanned value against it.
    func matchesBarcodeFormat(_ value: String) -> Bool {
        BarcodeFormatParser.matches(value, format: AppStorageManager.shared.barcodeFormat)
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

}
