//
//  PillScanViewModel+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import SwiftUI

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

        // MARK: 1️⃣ Check existing txn
        let existingTxn = pillDataLocalStorage
            .fetchTransactionsByBatch(batchId: batchId)
            .first {
                $0.drug?.ndc == ndc &&
                $0.drug?.package_qty == quantity &&
                $0.is_deleted == false
            }

        if let txn = existingTxn {
            
            print(" Existing txn found → merging")

            // MARK: 2️⃣ Update counts
            pillDataLocalStorage.updateCounts(
                txnId: txn.txn_id,
                bottleQty: containerStatus == .sealed ? 1 : nil,
                looseQty: containerStatus == .opened ? quantity : nil
            )

            // MARK: 3️⃣ Update current transaction (IMPORTANT FIX)
            if let updatedTxn = pillDataLocalStorage
                .fetchPillCountTransactionByTransactionId(txnId: txn.txn_id) {
                self.currentTransaction = updatedTxn
            }

            // MARK: 4️⃣ UI Updates
            handlePostScanUI(containerStatus: containerStatus)
            getAllTransactionDetailsOfTheCurrentTransaction()

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
                    drugName: drugName
                )
                return newId
            }
        }()

        // MARK: 6️⃣ Create Transaction
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            barcodeImage: image,
            targetCount: quantity,
            drugName: drugName,
            batchId: batchId
        )

        // MARK: 7️⃣ Fetch newly created txn
        guard let newTxn = pillDataLocalStorage
            .fetchTransactionsByBatch(batchId: batchId)
            .last else { return }

        // MARK: 8️⃣ Set initial counts
        pillDataLocalStorage.updateCounts(
            txnId: newTxn.txn_id,
            bottleQty: containerStatus == .sealed ? 1 : nil,
            looseQty: containerStatus == .opened ? quantity : nil
        )

        // MARK: 9️⃣ Update current txn
        if let updatedTxn = pillDataLocalStorage
            .fetchPillCountTransactionByTransactionId(txnId: newTxn.txn_id) {
            self.currentTransaction = updatedTxn
        }

        // MARK: 🔟 UI Updates
        handlePostScanUI(containerStatus: containerStatus)
        getAllTransactionDetailsOfTheCurrentTransaction()

        print("🆕 Batch Txn Created → NDC:", ndc, "Batch:", batchId)
    }
    private func handlePostScanUI(containerStatus: StockCountOptionContainerStatus) {
        if containerStatus == .sealed {
            isNdcAdded = true
        } else {
            isDrugFound = true
        }
    }
    
    func reset(){
        isNdcAdded = false
    }
    
}
