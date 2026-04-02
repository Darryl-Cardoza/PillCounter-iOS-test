//
//  PillScanViewModel+Stock.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/04/26.
//
import Foundation
import SwiftUI

extension PillScanViewModel {
    
    // Creating New batch in local database
    func createNewBatch() {
        let batchId = Int64(Date().timeIntervalSince1970 * 1000)

        let context = pillDataLocalStorage.mainThreadContext

        let batch = BatchCountEntity(context: context)
        batch.batch_id = batchId
        batch.start_date_time = String(batchId)
        batch.status = "partial"
        batch.is_deleted = false

        CoreDataManager.shared.save(context: context)

        currentBatchId = batchId
    }
    
    
    func createTxnForBatchFromScan(
        rawValue: String,
        countType: CountType,
        batchId: Int64 ,
        image: UIImage? = nil
    ) async {

        guard !rawValue.isEmpty else { return }

        //  Decode GS1 / barcode
        let decoded = decoder.decode(rawValue)
        let ndc = decoded.gtin ?? rawValue // fallback

        guard !ndc.isEmpty else {
            return
        }

        var drugIdToUse: Int64

        // Check local DB
        if let existingDrug = pillDataLocalStorage.getPillByNdc(by: ndc) {
            drugIdToUse = existingDrug.drug_id
            self.drugName = existingDrug.drug_name ?? ""

        } else {
            //  Create new drug
            drugIdToUse = generateUniqueDrugId()

            pillDataLocalStorage.saveManualPill(
                ndc: ndc,
                drugId: drugIdToUse,
                drugName: "Unknown Drug"
            )

            self.drugName = "Unknown Drug"
        }

        //  Create transaction WITH batch
        await createTransaction(
            drugId: drugIdToUse,
            countType: countType,
            barcodeImage: image,
            batchId: batchId
        )

        //  Update UI
        getAllTransactionDetailsOfTheCurrentTransaction()
        isDrugFound = true
    }
    
}
