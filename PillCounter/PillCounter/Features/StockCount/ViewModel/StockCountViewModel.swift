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

    let batchDAO             = BatchStore.shared
    let transactionDAO       = TransactionStore.shared
    let drugMasterDAO        = DrugCatalogStore.shared
    let userDataLocalStorage = UserStore.shared
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
    @Published var selectedGroupedTransaction: GroupedTransaction? = nil
    @Published var note: String = ""
    @Published var pendingBottleCount: Int = 1
    @Published var existingNdcBottleCount: Int = 0
    @Published var openPillScanRequested: Bool = false
    @Published var openPillScanNdc: String = ""
    var pendingBucketId: String = ""

    /// Txn committed by the last auto-add. Stepper changes debounce-update this txn.
    @Published var committedTxnId: Int64? = nil
    private var stepperDebounceTask: Task<Void, Never>? = nil

    /// While true, DB-change publisher events do not trigger a list reload.
    /// Set true before auto-add writes; set false + call reloadAllState() on dismiss.
    var suppressListReload: Bool = false
    
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
        Publishers.Merge(
            batchDAO.transactionsDidChange,
            transactionDAO.transactionsDidChange
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            guard let self, !self.suppressListReload else { return }
            self.reloadAllState()
        }
        .store(in: &cancellables)
    }

    /// Central state refresh. Replaces loadTransactions() + updateBatchCount()
    /// everywhere they were previously called manually.
    func reloadAllState() {
        Log("State Reloaded")
        let batches = batchDAO.fetchAllPartial()
        totalBatchCount = batches.count
        totalCompletedBatchCount = batchDAO.fetchAllCompleted().count

        guard let batchId = currentBatch?.batch_id else {
            groupedTransactions = []
            batchNdcSet = []
            return
        }

        let txns = transactionDAO.fetchByBatch(batchId: batchId)
        groupedTransactions = mapGroupedTransactions(txns: txns)
        batchNdcSet = Set(txns.compactMap { $0.drug?.ndc })
    }

    // MARK: - Batch

    func createNewBatch(bucketId: String) {
        if let batch = batchDAO.create(bucketId: bucketId) {
            currentBatch = batch
            // reloadAllState() fires automatically via publisher
        }
    }

    /// Creates the batch lazily on the first scan. Call before creating any transaction.
    func ensureBatchExists() {
        guard currentBatch == nil else { return }
        createNewBatch(bucketId: pendingBucketId)
    }

    func continueLastBatch() -> Bool {
        guard let lastBatch = batchDAO.fetchLastCreated() else {
            return false
        }
        currentBatch = lastBatch
        reloadAllState()
        return true
    }

    func loadBatches() -> [BatchCountEntity] {
        batchDAO.fetchAllPartial()
    }
    
    func generateUniqueDrugId() -> Int64 {
        let defaults = UserDefaults.standard

        let current = defaults.integer(
            forKey: AppStorageManager.AppStorageKeys.drugIdCounter)
        let newId = current + 1

        defaults.set(
            newId, forKey: AppStorageManager.AppStorageKeys.drugIdCounter)

        return Int64(newId)
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
        let txns = transactionDAO.fetchByBatch(batchId: batchId)
        txns.forEach {
            transactionDAO.updateStatus(txnId: $0.txn_id, status: .COMPLETED)
        }

        // Save batch status THEN fire publisher — no race condition
        batchDAO.updateStatus(batchId: batchId, status: .COMPLETED) { [weak self] in
            // This runs on main thread, after Core Data save is confirmed
            self?.batchDAO.transactionsDidChange.send()
        }

        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
               batchDAO.updateNote(batchId: batchId, note: note)
            note = ""
         }
    }

    // MARK: - Transactions

    /// Call when the stepper changes after a drug has been auto-added.
    /// Debounces so rapid taps only fire one DB write after 600ms of silence.
    func debouncedUpdateBottleCount(_ count: Int) {
        guard let txnId = committedTxnId else { return }
        stepperDebounceTask?.cancel()
        stepperDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            transactionDAO.setAbsoluteCounts(txnId: txnId, bottleQty: Int32(count))
        }
    }

    /// Cancels any pending debounce and writes the current bottle count immediately.
    /// Call before Add/Clear so the latest stepper value is always committed.
    func flushPendingBottleCount() {
        guard let txnId = committedTxnId else { return }
        stepperDebounceTask?.cancel()
        stepperDebounceTask = nil
        transactionDAO.setAbsoluteCounts(txnId: txnId, bottleQty: Int32(pendingBottleCount))
    }

    func updateCounts(txnId: Int64?, bottleQty: Int? = nil, looseQty: Int? = nil, openBottleQty: Int? = nil) {
        guard let txnId else { return }
        transactionDAO.updateCounts(
            txnId: txnId,
            bottleQty:     bottleQty.map     { Int32($0) },
            looseQty:      looseQty.map      { Int32($0) },
            openBottleQty: openBottleQty.map { Int32($0) }
        )
        // reloadAllState() fires automatically via publisher
    }
    
    

    // MARK: - NDC Requests (unaffected by publisher — different data set)

    func getAllPartialTransactions(countType: CountType, userId: String) async {
        guard let user = userDataLocalStorage.fetchByUserId(userId) else {
            regularCountTransactions = []
            return
        }
        regularCountTransactions = transactionDAO.fetchPartialFromPms(for: user, countType: countType)

        totalNdcRequests = 0
        for transaction in regularCountTransactions {
            totalNdcRequests = TransactionDetailStore.shared.totalCount(txnId: transaction.txn_id)
        }
    }

    // MARK: - Scan

    func getScannedDrugData(rawValue: String) async {
        let decoded = decoder.decode(rawValue)
        let lotNumber = decoded.lotNumber ?? ""
        let expiryString = formatExpiry(decoded.expirationDate) ?? ""

        let rawDigitsOnly = rawValue.components(separatedBy: .decimalDigits.inverted).joined()
        let gtin: String
        if let decoded = decoded.gtin, !decoded.isEmpty {
            gtin = decoded
        } else if rawDigitsOnly.count >= 8 && rawDigitsOnly.count <= 14 {
            gtin = rawDigitsOnly
        } else {
            gtin = ""
        }

        print("🔵 [BT-Scan] rawValue='\(rawValue)' utf8bytes=\(Array(rawValue.utf8)) rawDigitsOnly='\(rawDigitsOnly)' resolvedGtin='\(gtin)'")

        await fetchDrugDataOnly(rawValue: rawValue, gtin: gtin, lotNumber: lotNumber, expiry: expiryString)
    }

    private func formatExpiry(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func fetchDrugDataOnly(rawValue: String, gtin: String, lotNumber: String = "", expiry: String = "") async {
        guard !gtin.isEmpty else {
            showScanError = true
            barcodeNotFound = true
            return
        }

        showStockCountScannedDetails = false
        showScanError = false
        isLoading = true

        // 1. Local DB — only use if quantity is known; otherwise fall through to API to backfill it
        let localLookup = drugMasterDAO.fetchByGtin(gtin)
        print("🔵 [BT-Scan] localDB lookup gtin='\(gtin)' found=\(localLookup != nil) pkg_qty=\(localLookup?.package_qty ?? -1)")
        if let localDrug = localLookup, localDrug.package_qty > 0 {
            let ndc = localDrug.ndc ?? ""
            if currentBatch?.req_id_from_pms != nil, !batchNdcSet.contains(ndc) {
                isLoading = false
                showScannedNdcDoesNotMatch = true
                return
            }
            scannedDrugData = ScannedDrugData(
                drugName:   localDrug.drug_name ?? "",
                ndc:        ndc,
                gtin:       localDrug.gtin ?? "",
                quantity:   localDrug.package_qty,
                lotNumber:  lotNumber,
                expiry:     expiry,
                rawBarcode: rawValue
            )
            let existing = existingBottleCount(for: ndc)
            existingNdcBottleCount = existing
            pendingBottleCount = existing + 1
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
            let drugName = response.data?.scannedNdc?.lookupName ?? ""
            let qty      = response.data?.scannedNdc?.safeQuantity ?? 0
            let drugType = response.data?.scannedNdc?.deaSchedule

            // Backfill drug master so future scans resolve locally with full data
            let newDrugId = generateUniqueDrugId()
            drugMasterDAO.saveManual(
                ndc:         ndc,
                gtin:        gtin,
                drugId:      newDrugId,
                drugName:    drugName,
                drugType:    drugType,
                packageQty:  qty,
                isHazardous: response.data?.scannedNdc?.isHazardous
            )

            scannedDrugData = ScannedDrugData(
                drugName:   drugName,
                ndc:        ndc,
                gtin:       gtin,
                quantity:   qty,
                lotNumber:  lotNumber,
                expiry:     expiry,
                rawBarcode: rawValue
            )
            let existingApi = existingBottleCount(for: ndc)
            existingNdcBottleCount = existingApi
            pendingBottleCount = existingApi + 1
            isLoading = false
            showStockCountScannedDetails = true
            print("Fetched response from API: \(response)")
        } catch {
            print("🔴 [BT-Scan] API failed gtin='\(gtin)' error=\(error)")
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
        pendingBottleCount = 1
        existingNdcBottleCount = 0
        openPillScanRequested = false
        openPillScanNdc = ""
        committedTxnId = nil
        selectedGroupedTransaction = nil
        stepperDebounceTask?.cancel()
        stepperDebounceTask = nil
        suppressListReload = false
        // Note: pendingBucketId and currentBatch are intentionally NOT cleared here
        // so they survive scan resets within the same session.
    }

    /// Returns the existing sealed bottle count for an NDC already in the current batch.
    /// Displayed alongside the stepper so the user sees current total + how many they're adding.
    func existingBottleCount(for ndc: String) -> Int {
        guard let batchId = currentBatch?.batch_id else { return 0 }
        let txns = transactionDAO.fetchByBatch(batchId: batchId).filter { $0.drug?.ndc == ndc }
        return txns.reduce(0) { $0 + Int($1.bottle_qty) }
    }

    /// Returns the existing open bottle count for an NDC in the current batch.
    func existingOpenBottleCount(for ndc: String) -> Int {
        guard let batchId = currentBatch?.batch_id else { return 0 }
        let txns = transactionDAO.fetchByBatch(batchId: batchId).filter { $0.drug?.ndc == ndc }
        return txns.reduce(0) { $0 + Int($1.open_bottle_qty) }
    }

    /// Finds the transaction for the given NDC in the current batch (used by open pill flow).
    func existingTxn(for ndc: String) -> PillCountTransactionEntity? {
        guard let batchId = currentBatch?.batch_id else { return nil }
        return transactionDAO.fetchByBatch(batchId: batchId).first { $0.drug?.ndc == ndc && $0.is_deleted == false }
    }

    func selectTransaction(_ txn: GroupedTransaction) {
        let firstLot = txn.lotDetails.first
        scannedDrugData = ScannedDrugData(
            drugName:  txn.drugName,
            ndc:       txn.ndc,
            gtin:      "",
            quantity:  txn.packageQty,
            lotNumber: firstLot?.lot ?? "",
            expiry:    firstLot?.expiry ?? ""
        )
        existingNdcBottleCount = Int(txn.sealedBottleQty)
        pendingBottleCount = Int(txn.sealedBottleQty)
        committedTxnId = txn.txnId
        selectedGroupedTransaction = txn
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
                sealedBottleQty: txnList.reduce(0) { $0 + $1.bottle_qty },
                packageQty:   txnList.first?.drug?.package_qty ?? 0,
                openPills:    totalOpen,
                lotDetails:   lotDetails
            )
        }
    }
}

// MARK: - Supporting Types

struct ScannedDrugData {
    let drugName:   String
    let ndc:        String
    let gtin:       String
    let quantity:   Int32
    let lotNumber:  String
    let expiry:     String
    var rawBarcode: String = ""
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
    let packageQty:    Int32
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
