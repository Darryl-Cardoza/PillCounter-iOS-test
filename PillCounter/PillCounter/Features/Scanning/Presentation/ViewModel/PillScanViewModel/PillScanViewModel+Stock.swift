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
        let existingTxn = transactionDAO
            .fetchByBatch(batchId: batchId)
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
            transactionDAO.updateCounts(
                txnId: txn.txn_id,
                bottleQty: containerStatus == .sealed ? 1 : nil,
                looseQty: containerStatus == .opened ? 0 : nil
            )

            // MARK: 3️⃣ Update current transaction (IMPORTANT FIX)
            if let updatedTxn = transactionDAO.fetchById(txn.txn_id) {
                self.currentTransaction = updatedTxn
            }

            // MARK: 4️⃣ UI Updates
            handlePostScanUI(containerStatus: containerStatus)
//            getAllTransactionDetailsOfTheCurrentTransaction()

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

                if let lookup = response.data?.scannedNdc?.lookupName,
                   !lookup.isEmpty {

                    let newId = generateUniqueDrugId()

                    drugMasterDAO.saveManual(
                        ndc: response.data?.scannedNdc?.packageNdc ?? ndc,
                        gtin: gtin,
                        drugId: newId,
                        drugName: lookup,
                        drugType: response.data?.scannedNdc?.deaSchedule,
                        packageQty: response.data?.scannedNdc?.safeQuantity ?? quantity
                    )

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
        let allTxns = transactionDAO
            .fetchByBatch(batchId: batchId)
            .filter { $0.is_deleted == false }

        // pick latest using txn_id (reliable)
        guard let latestTxn = allTxns.max(by: { $0.txn_id < $1.txn_id }) else {
            print("Failed to get latest txn")
            return
        }

        // MARK: 8️⃣ Set initial counts
        transactionDAO.updateCounts(
            txnId: latestTxn.txn_id,
            bottleQty: containerStatus == .sealed ? 1 : nil,
            looseQty: containerStatus == .opened ? 0 : nil
        )

        // MARK: 9️⃣ Update current txn
        if let updatedTxn = transactionDAO.fetchById(latestTxn.txn_id) {
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
            transactionDAO.updateCounts(
                txnId: txn.txn_id,
                bottleQty: Int32(currentBottle + 1),
                looseQty: Int32(currentLoose)
            )

            handlePostScanUI(containerStatus: containerStatus)


        case .opened:
            transactionDAO.updateCounts(
                txnId: txn.txn_id,
                bottleQty: Int32(currentBottle),
                looseQty: Int32(currentLoose + scannedQty)
            )
            handlePostScanUI(containerStatus: containerStatus)
        }
    }

    @MainActor
    func createBatchAndTxnsFromHL7Request(
        medications: [MedicationData],
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

            let ndc = med.drugCode 
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

                guard let lookup = response.data?.scannedNdc?.lookupName,
                      !lookup.isEmpty else {
                    continue
                }

                let newId = generateUniqueDrugId()

                drugMasterDAO.saveManual(
                    ndc: response.data?.scannedNdc?.packageNdc ?? "",
                    drugId: newId,
                    drugName: lookup,
                    drugType: response.data?.scannedNdc?.deaSchedule,
                    packageQty: response.data?.scannedNdc?.safeQuantity ?? 0
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

        let batchId = batch.batch_id

        // MARK: Create Transactions
        for item in resolvedItems {
            print("Resolved Items \(resolvedItems)")
            await createTransaction(
                drugId: item.drugId,
                countType: .REGULAR,
                isComingFromPms: true,
                targetCount: item.targetCount, // always 0 for request
                drugName: item.resolvedName,
                batchId: batchId,
                expirationDate: item.expiry,
                lotNumber: item.lot,
                bucketId: bucketId
            )
        }
    }
    
    func reset(){
        isNdcAdded = false
        isDrugFound = false
    }
}
