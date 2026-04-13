//
//  StockCountViewModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import Foundation
import SwiftUI

@MainActor
class StockCountViewModel: ObservableObject {
    
    let pillDataLocalStorage = PillsDataLocalStorage.shared
    let userDataLocalStorage = UserLocalDataSource.shared
    let decoder = BarcodeAndQRDecoder()
    let controlledRepo  = ControlledRepository.shared

    var currentUserId: String? {
        // Assuming there's a way to get the current userId, you can set this accordingly in your app
        // For now, returning a sample or nil
        return nil
    }
    
    // MARK: Stock Count State
    @Published var groupedTransactions:[GroupedTransaction] = []
    @Published var regularCountTransactions: [PillCountTransactionEntity] = []

    
    @Published var currentBatch: BatchCountEntity?
    @Published var totalBatchCount: Int = 0
    @Published var totalNdcRequests: Int = 0
    @Published var scannedDrugData: ScannedDrugData?
    @Published var showStockCountScannedDetails: Bool = false
    @Published var showScanError: Bool = false
    @Published var isLoading:Bool = false
    
    @Published var barcodeNotFound: Bool = false
    @Published var showScannedNdcDoesNotMatch: Bool = false
    
    @Published var batchNdcSet: Set<String> = []
    @Published var selectedTransaction: PillCountTransactionEntity? = nil
    
    // Creating New Batch in Database
    func createNewBatch(bucketId: String) {
        if let batch = pillDataLocalStorage.createBatch(bucketId: bucketId, isFromPms: false) {
            currentBatch = batch
            updateBatchCount()
        }
    }
    
    // Load NDC requests
    func getAllPartialTransactions(countType: CountType, userId: String) async {
        guard let user = userDataLocalStorage.getUserByUserId(by: userId) else {
            self.regularCountTransactions = []
            return
        }
        self.regularCountTransactions =
        pillDataLocalStorage.fetchAllTransactionFixedOrRegularPartialFromPms(
            for: user, countType: countType)

        self.totalNdcRequests = 0

        for transaction in regularCountTransactions {
            let total = pillDataLocalStorage.getTheCountedNumberOfPillsForTheTransaction(
                for: transaction.txn_id)
            self.totalNdcRequests = total
        }
    }
    
    // Loading all batches from database
    func loadBatches() -> [BatchCountEntity] {
        return pillDataLocalStorage.fetchAllBatches()
    }

    func loadTransactions() {
        guard let batchId = currentBatch?.batch_id else {
            self.groupedTransactions = []
            return
        }

        let txns = pillDataLocalStorage.fetchTransactionsByBatch(batchId: batchId)
        
        self.groupedTransactions = mapGroupedTransactions(txns: txns)
        batchNdcSet = Set(txns.compactMap { $0.drug?.ndc })
    }
    
    
    // MARK: Scan Stock count Barcode
    func getScannedDrugData(
        rawValue: String
    ) async {
        let decoded = decoder.decode(rawValue)
        let gtin = decoded.gtin ?? ""
    
        await fetchDrugDataOnly(gtin: gtin)
    }
    
    
    private func fetchDrugDataOnly(gtin: String) async {
        guard !gtin.isEmpty else {
            showScanError = true
            return
        }

        showStockCountScannedDetails = false
        showScanError = false
        isLoading = true

        // 1. LOCAL DB
        if let localDrug = pillDataLocalStorage.getPillByGtin(by: gtin) {
            let ndc = localDrug.ndc ?? ""

            if currentBatch?.is_from_pms == true {
                if !batchNdcSet.contains(ndc) {
                    isLoading = false
                    showStockCountScannedDetails = false
                    showScannedNdcDoesNotMatch = true
                    return
                }
            }
            
            scannedDrugData = ScannedDrugData(
                drugName: localDrug.drug_name ?? "",
                ndc: localDrug.ndc ?? "",
                gtin: localDrug.gtin ?? "",
                quantity: localDrug.package_qty
            )

            isLoading = false
            showStockCountScannedDetails = true
            print("Fetched response from Local |()")
            return
        }

        let request = NdcValidationRequest(
            targetNdc: gtin,
            scannedNdc: gtin
        )

        // 2. API CALL
        do {
            let response = try await controlledRepo
                .getControlledDrugInfo(ndcValidationRequest: request)

            let ndc = response.data?.scannedNdc?.packageNdc ?? ""

            if currentBatch?.is_from_pms == true {
                if !batchNdcSet.contains(ndc) {
                    isLoading = false
                    showStockCountScannedDetails = false
                    showScannedNdcDoesNotMatch = true
                    print("❌ NDC not part of PMS batch\(ndc) \(batchNdcSet)")
                    return
                }
            }

            scannedDrugData = ScannedDrugData(
                drugName: response.data?.scannedNdc?.lookupName ?? "",
                ndc: response.data?.scannedNdc?.packageNdc ?? "",
                gtin:response.data?.scannedNdc?.packageNdc ?? "",
                quantity: response.data?.scannedNdc?.safeQuantity ?? 0
            )

            isLoading = false
            // just compare here and add condition here also
            showStockCountScannedDetails = true
            print("Fetched response from API\(response)")
        } catch {
            scannedDrugData = nil
            isLoading = false
            showScanError = true
            barcodeNotFound = true
        }
    }
    
    // Update Count in Txn
    func updateCounts(
        txnId: Int64?,
        bottleQty: Int? = nil,
        looseQty: Int? = nil
    ) {
        let bottle = bottleQty.map { Int32($0) }
        let loose = looseQty.map { Int32($0) }

        pillDataLocalStorage.updateCounts(
            txnId: txnId,
            bottleQty: bottle,
            looseQty: loose
        )
        loadTransactions()
    }
    
    
    func completeBatch(batchId: Int64) {
        let txns = pillDataLocalStorage.fetchTransactionsByBatch(batchId: batchId)

        for txn in txns {
            pillDataLocalStorage.updateTransactionStatus(
                txnId: txn.txn_id,
                newStatus: .COMPLETED
            )
        }

        pillDataLocalStorage.updateBatchStatus(
            batchId: batchId,
            status: "completed"
        )

        loadTransactions()

        print("Batch \(batchId) marked as COMPLETED")
    }
    
    
    // Formatting Date
    func formatDate(_ timestamp: Int64?) -> String {
        guard let timestamp else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM • hh:mm a"
        return formatter.string(from: date)
    }
    
    
    // Mapper function
    func mapGroupedTransactions(txns: [PillCountTransactionEntity]) -> [GroupedTransaction] {
        
        // 1. Group by NDC
        let groupedByNdc = Dictionary(grouping: txns) { $0.drug?.ndc ?? "" }
        
        return groupedByNdc.map { (ndc, txnList) in
            
            let drugName = txnList.first?.drug?.drug_name ?? "Unknown"
            
            // 2. Group by LOT + EXPIRY
            let lotGrouped = Dictionary(grouping: txnList) {
                "\($0.lot_no ?? "-")|\($0.expiry ?? "-")"
            }
            
            var lotDetails: [LotDetail] = []
            var totalSealed: Int32 = 0
            var totalOpen: Int32 = 0
            
            for (_, lotTxns) in lotGrouped {
                
                let lot = lotTxns.first?.lot_no ?? "-"
                let expiry = lotTxns.first?.expiry ?? "-"
                
                let sealed = lotTxns.reduce(0) {
                    $0 + ($1.bottle_qty * ($1.drug?.package_qty ?? 0))
                }
                
                let open = lotTxns.reduce(0) {
                    $0 + $1.loose_qty
                }
                
                totalSealed += sealed
                totalOpen += open
                
                lotDetails.append(
                    LotDetail(
                        lot: lot,
                        expiry: expiry,
                        sealedQty: sealed,
                        openQty: open
                    )
                )
            }
            
            return GroupedTransaction(
                ndc: ndc,
                drugName: drugName,
                total: totalSealed + totalOpen,
                sealedBottles: totalSealed,
                openPills: totalOpen,
                lotDetails: lotDetails
            )
        }
    }
    
    
    // Get Total Count of batches
    func updateBatchCount() {
        let batches = pillDataLocalStorage.fetchAllBatches()
        totalBatchCount = batches.count
    }
    
    // Get Count Data
    func getCountData(){
        updateBatchCount()
    }
    
    
    func reset(){
        scannedDrugData = nil
        showStockCountScannedDetails = false
        showScanError = false
    }
    
}

struct ScannedDrugData{
    let drugName: String
    let ndc: String
    let gtin: String
    let quantity: Int32
}


struct StockTransaction: Identifiable, Hashable {
    let id: Int64
    let drugName: String
    let ndc: String
    let total: Int32
    let stockBottles: Int32
    let openPills: Int32
    let expiray: String
}


struct GroupedTransaction {
    let ndc: String
    let drugName: String
    let total: Int32
    
    let sealedBottles: Int32
    let openPills: Int32
    
    let lotDetails: [LotDetail]
}

struct LotDetail {
    let lot: String
    let expiry: String
    let sealedQty: Int32
    let openQty: Int32
}


// If the conflict persists, use @objc to override
extension BatchCountEntity: ListItemIdentifiable {
    @objc public var id: Int64 { batch_id }
}
