//
//  PillScanViewModel+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import SwiftUI

extension PillScanViewModel {
    
    func createTxnForBatchFromScan(
        rawValueFromBarcodeOrQr:String?,
        ndc:String,
        drugName: String,
        quantity: Int32,
        countType: CountType,
        batchId: Int64,
        containerStatus: StockCountOptionContainerStatus,
        image: UIImage? = nil
    ) async {
        
        guard !ndc.isEmpty else {
            return
        }
        
        let decoded = decoder.decode(rawValueFromBarcodeOrQr ?? "")
        let gtin = decoded.gtin ?? ""

        var drugIdToUse: Int64

        //  Check local DB
        if let existingDrug = pillDataLocalStorage.getPillByNdc(by: ndc) {
            drugIdToUse = existingDrug.drug_id
        } else {
            // Create new drug
            drugIdToUse = generateUniqueDrugId()

            pillDataLocalStorage.saveManualPill(
                ndc: ndc,
                gtin: gtin,
                drugId: drugIdToUse,
                drugName: drugName
            )
        }

        // Create transaction (USE YOUR EXISTING FUNCTION )
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            barcodeImage: image,
            targetCount: quantity,
            drugName: self.drugName,
            batchId: batchId
        )

        //  Optional UI updates
        getAllTransactionDetailsOfTheCurrentTransaction()
        
        if let latest = pillDataLocalStorage.fetchPillCountTransactionByTransactionId(
            txnId: currentTransaction?.txn_id ?? 0
        ) {
            self.currentTransaction = latest
        }
        
        if containerStatus == .sealed{
            isNdcAdded = true
        }else{
            isDrugFound = true
        }
        
        print("Batch Txn Created → NDC:", ndc, "Batch:", batchId)
    }
    
    
    func reset(){
        isNdcAdded = false
    }
    
}
