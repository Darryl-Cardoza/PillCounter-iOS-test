//
//  HistoryViewModel.swift
//  PillCounter
//
//  Features/History/ViewModel/HistoryViewModel.swift
//

import Foundation
import SwiftUI
import CoreData

@MainActor
class HistoryViewModel: ObservableObject {

    // MARK: - Injected dependencies
    private let transactionStore: TransactionDataSource
    private let transactionDetailStore: TransactionDetailDataSource
    private let batchStore: BatchDataSource
    private let stockTxnStore: StockTxnDataSource
    private let bottleInfoStore: BottleInfoDataSource
    private let userStore: UserDataSource
    private let userIdProvider: UserIdProviding

    /// Dependencies default to the production singletons, so existing call
    /// sites (`HistoryViewModel()`) keep working unchanged. Tests pass mocks.
    init(
        transactionStore: TransactionDataSource = TransactionStore.shared,
        transactionDetailStore: TransactionDetailDataSource = TransactionDetailStore.shared,
        batchStore: BatchDataSource = BatchStore.shared,
        stockTxnStore: StockTxnDataSource = StockTxnStore.shared,
        bottleInfoStore: BottleInfoDataSource = BottleInfoStore.shared,
        userStore: UserDataSource = UserStore.shared,
        userIdProvider: UserIdProviding = AppStorageManager.shared
    ) {
        self.transactionStore = transactionStore
        self.transactionDetailStore = transactionDetailStore
        self.batchStore = batchStore
        self.stockTxnStore = stockTxnStore
        self.bottleInfoStore = bottleInfoStore
        self.userStore = userStore
        self.userIdProvider = userIdProvider
    }

    // MARK: - AppStorage
    private var userID: String { userIdProvider.userId ?? "" }

    // MARK: - Published: Raw filtered data
    @Published var filteredTransactionsOfUserByDate: [PillCountTransactionEntity] = []
    @Published var filteredBatchesOfUserByDate: [BatchCountEntity] = []

    // MARK: - Published: Mapped UI rows
    @Published var transactionRows: [TransactionRowData] = []
    @Published var batchRows: [StockData] = []

    // MARK: - Published: Detail view state
    @Published var selectedTransactionId: Int64? = nil
    @Published var detailsByStep: [ControlledStep: [PillCountTransactionDetailsEntity]] = [:]

    // MARK: - Published: Batch detail state
    @Published var selectedBatchId: Int64? = nil
    @Published var selectedBatch: BatchCountEntity? = nil
    @Published var groupedTransactionsForBatch: [GroupedTransaction] = []
    @Published var isLoading: Bool = false

    // MARK: - Published: Calendar selection (persists across orientation changes)
    @Published var selectedStartDate: Date? = Date()
    @Published var selectedEndDate: Date? = nil
    @Published var calendarMonthsToShow: [Date] = []

    // MARK: - Pagination state
    /// Rows fetched per page. Small enough that the first page renders
    /// near-instantly even when the selected date range holds thousands of
    /// rows; `loadMoreTransactionsIfNeeded`/`loadMoreBatchesIfNeeded` fetch
    /// subsequent pages as the user scrolls.
    let pageSize = 30
    @Published private(set) var hasMoreTransactions = true
    @Published private(set) var hasMoreBatches = true
    @Published private(set) var isLoadingMoreTransactions = false
    @Published private(set) var isLoadingMoreBatches = false
    private var transactionPageOffset = 0
    private var batchPageOffset = 0
    private var currentStartTs: Int64 = 0
    private var currentEndTs: Int64 = 0
    private var currentTypeFilter: HistoryFilterType = .fixed

    /// Row-data cache keyed by id, reused across `applyFilters` calls so a
    /// page load mid-fast-scroll only computes `TransactionRowData`/
    /// `StockData` (each involving a Core Data count query) for rows not
    /// already mapped, instead of re-querying and re-mapping every previously
    /// loaded row on every call. Cleared whenever the underlying loaded set
    /// is reset (new date range/type filter, delete, logout).
    private var transactionRowCache: [Int64: TransactionRowData] = [:]
    private var batchRowCache: [Int64: StockData] = [:]

    // MARK: - Fetch Transactions by Date (first page)

    /// Resets pagination and loads the first page for a new date/type
    /// selection. Call `loadMoreTransactionsIfNeeded` to fetch subsequent
    /// pages as the user scrolls.
    func getTransactionsByDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType
    ) async {
        guard filter != .regular else {
            filteredTransactionsOfUserByDate = []
            hasMoreTransactions = false
            return
        }
        guard let user = userStore.fetchByUserId(userID) else {
            filteredTransactionsOfUserByDate = []
            hasMoreTransactions = false
            return
        }

        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: endDate)
        )!

        currentStartTs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        currentEndTs = Int64(endOfDay.timeIntervalSince1970 * 1000)
        currentTypeFilter = filter
        transactionPageOffset = 0
        hasMoreTransactions = true
        transactionRowCache.removeAll()

        // Route through the real predicate-based, indexed fetch instead of
        // `UserStore.fetchTransactionsByDateRange`, which faulted the
        // user's ENTIRE transaction history into memory via the relationship
        // set just to filter by date in Swift — a full-table load disguised
        // as a date-scoped query.
        let page = transactionStore.fetchByTimeRangePage(
            for: user, startTime: currentStartTs, endTime: currentEndTs,
            limit: pageSize, offset: transactionPageOffset
        )
        transactionPageOffset += page.count
        hasMoreTransactions = page.count == pageSize

        filteredTransactionsOfUserByDate = page.filter { $0.is_dispense }
    }

    /// Fetches and appends the next page of transactions for the current
    /// date/type selection. No-op if a fetch is already running or there's
    /// nothing left to load.
    ///
    /// Deliberately NOT `async` — the underlying fetch is synchronous
    /// (`performAndWait`), so there was never a real suspension point inside.
    /// Marking it `async` only meant the view had to wrap each call in a
    /// fresh `Task { }`, and `Task` creation merely schedules work rather
    /// than running it — during a fast scroll, several `onAppear` triggers
    /// could each spawn a Task before any of them actually started running
    /// (and thus before `isLoadingMoreTransactions` had a chance to flip
    /// `true`), letting redundant fetches through the reentrancy guard and
    /// occasionally corrupting `hasMoreTransactions`. Calling this directly,
    /// synchronously, from `onAppear` — like Dashboard's equivalent loader —
    /// closes that gap entirely: the guard check and flag-set happen in the
    /// same uninterrupted call, so no second call can observe the flag as
    /// `false` while the first is still running.
    func loadMoreTransactionsIfNeeded() {
        guard hasMoreTransactions, !isLoadingMoreTransactions else { return }
        guard let user = userStore.fetchByUserId(userID), currentTypeFilter == .fixed else { return }

        isLoadingMoreTransactions = true
        defer { isLoadingMoreTransactions = false }

        let page = transactionStore.fetchByTimeRangePage(
            for: user, startTime: currentStartTs, endTime: currentEndTs,
            limit: pageSize, offset: transactionPageOffset
        )
        transactionPageOffset += page.count
        hasMoreTransactions = page.count == pageSize
        filteredTransactionsOfUserByDate += page.filter { $0.is_dispense }
    }

    // MARK: - Fetch Batches by Date (first page)

    func getBatchesByDate(startDate: Date, endDate: Date) async {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: endDate)
        )!

        currentStartTs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        currentEndTs = Int64(endOfDay.timeIntervalSince1970 * 1000)
        batchPageOffset = 0
        hasMoreBatches = true
        batchRowCache.removeAll()

        let page = batchStore.fetchByDateRangePage(
            startTs: currentStartTs, endTs: currentEndTs, limit: pageSize, offset: batchPageOffset
        )
        batchPageOffset += page.count
        hasMoreBatches = page.count == pageSize
        filteredBatchesOfUserByDate = page
    }

    /// Fetches and appends the next page of batches for the current date
    /// selection. No-op if a fetch is already running or there's nothing
    /// left to load. Deliberately NOT `async` — see
    /// `loadMoreTransactionsIfNeeded` for why.
    func loadMoreBatchesIfNeeded() {
        guard hasMoreBatches, !isLoadingMoreBatches else { return }
        isLoadingMoreBatches = true
        defer { isLoadingMoreBatches = false }

        let page = batchStore.fetchByDateRangePage(
            startTs: currentStartTs, endTs: currentEndTs, limit: pageSize, offset: batchPageOffset
        )
        batchPageOffset += page.count
        hasMoreBatches = page.count == pageSize
        filteredBatchesOfUserByDate += page
    }

    // MARK: - Apply Filters (status + search)
    func applyFilters(status: HistoryStatusFilter, search: String) {
        // --- Transactions ---
        var txns = filteredTransactionsOfUserByDate

        switch status {
        case .completed: txns = txns.filter { $0.status == CountStatus.COMPLETED.rawValue }
        case .pending:   txns = txns.filter { $0.status == CountStatus.PARTIAL.rawValue }
        case .all:       break
        }

        if !search.isEmpty {
            let q = search.lowercased()
            txns = txns.filter {
                ($0.drug?.drug_name?.lowercased() ?? "").contains(q)
                || ($0.note?.lowercased() ?? "").contains(q)
                || ($0.status?.lowercased() ?? "").contains(q)
                || ($0.drug?.ndc ?? "").contains(q)
            }
        }

        txns.sort { $0.created_at > $1.created_at }

        transactionRows = txns.map { txn in
            if let cached = transactionRowCache[txn.txn_id] {
                return cached
            }
            let counted = transactionDetailStore.totalCountForStep(
                txnId: txn.txn_id,
                step: .targetVerification
            )
            let row = txn.toRowData(pillCount: Int(counted))
            transactionRowCache[txn.txn_id] = row
            return row
        }

        // --- Batches ---
        var batches = filteredBatchesOfUserByDate

        switch status {
        case .completed: batches = batches.filter { $0.status == CountStatus.COMPLETED.rawValue }
        case .pending:   batches = batches.filter { $0.status == CountStatus.PARTIAL.rawValue}
        case .all:       break
        }

        if !search.isEmpty {
            let q = search.lowercased()
            batches = batches.filter {
                ($0.bucket_id?.lowercased().contains(q) ?? false)
                || ($0.status?.lowercased().contains(q) ?? false)
                || String($0.batch_id).contains(q)
            }
        }

        batches.sort { $0.start_date_time > $1.start_date_time }

        batchRows = batches.map { batch in
            if let cached = batchRowCache[batch.batch_id] {
                return cached
            }
            let count = batchStore.getTransactionCount(for: batch.batch_id)
            let row = batch.toStockData(ndcCount: count)
            batchRowCache[batch.batch_id] = row
            return row
        }
    }

    // MARK: - Soft Delete: Transactions (filter = .fixed)
    func softDeleteTransactionsForSelectedDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType,
        status: HistoryStatusFilter,
        search: String
    ) async {
        switch filter {
        case .fixed:
            let rowIdsToDelete = Set(transactionRows.map { Int64($0.id) })
            let toDelete = filteredTransactionsOfUserByDate.filter {
                rowIdsToDelete.contains($0.txn_id)
            }
            guard !toDelete.isEmpty else { return }
            for txn in toDelete {
                transactionStore.softDelete(txnId: txn.txn_id)
            }
            await getTransactionsByDate(startDate: startDate, endDate: endDate, filter: filter)

        case .regular:
            let batchIdsToDelete = Set(batchRows.map { $0.batchId })  // ← StockData.batchId field
            let toDelete = filteredBatchesOfUserByDate.filter {
                batchIdsToDelete.contains($0.batch_id)
            }
            guard !toDelete.isEmpty else { return }

            // softDelete soft-deletes both the batch AND its child transactions in one call
            batchStore.softDelete(ids: Set(toDelete.map { $0.batch_id }))

            await getBatchesByDate(startDate: startDate, endDate: endDate)
        }

        applyFilters(status: status, search: search)
    }

    // MARK: - Soft Delete Single Transaction (used from detail view)
    func softDeleteTransaction(txnId: Int64) async {
        transactionStore.softDelete(txnId: txnId)
    }
    
    func softDeleteBatch(batchId: Int64) async {
        batchStore.softDelete(ids: [batchId])
    }

    // MARK: - Status Counts
    /// True counts for the current date-range selection, independent of how
    /// many pages have been loaded — querying the loaded array directly (as
    /// this used to) made the badge change as pagination fetched more pages
    /// (e.g. showing "50" then "100" while scrolling), which reads as a bug
    /// since nothing about the underlying data changed.
    func getStatusCounts(for type: HistoryFilterType) -> (all: Int, completed: Int, pending: Int) {
        if type == .fixed {
            guard let user = userStore.fetchByUserId(userID) else { return (0, 0, 0) }
            return (
                all: transactionStore.countByTimeRange(for: user, startTime: currentStartTs, endTime: currentEndTs, status: nil),
                completed: transactionStore.countByTimeRange(for: user, startTime: currentStartTs, endTime: currentEndTs, status: .COMPLETED),
                pending: transactionStore.countByTimeRange(for: user, startTime: currentStartTs, endTime: currentEndTs, status: .PARTIAL)
            )
        } else {
            return (
                all: batchStore.countByDateRange(startTs: currentStartTs, endTs: currentEndTs, status: nil),
                completed: batchStore.countByDateRange(startTs: currentStartTs, endTs: currentEndTs, status: .COMPLETED),
                pending: batchStore.countByDateRange(startTs: currentStartTs, endTs: currentEndTs, status: .PARTIAL)
            )
        }
    }

    // MARK: - Type Tab Counts
    /// True dispense/stock totals for the current date-range selection,
    /// independent of how many pages have been loaded (same rationale as
    /// `getStatusCounts`). Used by the Dispensed/Stock Count tab labels so
    /// they don't grow as pagination fetches more pages.
    func getTypeCounts() -> (dispense: Int, stock: Int) {
        guard let user = userStore.fetchByUserId(userID) else { return (0, 0) }
        return (
            dispense: transactionStore.countByTimeRange(for: user, startTime: currentStartTs, endTime: currentEndTs, status: nil),
            stock: batchStore.countByDateRange(startTs: currentStartTs, endTs: currentEndTs, status: nil)
        )
    }

    // MARK: - Detail: Resolve + prepare by id
    /// Fetches the transaction from the store by id and prepares its step
    /// details. Returns the resolved entity (nil if it no longer exists).
    /// Used by the detail screen so it no longer depends on the caller having
    /// pre-seeded `filteredTransactionsOfUserByDate`.
    @discardableResult
    func prepareDetails(forTxnId txnId: Int64) -> PillCountTransactionEntity? {
        selectedTransactionId = txnId
        guard let txn = transactionStore.fetchById(txnId) else {
            detailsByStep = [:]
            return nil
        }
        prepareDetails(for: txn)
        return txn
    }

    // MARK: - Detail Screen: background-context fetch + decrypt

    /// Published while `prepareDetailScreen` is in flight, so
    /// `HistoryTransactionDetailView` can show a loading state instead of an
    /// empty/frozen-looking screen during the fetch.
    @Published var isLoadingDetailScreen: Bool = false

    /// Resolves everything `HistoryTransactionDetailView` needs for one
    /// transaction, entirely off the main thread.
    ///
    /// The transaction's full detail-row relationship (every count-step
    /// row, each individually AES-decrypted via the `NSManagedObject`
    /// encryption swizzle on fetch) was previously faulted in and decrypted
    /// synchronously on `viewContext` inside the view's `onAppear` — for a
    /// transaction with many detail/image rows this was slow enough to read
    /// as the screen freezing, with nothing shown while it ran. The fetch,
    /// every relationship read, and every row's decrypt now happen inside
    /// one background context's `performAndWait`; only the plain
    /// `TransactionDetailScreenModel` result (no `NSManagedObject`) crosses
    /// back to the main actor.
    func prepareDetailScreen(forTxnId txnId: Int64) async -> TransactionDetailScreenModel? {
        selectedTransactionId = txnId
        isLoadingDetailScreen = true
        defer { isLoadingDetailScreen = false }

        let model = await Task.detached(priority: .userInitiated) { () -> TransactionDetailScreenModel? in
            let bgContext = CoreDataManager.shared.backgroundContext
            return bgContext.performAndWait { () -> TransactionDetailScreenModel? in
                guard let txn = TransactionStore.shared.fetchById(txnId, in: bgContext) else {
                    return nil
                }

                let allDetails = TransactionDetailStore.shared.fetchAll(txnId: txnId, in: bgContext)
                let grouped = Dictionary(grouping: allDetails.filter { !$0.is_deleted }) { detail in
                    ControlledStep(rawValue: detail.type ?? "") ?? .containerInitiate
                }
                let detailsByStep = grouped.mapValues { rows in
                    rows.map {
                        TransactionDetailRowUIModel(
                            id: $0.txn_details_id,
                            imagePath: $0.image_path,
                            pillCount: $0.pill_count,
                            createdAt: $0.created_at
                        )
                    }
                }

                return TransactionDetailScreenModel(
                    txnId: txn.txn_id,
                    drugName: txn.drug?.drug_name ?? "",
                    ndc: txn.drug?.ndc ?? "",
                    drugType: txn.drug?.drug_type ?? "",
                    note: txn.note,
                    targetCount: txn.target_count,
                    createdAt: txn.created_at,
                    isDispense: txn.is_dispense,
                    isSubstitute: txn.is_substitute,
                    substituteDrugName: txn.substitueDrug?.drug_name,
                    substituteNdc: txn.substitueDrug?.ndc,
                    bottleInfoListJson: txn.bottle_info_list_json,
                    detailsByStep: detailsByStep
                )
            }
        }.value

        return model
    }

    // MARK: - Detail: Prepare step-grouped details
    func prepareDetails(for transaction: PillCountTransactionEntity) {
        isLoading = false

        guard let allDetails = transaction.pillCountTransactionDetails?.allObjects
                as? [PillCountTransactionDetailsEntity]
        else {
            detailsByStep = [:]
            return
        }
        let valid = allDetails.filter { !$0.is_deleted }
        detailsByStep = Dictionary(grouping: valid) { detail in
            ControlledStep(rawValue: detail.type ?? "") ?? .containerInitiate
        }
        DispatchQueue.main.async {
              self.isLoading = true
        }
    }

    // MARK: - Detail: Total count for a step (sum of pill_count in local details dict)
    func getTotalCount(step: ControlledStep) -> Int {
        (detailsByStep[step] ?? []).reduce(0) { $0 + Int($1.pill_count) }
    }

    // MARK: - Detail: Total pill count via PillScanViewModel logic
    func getTotalPillCount(
        for transaction: PillCountTransactionEntity,
        step: ControlledStep
    ) -> Int {
        let count = transactionDetailStore.totalCountForStep(
            txnId: transaction.txn_id,
            step: step
        )
        return Int(count)
    }

    // MARK: - Detail: Clear on disappear
    func clearSelectedTransaction() {
        selectedTransactionId = nil
        detailsByStep = [:]
    }

    // MARK: - Batch Detail: Prepare grouped transactions
    func prepareBatchDetails(for batchId: Int64) {
        selectedBatch = batchStore.fetchById(batchId)
        let stockTxns = stockTxnStore.fetchByBatch(batchId: batchId)
        groupedTransactionsForBatch = mapGroupedStockTxns(stockTxns: stockTxns)
    }

    private func mapGroupedStockTxns(stockTxns: [StockTxnEntity]) -> [GroupedTransaction] {
        let groupedByNdc = Dictionary(grouping: stockTxns) { $0.drug?.ndc ?? "" }

        return groupedByNdc.map { ndc, stockTxnList in
            let drugName = stockTxnList.first?.drug?.drug_name ?? "Unknown"
            let packageQty = stockTxnList.first?.drug?.package_qty ?? 0

            var lotDetails: [LotDetail] = []
            var totalSealed: Int32 = 0
            var totalOpen: Int32 = 0
            var sealedBottleQty: Int32 = 0
            var openedBottleCount: Int32 = 0

            for stockTxn in stockTxnList {
                let bottles = bottleInfoStore.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)

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
                packageQty:      packageQty,
                openPills:       totalOpen,
                lotDetails:      lotDetails
            )
        }
    }

    // MARK: - Batch Detail: Clear on disappear
    func clearBatchDetail() {
        selectedBatchId = nil
        selectedBatch = nil
        groupedTransactionsForBatch = []
    }

    // MARK: - Reset (on logout)
    func resetState() {
        filteredTransactionsOfUserByDate = []
        filteredBatchesOfUserByDate = []
        transactionRows = []
        batchRows = []
        transactionRowCache.removeAll()
        batchRowCache.removeAll()
        selectedTransactionId = nil
        detailsByStep = [:]
        selectedBatchId = nil
        selectedBatch = nil
        groupedTransactionsForBatch = []
    }
}
