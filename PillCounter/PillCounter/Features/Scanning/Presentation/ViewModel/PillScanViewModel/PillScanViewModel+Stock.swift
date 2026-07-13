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
        countType: CountType,
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

    /// Called after open pill counting completes. Sets loose_qty to the final counted value
    /// (absolute, not additive) on the specific opened BottleInfoEntity row created by the scan.
    func updateOpenPillCount(bottleId: Int64, loosePillCount: Int) {
        bottleInfoDAO.updateOpenedBottleLooseQty(bottleId: bottleId, looseQty: Int32(loosePillCount))
        if let stockTxnId = currentStockTxn?.stock_txn_id, let updated = stockTxnDAO.fetchById(stockTxnId) {
            self.currentStockTxn = updated
        }
        self.currentBottleInfo = bottleInfoDAO.fetchById(bottleId)
    }

    func formatExpiry(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        return formatter.string(from: date)
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
        scannedQty: Int
    ) {
        switch containerStatus {
        case .sealed:
            // additive-by-one: sealed row's bottle_qty += 1
            let existingQty = bottleInfoDAO
                .fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
                .first { $0.bottle_qty > 0 && $0.loose_qty == 0 }?
                .bottle_qty ?? 0
            self.currentBottleInfo = bottleInfoDAO.setSealedBottleQty(
                stockTxnId: stockTxn.stock_txn_id,
                bottleQty: existingQty + 1,
                lotNo: nil,
                expNo: nil
            )
            handlePostScanUI(containerStatus: containerStatus)

        case .opened:
            // every opened scan is a new bottle row
            self.currentBottleInfo = bottleInfoDAO.addOpenedBottle(
                stockTxnId: stockTxn.stock_txn_id,
                looseQty: Int32(scannedQty),
                lotNo: nil,
                expNo: nil,
                serialNo: nil
            )
            handlePostScanUI(containerStatus: containerStatus)
        }
        self.currentStockTxn = stockTxnDAO.fetchById(stockTxn.stock_txn_id)
    }

    @MainActor
    func createBatchAndTxnsFromHL7Request(
        medications: [RXESegment],
        requestId : String,
        bucketId: String?
    ) async {

        print("Requset Comes here")
        guard !medications.isEmpty else {
            print("Meidcation is empty")
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

        for med in medications {

            let ndc = med.giveCode
            let lot = ""          // RXE usually doesn't send lot
            let expiry = ""       // RXE usually doesn't s expiry
            let targetCount: Int32 = 0 // request → no quantity

            guard !ndc.isEmpty else { continue }

            // MARK: Local DB check
            if let existing = drugMasterDAO.fetchByNdc(ndc) {
                guard let localName = existing.drug_name, !localName.isEmpty else {
                    continue
                }

                resolvedItems.append(
                    ResolvedItem(
                        ndc: ndc,
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
                      !lookup.isEmpty else {
                    continue
                }

                let newId = generateUniqueDrugId()

                drugMasterDAO.upsertFromApi(
                    ndc:    scannedNdc.drugCode ?? "",
                    drugId: newId,
                    drug:   scannedNdc
                )

                resolvedItems.append(
                    ResolvedItem(
                        ndc: ndc,
                        drugId: newId,
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
