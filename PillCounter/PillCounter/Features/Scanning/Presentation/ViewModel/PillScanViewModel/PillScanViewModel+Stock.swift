//
//  PillScanViewModel+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import SwiftUI
import Hl7Core

extension PillScanViewModel {
    
    func createTxnForBatchFromScan(
        rawValueFromBarcodeOrQr: String?,
        ndc: String,
        drugName: String,
        quantity: Int32,
        batchId: Int64,
        containerStatus: StockCountOptionContainerStatus,
        bottleCount: Int = 1,
        image: UIImage? = nil
    ) async {

        guard !ndc.isEmpty else { return }

        let decoded = decoder.decode(rawValueFromBarcodeOrQr ?? "")
        let gtin = decoded.gtin ?? ""
        let expiryString = formatExpiry(decoded.expirationDate)

        // MARK: 1️⃣ Resolve/create the StockTxnEntity for this NDC in this batch
        guard let batch = batchDAO.fetchById(batchId) else { return }

        if let existingStockTxn = stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: ndc) {

            print("Existing stock txn found → merging")

            // MARK: 2️⃣ Write the bottle info (absolute-set for sealed, new row for opened)
            switch containerStatus {
            case .sealed:
                self.currentBottleInfo = bottleInfoDAO.setSealedBottleQty(
                    stockTxnId: existingStockTxn.stock_txn_id,
                    bottleQty: Int32(bottleCount),
                    lotNo: decoded.lotNumber,
                    expNo: expiryString
                )
            case .opened:
                self.currentBottleInfo = bottleInfoDAO.addOpenedBottle(
                    stockTxnId: existingStockTxn.stock_txn_id,
                    looseQty: 0,
                    lotNo: decoded.lotNumber,
                    expNo: expiryString,
                    serialNo: decoded.serialNumber
                )
            }

            // MARK: 3️⃣ Update current stock txn
            self.currentStockTxn = stockTxnDAO.fetchById(existingStockTxn.stock_txn_id)

            // MARK: 4️⃣ UI Updates
            handlePostScanUI(containerStatus: containerStatus)

            return
        }

        // MARK: 5️⃣ Create / Get Drug
        var drugIdToUse: Int64

        // MARK: Check by NDC
        if let existingDrug = drugMasterDAO.fetchByNdc(ndc) {

            if (existingDrug.gtin ?? "").isEmpty, !gtin.isEmpty {
                existingDrug.gtin = gtin
                CoreDataManager.shared.save(context: CoreDataManager.shared.context)
                Log("Updated GTIN for existing drug → \(ndc)")
            }

            drugIdToUse = existingDrug.drug_id
        }

        // MARK: Check by GTIN
        else if !gtin.isEmpty,
                let existingByGtin = drugMasterDAO.fetchByGtin(gtin) {

            drugIdToUse = existingByGtin.drug_id
        }

        // MARK: API fallback
        else {
            let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)

            do {
                let response = try await controlledRepo.getControlledDrugInfo(
                    ndcValidationRequest: request
                )

                if let scannedNdc = response.data?.scannedNdc,
                   let lookup = scannedNdc.lookupName,
                   !lookup.isEmpty {

                    let newId = generateUniqueDrugId()

                    drugMasterDAO.upsertFromApi(
                        ndc:    scannedNdc.drugCode ?? ndc,
                        drugId: newId,
                        drug:   scannedNdc,
                        gtin:   gtin
                    )
                    // Fall back to the scanned bottle quantity when the API gave no package size.
                    if scannedNdc.safeQuantity == 0 {
                        drugMasterDAO.update(drugId: newId, packageQty: quantity)
                    }

                    drugIdToUse = newId
                } else {
                    throw NSError(domain: "HL7", code: -1)
                }

            } catch {

                Log("API failed → fallback create")

                let newId = generateUniqueDrugId()

                drugMasterDAO.saveManual(
                    ndc: ndc,
                    gtin: gtin,
                    drugId: newId,
                    drugName: drugName,
                    packageQty: quantity
                )

                drugIdToUse = newId
            }
        }

        // MARK: 6️⃣ Create StockTxnEntity for this NDC in this batch
        let stockTxn = stockTxnDAO.fetchOrCreate(batch: batch, drugId: drugIdToUse, bucketId: batch.bucket_id)

        // MARK: 7️⃣ Set initial bottle info (absolute-set for sealed, new row for opened)
        switch containerStatus {
        case .sealed:
            self.currentBottleInfo = bottleInfoDAO.setSealedBottleQty(
                stockTxnId: stockTxn.stock_txn_id,
                bottleQty: Int32(bottleCount),
                lotNo: decoded.lotNumber,
                expNo: expiryString
            )
        case .opened:
            self.currentBottleInfo = bottleInfoDAO.addOpenedBottle(
                stockTxnId: stockTxn.stock_txn_id,
                looseQty: 0,
                lotNo: decoded.lotNumber,
                expNo: expiryString,
                serialNo: decoded.serialNumber
            )
        }

        // MARK: 8️⃣ Update current stock txn
        self.currentStockTxn = stockTxnDAO.fetchById(stockTxn.stock_txn_id)
        print("New stock txn set:", stockTxn.stock_txn_id)

        // MARK: 9️⃣ UI Updates
        handlePostScanUI(containerStatus: containerStatus)

        print("Batch Stock Txn Created → NDC:", ndc, "Batch:", batchId)
    }

    /// Open-pill flow: resolve/create the drug + StockTxnEntity for the scanned NDC, but do
    /// NOT write a BottleInfoEntity row yet — the user still has to count the loose pills and
    /// tap Proceed. Lot/expiry/serial from the scan are stashed and applied when the row is
    /// finally created in `createOpenedBottleFromPendingScan`.
    func resolveStockTxnForOpenPillScan(
        rawValueFromBarcodeOrQr: String?,
        ndc: String,
        drugName: String,
        quantity: Int32,
        batchId: Int64?
    ) async {
        guard !ndc.isEmpty else { return }

        let decoded = decoder.decode(rawValueFromBarcodeOrQr ?? "")
        let gtin = decoded.gtin ?? ""
        let expiryString = formatExpiry(decoded.expirationDate)

        pendingOpenBottleLot = decoded.lotNumber
        pendingOpenBottleExpiry = expiryString
        pendingOpenBottleSerial = decoded.serialNumber

        // If a batch already exists and already has a StockTxn for this NDC, reuse it —
        // no new persistence needed for an already-tracked NDC.
        if let batchId, let existingStockTxn = stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: ndc) {
            self.currentStockTxn = existingStockTxn
            self.currentBottleInfo = nil
            self.pendingOpenBottleDrug = existingStockTxn.drug
            self.pendingOpenBottleDrugId = existingStockTxn.drug_id
            handlePostScanUI(containerStatus: .opened)
            return
        }

        var drugIdToUse: Int64

        if let existingDrug = drugMasterDAO.fetchByNdc(ndc) {
            if (existingDrug.gtin ?? "").isEmpty, !gtin.isEmpty {
                existingDrug.gtin = gtin
                CoreDataManager.shared.save(context: CoreDataManager.shared.context)
                Log("Updated GTIN for existing drug → \(ndc)")
            }
            drugIdToUse = existingDrug.drug_id
        } else if !gtin.isEmpty, let existingByGtin = drugMasterDAO.fetchByGtin(gtin) {
            drugIdToUse = existingByGtin.drug_id
        } else {
            let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)
            do {
                let response = try await controlledRepo.getControlledDrugInfo(
                    ndcValidationRequest: request
                )
                if let scannedNdc = response.data?.scannedNdc,
                   let lookup = scannedNdc.lookupName,
                   !lookup.isEmpty {
                    let newId = generateUniqueDrugId()
                    drugMasterDAO.upsertFromApi(
                        ndc:    scannedNdc.drugCode ?? ndc,
                        drugId: newId,
                        drug:   scannedNdc,
                        gtin:   gtin
                    )
                    if scannedNdc.safeQuantity == 0 {
                        drugMasterDAO.update(drugId: newId, packageQty: quantity)
                    }
                    drugIdToUse = newId
                } else {
                    throw NSError(domain: "HL7", code: -1)
                }
            } catch {
                Log("API failed → fallback create")
                let newId = generateUniqueDrugId()
                drugMasterDAO.saveManual(
                    ndc: ndc,
                    gtin: gtin,
                    drugId: newId,
                    drugName: drugName,
                    packageQty: quantity
                )
                drugIdToUse = newId
            }
        }

        // Drug catalog resolution is safe to persist eagerly (it's shared reference data,
        // not batch/count data). The StockTxnEntity/BottleInfoEntity — the actual count —
        // is NOT created here. It's created only on Proceed (createOpenedBottleFromPendingScan),
        // so backing out or killing the app mid-scan leaves no phantom 0-count NDC behind.
        self.currentStockTxn = nil
        self.currentBottleInfo = nil
        self.pendingOpenBottleDrug = DrugCatalogStore.shared.fetchById(drugIdToUse)
        self.pendingOpenBottleDrugId = drugIdToUse

        handlePostScanUI(containerStatus: .opened)
    }

    /// Called after open pill counting completes (Proceed) — creates the batch (if this is
    /// the very first count of the session), the StockTxnEntity, and the BottleInfoEntity row,
    /// all at once, using the drug/lot/expiry/serial stashed at scan time and the final
    /// counted qty. Nothing is persisted before this point.
    func createOpenedBottleFromPendingScan(existingBatch: BatchCountEntity?, bucketId: String?, loosePillCount: Int) {
        guard let drugId = pendingOpenBottleDrugId else { return }

        let batch: BatchCountEntity?
        if let existingBatch {
            batch = existingBatch
        } else {
            batch = batchDAO.create(bucketId: bucketId ?? "")
        }
        guard let batch else { return }

        let stockTxn = stockTxnDAO.fetchOrCreate(batch: batch, drugId: drugId, bucketId: batch.bucket_id)
        self.currentBottleInfo = bottleInfoDAO.addOpenedBottle(
            stockTxnId: stockTxn.stock_txn_id,
            looseQty: Int32(loosePillCount),
            lotNo: pendingOpenBottleLot,
            expNo: pendingOpenBottleExpiry,
            serialNo: pendingOpenBottleSerial
        )
        self.currentStockTxn = stockTxnDAO.fetchById(stockTxn.stock_txn_id)

        pendingOpenBottleLot = nil
        pendingOpenBottleExpiry = nil
        pendingOpenBottleSerial = nil
        pendingOpenBottleDrug = nil
        pendingOpenBottleDrugId = nil
    }

    func formatExpiry(_ date: Date?) -> String? {
        DateUtils.formatExpiryYYYYMMdd(date)
    }

    private func handlePostScanUI(containerStatus: StockCountOptionContainerStatus) {
        if containerStatus == .sealed {
            isNdcAdded = true
        } else {
            isDrugFound = true
        }
    }
    
    func updatePmsTxnCount(
        stockTxn: StockTxnEntity,
        containerStatus: StockCountOptionContainerStatus,
        scannedQty: Int,
        lotNo: String? = nil,
        expNo: String? = nil
    ) {
        switch containerStatus {
        case .sealed:
            // Fetch-or-create by the scanned lot+exp, same key every other sealed write
            // site uses — no PMS-specific single-row exception.
            let existingQty = bottleInfoDAO.sealedBottleQty(
                stockTxnId: stockTxn.stock_txn_id, lotNo: lotNo, expNo: expNo
            )
            self.currentBottleInfo = bottleInfoDAO.setSealedBottleQty(
                stockTxnId: stockTxn.stock_txn_id,
                bottleQty: existingQty + 1,
                lotNo: lotNo,
                expNo: expNo
            )
            handlePostScanUI(containerStatus: containerStatus)

        case .opened:
            // every opened scan is a new bottle row
            self.currentBottleInfo = bottleInfoDAO.addOpenedBottle(
                stockTxnId: stockTxn.stock_txn_id,
                looseQty: Int32(scannedQty),
                lotNo: lotNo,
                expNo: expNo,
                serialNo: nil
            )
            handlePostScanUI(containerStatus: containerStatus)
        }
        self.currentStockTxn = stockTxnDAO.fetchById(stockTxn.stock_txn_id)
    }

    @MainActor
    func createBatchAndTxnsFromHL7Request(
        inventoryItems: [INVSegment],
        requestId : String,
        bucketId: String?
    ) async {

        print("Requset Comes here")
        guard !inventoryItems.isEmpty else {
            print("Inventory items empty")
            return
        }

        struct ResolvedItem {
            let ndc: String
            let drugId: Int64
            let resolvedName: String
            let lot: String
            let expiry: String
            let targetCount: Int32
        }

        var resolvedItems: [ResolvedItem] = []

        for item in inventoryItems {

            // INVSegment's named substanceCode/substanceName do NOT bind to
            // INV-1 (confirmed live: substanceCode returned "A", INV-2's status
            // code, for `INV|76385-118-01^Etodolac^L|A^Active^HL70383|...`).
            // Read INV-1 directly by field/component position instead — exact
            // per the HL7 wire spec, no dependency on the typed property's
            // (apparently wrong) binding in this build.
            let ndc = item.raw.componentValue(n: 1, c: 1)
            let lot = item.lotNumber
            let expiry = item.expirationDate
            let targetCount: Int32 = 0 // request → no quantity

            guard !ndc.isEmpty else { continue }

            // MARK: Local DB check
            // Digits-only match — PMS sends NDC in whatever format that run
            // uses (with/without hyphens, 10 or 11 digit), while the stored
            // row is keyed on the API's own normalized format. Exact-string
            // fetchByNdc misses these and re-hits the API for a known drug.
            if let existing = drugMasterDAO.fetchByNdcDigitsOnly(ndc) {
                guard let localName = existing.drug_name, !localName.isEmpty else {
                    continue
                }

                // Stored NDC, not the raw PMS one — keeps the transaction's
                // NDC matching drugMasterDAO's key regardless of which format
                // this PMS run happened to send.
                resolvedItems.append(
                    ResolvedItem(
                        ndc: existing.ndc ?? ndc,
                        drugId: existing.drug_id,
                        resolvedName: localName,
                        lot: lot,
                        expiry: expiry,
                        targetCount: targetCount
                    )
                )
                continue
            }

            // MARK: API fallback
            let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)

            do {
                let response = try await controlledRepo.getControlledDrugInfo(
                    ndcValidationRequest: request
                )

                guard let scannedNdc = response.data?.scannedNdc,
                      let lookup = scannedNdc.lookupName,
                      !lookup.isEmpty,
                      let apiNdc = scannedNdc.drugCode,
                      !apiNdc.isEmpty else {
                    // Invalid/unknown NDC (PMS-sent NDC not found, or API returned
                    // no usable drug_code/lookup_name) — discard entirely, never
                    // create a transaction against an empty/unresolved NDC.
                    continue
                }

                // upsertFromApi/fetchOrCreateNoWrap looks up by NDC and returns
                // the EXISTING row's drug_id if apiNdc was already saved by a
                // prior request — generateUniqueDrugId()'s newId is only used
                // when the row is newly created. Must read back the id that was
                // actually persisted, or StockTxnStore.fetchOrCreate's later
                // fetchById(drugId) misses, entity.drug stays nil, and the row
                // renders "Unknown" (and NDC-collides into the empty group).
                let newId = generateUniqueDrugId()

                guard let persisted = drugMasterDAO.upsertFromApi(
                    ndc:    apiNdc,
                    drugId: newId,
                    drug:   scannedNdc
                ) else {
                    continue
                }

                // Always the API's NDC (11-digit, normalized) — never the raw
                // PMS-sent one (may be 10-digit/differently formatted), so the
                // stored drug row and the transaction's NDC always match and
                // later scan validation doesn't mismatch on digit count.
                resolvedItems.append(
                    ResolvedItem(
                        ndc: apiNdc,
                        drugId: persisted.drug_id,
                        resolvedName: lookup,
                        lot: lot,
                        expiry: expiry,
                        targetCount: targetCount
                    )
                )

            } catch {
                continue
            }
        }

        guard !resolvedItems.isEmpty else { return }

        // MARK: Create Batch
        guard let batch = batchDAO.create(
            bucketId: bucketId ?? "",
            requestId: requestId
        ) else { return }

        // MARK: Create StockTxnEntity rows (one per requested NDC, no bottle data yet)
        for item in resolvedItems {
            print("Resolved Items \(resolvedItems)")
            stockTxnDAO.fetchOrCreate(batch: batch, drugId: item.drugId, bucketId: bucketId)
        }
    }
    
    func reset(){
        isNdcAdded = false
        isDrugFound = false
    }
}
