//
//  PillScanViewModel+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import SwiftUI
import ComposeApp

extension PillScanViewModel {
    
    func createTxnForBatchFromScan(
        rawValueFromBarcodeOrQr: String?,
        ndc: String,
        drugName: String,
        quantity: Int32,
        countType: CountType,
        batchId: Int64,
        containerStatus: StockCountOptionContainerStatus,
        image: UIImage? = nil
    ) async {
                
        guard !ndc.isEmpty else { return }
        
        let decoded = decoder.decode(rawValueFromBarcodeOrQr ?? "")
        let gtin = decoded.gtin ?? ""
        let expiryString = formatExpiry(decoded.expirationDate)
    

        // MARK: 1️⃣ Check existing txn
        let existingTxn = pillDataLocalStorage
            .fetchTransactionsByBatch(batchId: batchId)
            .first {
                $0.drug?.ndc == ndc &&
                $0.drug?.package_qty == quantity &&
                $0.is_deleted == false &&
                $0.expiry == expiryString &&
                $0.lot_no == decoded.lotNumber
            }

        if let txn = existingTxn {
            
            print("Existing txn found → merging")

            // MARK: 2️⃣ Update counts
            pillDataLocalStorage.updateCounts(
                txnId: txn.txn_id,
                bottleQty: containerStatus == .sealed ? 1 : nil,
                looseQty: containerStatus == .opened ? 0 : nil
            )

            // MARK: 3️⃣ Update current transaction (IMPORTANT FIX)
            if let updatedTxn = pillDataLocalStorage
                .fetchPillCountTransactionByTransactionId(txnId: txn.txn_id) {
                self.currentTransaction = updatedTxn
            }

            // MARK: 4️⃣ UI Updates
            handlePostScanUI(containerStatus: containerStatus)
//            getAllTransactionDetailsOfTheCurrentTransaction()

            return
        }

        // MARK: 5️⃣ Create / Get Drug
        let drugIdToUse: Int64 = {
            if let existingDrug = pillDataLocalStorage.getPillByNdc(by: ndc) {
                return existingDrug.drug_id
            } else {
                let newId = generateUniqueDrugId()
                pillDataLocalStorage.saveManualPill(
                    ndc: ndc,
                    gtin: gtin,
                    drugId: newId,
                    drugName: drugName,
                    packageQty: quantity
                )
                return newId
            }
        }()

        // MARK: 6️⃣ Create Transaction
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            barcodeImage: image,
            drugName: drugName,
            batchId: batchId,
            expirationDate: expiryString,
            lotNumber: decoded.lotNumber
        )

        // MARK: 7️⃣ Fetch newly created txn
        let allTxns = pillDataLocalStorage
            .fetchTransactionsByBatch(batchId: batchId)
            .filter { $0.is_deleted == false }

        // pick latest using txn_id (reliable)
        guard let latestTxn = allTxns.max(by: { $0.txn_id < $1.txn_id }) else {
            print("Failed to get latest txn")
            return
        }

        // MARK: 8️⃣ Set initial counts
        pillDataLocalStorage.updateCounts(
            txnId: latestTxn.txn_id,
            bottleQty: containerStatus == .sealed ? 1 : nil,
            looseQty: containerStatus == .opened ? 0 : nil
        )

        // MARK: 9️⃣ Update current txn
        if let updatedTxn = pillDataLocalStorage
            .fetchPillCountTransactionByTransactionId(txnId: latestTxn.txn_id) {

            self.currentTransaction = updatedTxn

            print("New txn set:", updatedTxn.txn_id)
        } else {
            print("New txn not found")
        }

        // MARK: 🔟 UI Updates
        handlePostScanUI(containerStatus: containerStatus)
//        getAllTransactionDetailsOfTheCurrentTransaction()

        print("Batch Txn Created → NDC:", ndc, "Batch:", batchId)
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
        txn: PillCountTransactionEntity,
        containerStatus: StockCountOptionContainerStatus,
        scannedQty: Int
    ) {
        
        let currentBottle = Int(txn.bottle_qty)
        let currentLoose = Int(txn.loose_qty)
        
        switch containerStatus {
            
        case .sealed:
            // Add full bottle
//            updateCounts(
//                txnId: txn.txn_id,
//                bottleQty: currentBottle + 1,
//                looseQty: currentLoose
//            )
            
            pillDataLocalStorage.updateCounts(
                txnId: txn.txn_id,
                bottleQty: Int32(currentBottle + 1),
                looseQty: Int32(currentLoose)
            )
            
            handlePostScanUI(containerStatus: containerStatus)

            
        case .opened:
            // Add loose pills
//            updateCounts(
//                txnId: txn.txn_id,
//                bottleQty: currentBottle,
//                looseQty: currentLoose + scannedQty
//            )
            pillDataLocalStorage.updateCounts(
                txnId: txn.txn_id,
                bottleQty: Int32(currentBottle),
                looseQty:Int32(currentLoose + scannedQty)
            )
            handlePostScanUI(containerStatus: containerStatus)
        }
    }
    
    
    @MainActor
    func createBatchAndTxnsFromHL7(
        inventoryItems: [InventoryItemData],
        countType: CountType,
        rxNo: String?,
        bucketId: String?
    ) async {

        guard !inventoryItems.isEmpty else { return }

        // MARK: 1️⃣ Pre-resolve all drugs BEFORE creating batch
        struct ResolvedItem {
            let ndc: String
            let drugId: Int64
            let resolvedName: String
            let lot: String
            let expiry: String
            let targetCount: Int32
        }

        var resolvedItems: [ResolvedItem] = []

        for (_, _inventory) in inventoryItems.enumerated() {

            let ndc         = _inventory.substanceStatusCode ?? ""
            let lot         = _inventory.lotNumber ?? ""
            let expiry      = _inventory.expirationDateTime ?? ""
            let targetCount = Int32(_inventory.currentQuantity ?? "0") ?? 0

            guard !ndc.isEmpty else {
                continue
            }

            // MARK: Local DB check
            if let existing = pillDataLocalStorage.getPillByNdc(by: ndc) {
                guard let localName = existing.drug_name, !localName.isEmpty else {
                    continue
                }
                resolvedItems.append(ResolvedItem(
                    ndc: ndc,
                    drugId: existing.drug_id,
                    resolvedName: localName,   // ← local only, no rawName fallback
                    lot: lot,
                    expiry: expiry,
                    targetCount: targetCount
                ))
                continue
            }

            // MARK: API check
            let request = NdcValidationRequest(targetNdc: ndc, scannedNdc: ndc)

            do {
                let response = try await controlledRepo.getControlledDrugInfo(
                    ndcValidationRequest: request
                )

                guard let lookup = response.data?.scannedNdc?.lookupName,
                      !lookup.isEmpty else {
                    continue
                }

                let newId = generateUniqueDrugId()
                pillDataLocalStorage.saveManualPill(
                    ndc: response.data?.scannedNdc?.packageNdc ?? "",
                    drugId: newId,
                    drugName: lookup,
                    packageQty: response.data?.scannedNdc?.safeQuantity ?? 0
                )

                resolvedItems.append(
                ResolvedItem(
                    ndc: response.data?.scannedNdc?.packageNdc ?? "",
                    drugId: newId,
                    resolvedName: lookup,
                    lot: lot,
                    expiry: expiry,
                    targetCount: 0
                ))

            } catch {
                continue
            }
        }

        // MARK: 2️⃣ Guard — only proceed if at least one item resolved
        guard !resolvedItems.isEmpty else {
            return
        }

        // MARK: 3️⃣ Create ONE Batch (only now, after validation)
        guard let batch = pillDataLocalStorage.createBatch(
            bucketId: bucketId ?? "",
            isFromPms: true
        ) else {
            return
        }

        let batchId = batch.batch_id

        // MARK: 4️⃣ Create transactions only for resolved items
        for (_, item) in resolvedItems.enumerated() {
            await createTransaction(
                drugId: item.drugId,
                countType: countType,
                isComingFromPms: true,
                targetCount: item.targetCount,
                drugName: item.resolvedName,
                batchId: batchId,
                expirationDate: item.expiry,
                lotNumber: item.lot,
                rxNo: rxNo,
                bucketId: bucketId
            )
        }
    }
    
    func reset(){
        isNdcAdded = false
        isDrugFound = false
    }
}
