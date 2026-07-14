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

    // MARK: - Injected dependencies
    //
    // Default to the production singletons so existing call sites
    // (`StockCountViewModel()`) keep working unchanged. Tests pass mocks
    // conforming to the data-source / repository protocols.

    let batchDAO: BatchDataSource
    let transactionDAO: TransactionDataSource
    let transactionDetailDAO: TransactionDetailDataSource
    let stockTxnDAO: StockTxnDataSource
    let bottleInfoDAO: BottleInfoDataSource
    let drugMasterDAO: DrugCatalogDataSource
    let userDataLocalStorage: UserDataSource
    let decoder: BarcodeAndQRDecoder
    let controlledRepo: ControlledRepositoryProtocol

    init(
        batchDAO: BatchDataSource = BatchStore.shared,
        transactionDAO: TransactionDataSource = TransactionStore.shared,
        transactionDetailDAO: TransactionDetailDataSource = TransactionDetailStore.shared,
        stockTxnDAO: StockTxnDataSource = StockTxnStore.shared,
        bottleInfoDAO: BottleInfoDataSource = BottleInfoStore.shared,
        drugMasterDAO: DrugCatalogDataSource = DrugCatalogStore.shared,
        userDataLocalStorage: UserDataSource = UserStore.shared,
        decoder: BarcodeAndQRDecoder = BarcodeAndQRDecoder(),
        controlledRepo: ControlledRepositoryProtocol = ControlledRepository.shared
    ) {
        self.batchDAO = batchDAO
        self.transactionDAO = transactionDAO
        self.transactionDetailDAO = transactionDetailDAO
        self.stockTxnDAO = stockTxnDAO
        self.bottleInfoDAO = bottleInfoDAO
        self.drugMasterDAO = drugMasterDAO
        self.userDataLocalStorage = userDataLocalStorage
        self.decoder = decoder
        self.controlledRepo = controlledRepo

        observeDataChanges()
    }

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

    /// StockTxn/BottleInfo committed by the last auto-add.
    /// committedStockTxnId identifies the NDC row; committedBottleId is the sealed bottle row
    /// the stepper writes to (debounced).
    @Published var committedStockTxnId: Int64? = nil
    @Published var committedBottleId: Int64? = nil
    private var stepperDebounceTask: Task<Void, Never>? = nil

    /// While true, DB-change publisher events do not trigger a list reload.
    /// Set true before auto-add writes; set false + call reloadAllState() on dismiss.
    var suppressListReload: Bool = false
    
    @AppStorage(AppStorageManager.AppStorageKeys.isPillCountingEnabled) var isNoteEnable: Bool = false

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Reactive Observer

    /// Single subscription. Any DB write fires transactionsDidChange,
    /// which calls reloadAllState() — no manual reload calls needed anywhere.
    private func observeDataChanges() {
        Publishers.Merge3(
            batchDAO.transactionsDidChange,
            stockTxnDAO.stockTxnsDidChange,
            bottleInfoDAO.bottleInfosDidChange
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

        let stockTxns = stockTxnDAO.fetchByBatch(batchId: batchId)
        groupedTransactions = mapGroupedStockTxns(stockTxns: stockTxns)
        batchNdcSet = Set(stockTxns.compactMap { $0.drug?.ndc })
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

    // MARK: - Stock-count entry (called by the scan screen on appear)

    /// Resume counting an existing batch. Fetches it fresh by id and rebuilds
    /// the session. Centralises the setup callers previously did inline.
    func startStockCount(batchId: Int64) {
        guard let batch = batchDAO.fetchById(batchId) else { return }
        currentBatch = batch
        reloadAllState()
    }

    /// Begin a new stock-count batch for the given bucket. The batch is created
    /// lazily on the first scan via `ensureBatchExists()`; here we just clear any
    /// prior session and stash the bucket.
    func startNewBatch(bucketId: String) {
        currentBatch = nil
        groupedTransactions = []
        batchNdcSet = []
        pendingBucketId = bucketId
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
        let stockTxns = stockTxnDAO.fetchByBatch(batchId: batchId)
        stockTxns.forEach {
            stockTxnDAO.updateStatus(stockTxnId: $0.stock_txn_id, status: .COMPLETED)
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
        guard let bottleId = committedBottleId else { return }
        stepperDebounceTask?.cancel()
        stepperDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            bottleInfoDAO.setAbsolute(bottleId: bottleId, bottleQty: Int32(count), looseQty: nil)
        }
    }

    /// Cancels any pending debounce and writes the current bottle count immediately.
    /// Call before Add/Clear so the latest stepper value is always committed.
    func flushPendingBottleCount() {
        guard let bottleId = committedBottleId else { return }
        stepperDebounceTask?.cancel()
        stepperDebounceTask = nil
        bottleInfoDAO.setAbsolute(bottleId: bottleId, bottleQty: Int32(pendingBottleCount), looseQty: nil)
    }

    /// Absolute-set on a specific BottleInfoEntity row.
    func updateCounts(bottleId: Int64?, bottleQty: Int? = nil, looseQty: Int? = nil) {
        guard let bottleId else { return }
        bottleInfoDAO.setAbsolute(
            bottleId: bottleId,
            bottleQty: bottleQty.map { Int32($0) },
            looseQty:  looseQty.map  { Int32($0) }
        )
        // reloadAllState() fires automatically via publisher
    }
    
    

    // MARK: - NDC Requests (unaffected by publisher — different data set)

    func getAllPartialTransactions(isDispense: Bool, userId: String) async {
        guard let user = userDataLocalStorage.fetchByUserId(userId) else {
            regularCountTransactions = []
            return
        }
        regularCountTransactions = transactionDAO.fetchPartialFromPms(for: user, isDispense: isDispense)

        totalNdcRequests = 0
        for transaction in regularCountTransactions {
            totalNdcRequests = transactionDetailDAO.totalCount(txnId: transaction.txn_id)
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
            let ndc = response.data?.scannedNdc?.drugCode ?? ""
            if currentBatch?.req_id_from_pms != nil, !batchNdcSet.contains(ndc) {
                isLoading = false
                showScannedNdcDoesNotMatch = true
                print("❌ NDC not part of PMS batch: \(ndc) — set: \(batchNdcSet)")
                return
            }
            let drugName = response.data?.scannedNdc?.lookupName ?? ""
            let qty      = response.data?.scannedNdc?.safeQuantity ?? 0

            // Backfill drug master so future scans resolve locally with full data
            let newDrugId = generateUniqueDrugId()
            if let scannedNdc = response.data?.scannedNdc {
                drugMasterDAO.upsertFromApi(
                    ndc:    ndc,
                    drugId: newDrugId,
                    drug:   scannedNdc,
                    gtin:   gtin
                )
            }

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
        committedStockTxnId = nil
        committedBottleId = nil
        selectedGroupedTransaction = nil
        stepperDebounceTask?.cancel()
        stepperDebounceTask = nil
        suppressListReload = false
        // Note: pendingBucketId and currentBatch are intentionally NOT cleared here
        // so they survive scan resets within the same session.
    }

    /// Re-syncs the detail card's stepper state from the DB after an Edit Details save.
    /// The card reads `pendingBottleCount`, which was set once during scan; the Edit sheet
    /// writes straight to the DAO, so without this the card stays stale.
    ///
    /// `pendingBottleCount` MUST stay equal to the committed sealed bottle row's `bottle_qty`,
    /// because the Add flush (`flushPendingBottleCount`) writes it back to that single row.
    /// Storing the NDC-wide sum here instead would make the flush re-apply the edit and double
    /// the count.
    func resyncScannedDrugCounts() {
        guard let ndc = scannedDrugData?.ndc else { return }
        existingNdcBottleCount = existingBottleCount(for: ndc)
        if let bottleId = committedBottleId, let bottle = bottleInfoDAO.fetchById(bottleId) {
            pendingBottleCount = Int(bottle.bottle_qty)
        } else {
            pendingBottleCount = existingNdcBottleCount
        }
    }

    /// Returns the existing sealed bottle count for an NDC already in the current batch
    /// (the single sealed BottleInfoEntity row's bottle_qty, or 0 if none yet).
    /// Displayed alongside the stepper so the user sees current total + how many they're adding.
    func existingBottleCount(for ndc: String) -> Int {
        guard let batchId = currentBatch?.batch_id,
              let stockTxn = stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: ndc) else { return 0 }
        let sealedRow = bottleInfoDAO
            .fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
            .first { $0.bottle_qty > 0 && $0.loose_qty == 0 }
        return Int(sealedRow?.bottle_qty ?? 0)
    }

    /// NDC-wide sealed bottle total shown in the scanned-detail card.
    ///
    /// `pendingBottleCount` is bound to the single committed sealed bottle row (the flush
    /// target), so it only ever holds that row's own count. We take the DB value and fold in
    /// the live, not-yet-flushed stepper delta so the number reacts to +/- taps immediately
    /// (the DAO write is debounced 600ms and would otherwise lag).
    func displayBottleTotal(for ndc: String) -> Int {
        let ndcWide = existingBottleCount(for: ndc)
        guard let bottleId = committedBottleId, let bottle = bottleInfoDAO.fetchById(bottleId) else {
            return ndcWide
        }
        let committedDbQty = Int(bottle.bottle_qty)
        return ndcWide - committedDbQty + pendingBottleCount
    }

    /// Returns the count of opened BottleInfoEntity rows for an NDC in the current batch
    /// (each opened scan creates one row — this is the "number of opened bottles").
    func existingOpenBottleCount(for ndc: String) -> Int {
        guard let batchId = currentBatch?.batch_id,
              let stockTxn = stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: ndc) else { return 0 }
        return bottleInfoDAO
            .fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
            .filter { !($0.bottle_qty > 0 && $0.loose_qty == 0) }
            .count
    }

    /// Returns the existing open (loose) pill count for an NDC in the current batch —
    /// the sum of loose_qty across every opened BottleInfoEntity row.
    /// Displayed alongside the bottle stepper so the user sees scanned open pills.
    func existingOpenPillCount(for ndc: String) -> Int {
        guard let batchId = currentBatch?.batch_id,
              let stockTxn = stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: ndc) else { return 0 }
        return bottleInfoDAO
            .fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
            .filter { !($0.bottle_qty > 0 && $0.loose_qty == 0) }
            .reduce(0) { $0 + Int($1.loose_qty) }
    }

    /// Finds the StockTxnEntity for the given NDC in the current batch (used by open pill flow).
    func existingTxn(for ndc: String) -> StockTxnEntity? {
        guard let batchId = currentBatch?.batch_id else { return nil }
        return stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: ndc)
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
        committedStockTxnId = txn.stockTxnId
        // existingNdcBottleCount is the NDC-wide sealed total (for display).
        // pendingBottleCount MUST be the committed sealed row's OWN bottle_qty, not the
        // NDC-wide sum — flushPendingBottleCount writes it absolutely onto committedBottleId,
        // so storing the sum here would double-count. displayBottleTotal folds the pending
        // value back into the NDC-wide sum, so the card still shows the full total.
        existingNdcBottleCount = Int(txn.sealedBottleQty)
        if let batchId = currentBatch?.batch_id,
           let stockTxn = stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: txn.ndc) {
            let sealedRow = bottleInfoDAO
                .fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
                .first { $0.bottle_qty > 0 && $0.loose_qty == 0 }
            committedBottleId = sealedRow?.bottle_id
            pendingBottleCount = Int(sealedRow?.bottle_qty ?? txn.sealedBottleQty)
        } else {
            committedBottleId = nil
            pendingBottleCount = Int(txn.sealedBottleQty)
        }
        selectedGroupedTransaction = txn
    }

    // MARK: - Mapper

    func mapGroupedStockTxns(stockTxns: [StockTxnEntity]) -> [GroupedTransaction] {
        let groupedByNdc = Dictionary(grouping: stockTxns) { $0.drug?.ndc ?? "" }

        return groupedByNdc.map { ndc, stockTxnList in
            let drugName = stockTxnList.first?.drug?.drug_name ?? "Unknown"
            let packageQty = stockTxnList.first?.drug?.package_qty ?? 0

            var lotDetails:  [LotDetail] = []
            var totalSealed: Int32 = 0
            var totalOpen:   Int32 = 0
            var sealedBottleQty: Int32 = 0
            var openedBottleCount: Int32 = 0

            for stockTxn in stockTxnList {
                let bottles = bottleInfoDAO.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)

                let sealedRows = bottles.filter { $0.bottle_qty > 0 && $0.loose_qty == 0 }
                let openedRows = bottles.filter { !($0.bottle_qty > 0 && $0.loose_qty == 0) }

                for sealed in sealedRows {
                    let sealedQty = sealed.bottle_qty * packageQty
                    totalSealed += sealedQty
                    sealedBottleQty += sealed.bottle_qty
                    lotDetails.append(LotDetail(
                        lot: sealed.lot_no ?? "", expiry: sealed.exp_no ?? "",
                        sealedQty: sealedQty, openQty: 0
                    ))
                }

                // Every opened row IS one physical bottle — tracked separately from
                // sealedBottleQty so "Sealed Bottles" vs "Opened Bottles" stay distinct.
                openedBottleCount += Int32(openedRows.count)

                let openGrouped = Dictionary(grouping: openedRows) { "\($0.lot_no ?? "")|\($0.exp_no ?? "")" }
                for (_, rows) in openGrouped {
                    let open = rows.reduce(0) { $0 + $1.loose_qty }
                    totalOpen += open
                    lotDetails.append(LotDetail(
                        lot: rows.first?.lot_no ?? "", expiry: rows.first?.exp_no ?? "",
                        sealedQty: 0, openQty: open
                    ))
                }
            }

            return GroupedTransaction(
                stockTxnId:        stockTxnList.first?.stock_txn_id ?? 0,
                ndc:               ndc,
                drugName:          drugName,
                total:             totalSealed + totalOpen,
                sealedBottles:     totalSealed,
                sealedBottleQty:   sealedBottleQty,
                openedBottleCount: openedBottleCount,
                packageQty:        packageQty,
                openPills:         totalOpen,
                lotDetails:        lotDetails
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
    let stockTxnId:        Int64
    let ndc:               String
    let drugName:          String
    let total:             Int32
    let sealedBottles:     Int32
    /// Count of sealed physical bottles only (the single sealed BottleInfoEntity row's bottle_qty).
    let sealedBottleQty:   Int32
    /// Count of opened physical bottles (one BottleInfoEntity row each).
    let openedBottleCount: Int32
    let packageQty:        Int32
    let openPills:         Int32
    let lotDetails:        [LotDetail]

    /// Total physical bottles for this NDC — sealed + opened — shown on the batch list row.
    var totalBottleCount: Int32 { sealedBottleQty + openedBottleCount }
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
