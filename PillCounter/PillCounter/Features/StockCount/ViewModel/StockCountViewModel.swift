//
//  StockCountViewModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 03/04/26.
//
import Foundation
import SwiftUI
import Combine

@MainActor
class StockCountViewModel: ObservableObject {

    // MARK: - Dependencies

    let pillDataLocalStorage = PillsDataLocalStorage.shared
    let userDataLocalStorage = UserLocalDataSource.shared
    let decoder              = BarcodeAndQRDecoder()
    let controlledRepo       = ControlledRepository.shared

    // MARK: - Published State

    @Published var groupedTransactions: [GroupedTransaction] = []
    @Published var regularCountTransactions: [PillCountTransactionEntity] = []
    @Published var currentBatch: BatchCountEntity?
    @Published var totalBatchCount: Int = 0
    @Published var totalCompletedBatchCount: Int = 0
    @Published var totalNdcRequests: Int = 0
    @Published var scannedDrugData: ScannedDrugData?
    @Published var showStockCountScannedDetails: Bool = false
    @Published var showScanError: Bool = false
    @Published var isLoading: Bool = false
    @Published var barcodeNotFound: Bool = false
    @Published var showScannedNdcDoesNotMatch: Bool = false
    @Published var batchNdcSet: Set<String> = []
    @Published var selectedTransaction: PillCountTransactionEntity? = nil
    @Published var note: String = ""
    
    @AppStorage(AppStorageManager.AppStorageKeys.isPillCountingEnabled) var isNoteEnable: Bool = false

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        observeDataChanges()
    }

    // MARK: - Reactive Observer

    /// Single subscription. Any DB write fires transactionsDidChange,
    /// which calls reloadAllState() — no manual reload calls needed anywhere.
    private func observeDataChanges() {
        pillDataLocalStorage.transactionsDidChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadAllState()
            }
            .store(in: &cancellables)
    }

    /// Central state refresh. Replaces loadTransactions() + updateBatchCount()
    /// everywhere they were previously called manually.
    private func reloadAllState() {
        Log("State Reloaded")
        let batches = pillDataLocalStorage.fetchAllBatches()
        totalBatchCount = batches.count
        totalCompletedBatchCount = pillDataLocalStorage.fetchCompletedBatches().count

        guard let batchId = currentBatch?.batch_id else {
            groupedTransactions = []
            batchNdcSet = []
            return
        }

        let txns = pillDataLocalStorage.fetchTransactionsByBatch(batchId: batchId)
        groupedTransactions = mapGroupedTransactions(txns: txns)
        batchNdcSet = Set(txns.compactMap { $0.drug?.ndc })
    }

    // MARK: - Batch

    func createNewBatch(bucketId: String) {
        if let batch = pillDataLocalStorage.createBatch(bucketId: bucketId) {
            currentBatch = batch
            // reloadAllState() fires automatically via publisher
        }
    }

    func continueLastBatch() -> Bool {
        guard let lastBatch = pillDataLocalStorage.fetchLastCreatedBatch() else {
            return false
        }
        currentBatch = lastBatch
        reloadAllState()
        return true
    }

    func loadBatches() -> [BatchCountEntity] {
        pillDataLocalStorage.fetchAllBatches()
    }

//    func completeBatch(batchId: Int64) {
//        let txns = pillDataLocalStorage.fetchTransactionsByBatch(batchId: batchId)
//        txns.forEach {
//            pillDataLocalStorage.updateTransactionStatus(txnId: $0.txn_id, newStatus: .COMPLETED)
//        }
//        pillDataLocalStorage.updateBatchStatus(batchId: batchId, status: .COMPLETED)
//        Hl7ServiceController.shared.sendBatchInventory(batchId: batchId)
//        // reloadAllState() fires automatically via publisher
//        print("Batch \(batchId) marked as COMPLETED")
//    }
    
    func completeBatch(batchId: Int64) {
        let txns = pillDataLocalStorage.fetchTransactionsByBatch(batchId: batchId)
        txns.forEach {
            pillDataLocalStorage.updateTransactionStatus(txnId: $0.txn_id, newStatus: .COMPLETED)
        }
        
        // Save batch status THEN fire publisher — no race condition
        pillDataLocalStorage.updateBatchStatus(batchId: batchId, status: .COMPLETED) { [weak self] in
            // This runs on main thread, after Core Data save is confirmed
            self?.pillDataLocalStorage.transactionsDidChange.send()
        }
        
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
               pillDataLocalStorage.updateBatchNote(
                   batchId: batchId,
                   note: note
               )
            note = ""
         }
    }

    // MARK: - Transactions

    func updateCounts(txnId: Int64?, bottleQty: Int? = nil, looseQty: Int? = nil) {
        pillDataLocalStorage.updateCounts(
            txnId: txnId,
            bottleQty: bottleQty.map { Int32($0) },
            looseQty:  looseQty.map  { Int32($0) }
        )
        // reloadAllState() fires automatically via publisher
    }
    
    

    // MARK: - NDC Requests (unaffected by publisher — different data set)

    func getAllPartialTransactions(countType: CountType, userId: String) async {
        guard let user = userDataLocalStorage.getUserByUserId(by: userId) else {
            regularCountTransactions = []
            return
        }
        regularCountTransactions = pillDataLocalStorage
            .fetchAllTransactionFixedOrRegularPartialFromPms(for: user, countType: countType)

        totalNdcRequests = 0
        for transaction in regularCountTransactions {
            totalNdcRequests = pillDataLocalStorage
                .getTheCountedNumberOfPillsForTheTransaction(for: transaction.txn_id)
        }
    }

    // MARK: - Scan

    func getScannedDrugData(rawValue: String) async {
        let gtin = decoder.decode(rawValue).gtin ?? ""
        await fetchDrugDataOnly(gtin: gtin)
    }

    private func fetchDrugDataOnly(gtin: String) async {
        guard !gtin.isEmpty else {
            showScanError = true
            barcodeNotFound = true
            return
        }

        showStockCountScannedDetails = false
        showScanError = false
        isLoading = true

        // 1. Local DB
        if let localDrug = pillDataLocalStorage.getPillByGtin(by: gtin) {
            let ndc = localDrug.ndc ?? ""
            if currentBatch?.req_id_from_pms != nil, !batchNdcSet.contains(ndc) {
                isLoading = false
                showScannedNdcDoesNotMatch = true
                return
            }
            scannedDrugData = ScannedDrugData(
                drugName: localDrug.drug_name ?? "",
                ndc:      ndc,
                gtin:     localDrug.gtin ?? "",
                quantity: localDrug.package_qty
            )
            isLoading = false
            showStockCountScannedDetails = true
            print("Fetched response from Local")
            return
        }

        // 2. API
        do {
            let response = try await controlledRepo.getControlledDrugInfo(
                ndcValidationRequest: NdcValidationRequest(targetNdc: gtin, scannedNdc: gtin)
            )
            let ndc = response.data?.scannedNdc?.packageNdc ?? ""
            if currentBatch?.req_id_from_pms != nil, !batchNdcSet.contains(ndc) {
                isLoading = false
                showScannedNdcDoesNotMatch = true
                print("❌ NDC not part of PMS batch: \(ndc) — set: \(batchNdcSet)")
                return
            }
            scannedDrugData = ScannedDrugData(
                drugName: response.data?.scannedNdc?.lookupName ?? "",
                ndc:      ndc,
                gtin:     ndc,
                quantity: response.data?.scannedNdc?.safeQuantity ?? 0
            )
            isLoading = false
            showStockCountScannedDetails = true
            print("Fetched response from API: \(response)")
        } catch {
            scannedDrugData = nil
            isLoading = false
            showScanError = true
            barcodeNotFound = true
        }
    }

    // MARK: - Misc

    /// Explicit trigger for onAppear / pull-to-refresh.
    func getCountData() {
        reloadAllState()
    }

    func reset() {
        scannedDrugData = nil
        showStockCountScannedDetails = false
        showScanError = false
        barcodeNotFound = false
        showScannedNdcDoesNotMatch = false
        isLoading = false
    }

    // MARK: - Mapper

    func mapGroupedTransactions(txns: [PillCountTransactionEntity]) -> [GroupedTransaction] {
        let groupedByNdc = Dictionary(grouping: txns) { $0.drug?.ndc ?? "" }

        return groupedByNdc.map { ndc, txnList in
            let drugName   = txnList.first?.drug?.drug_name ?? "Unknown"
            let lotGrouped = Dictionary(grouping: txnList) {
                "\($0.lot_no ?? "")|\($0.expiry ?? "")"
            }

            var lotDetails:   [LotDetail] = []
            var totalSealed:  Int32 = 0
            var totalOpen:    Int32 = 0

            for (_, lotTxns) in lotGrouped {
                let sealed = lotTxns.reduce(0) { $0 + ($1.bottle_qty * ($1.drug?.package_qty ?? 0)) }
                let open   = lotTxns.reduce(0) { $0 + $1.loose_qty }
                totalSealed += sealed
                totalOpen   += open
                lotDetails.append(LotDetail(
                    lot:      lotTxns.first?.lot_no  ?? "",
                    expiry:   lotTxns.first?.expiry  ?? "",
                    sealedQty: sealed,
                    openQty:   open
                ))
            }

            return GroupedTransaction(
                txnId:       txnList.first?.txn_id ?? 0,
                ndc:          ndc,
                drugName:     drugName,
                total:        totalSealed + totalOpen,
                sealedBottles: totalSealed,
                sealedBottleQty: txnList.first?.bottle_qty ?? 0,
                openPills:    totalOpen,
                lotDetails:   lotDetails
            )
        }
    }
}

// MARK: - Supporting Types

struct ScannedDrugData {
    let drugName: String
    let ndc:      String
    let gtin:     String
    let quantity: Int32
}

struct StockTransaction: Identifiable, Hashable {
    let id:          Int64
    let drugName:    String
    let ndc:         String
    let total:       Int32
    let stockBottles: Int32
    let openPills:   Int32
    let expiray:     String
}

struct GroupedTransaction {
    let txnId:  Int64
    let ndc:           String
    let drugName:      String
    let total:         Int32
    let sealedBottles: Int32
    let sealedBottleQty: Int32
    let openPills:     Int32
    let lotDetails:    [LotDetail]
}

struct LotDetail {
    let lot:       String
    let expiry:    String
    let sealedQty: Int32
    let openQty:   Int32
}

// MARK: - BatchCountEntity conformance

extension BatchCountEntity: ListItemIdentifiable {
    @objc public var id: Int64 { batch_id }
}
