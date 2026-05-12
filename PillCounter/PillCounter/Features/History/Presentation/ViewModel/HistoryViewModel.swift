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

    // MARK: - Dependencies
    private let pillLocalDB = PillsDataLocalStorage.shared
    private let userLocalDB = UserLocalDataSource.shared

    // MARK: - AppStorage
    @AppStorage(AppStorageManager.AppStorageKeys.userId) private var userID: String = ""

    // MARK: - Published: Raw filtered data
    @Published var filteredTransactionsOfUserByDate: [PillCountTransactionEntity] = []
    @Published var filteredBatchesOfUserByDate: [BatchCountEntity] = []

    // MARK: - Published: Mapped UI rows
    @Published var transactionRows: [TransactionRowData] = []
    @Published var batchRows: [StockData] = []

    // MARK: - Published: Counts
    @Published var historyTotalTransactionsCount: Int = 0

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



    // MARK: - Fetch Transactions by Date
    func getTransactionsByDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType
    ) async {
        guard let user = userLocalDB.getUserByUserId(by: userID) else {
            filteredTransactionsOfUserByDate = []
            return
        }

        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: endDate)
        )!

        let startTs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs   = Int64(endOfDay.timeIntervalSince1970 * 1000)

        let allTransactions = userLocalDB.getTransactionsForUserFilteredByDate(
            for: user,
            startDateTs: startTs,
            endDateTs: endTs
        )

        let finalTransactions: [PillCountTransactionEntity]
        switch filter {
        case .regular:
            return
        case .fixed:
            finalTransactions = allTransactions.filter {
                $0.count_type == CountType.FIXED.rawValue
            }
        }

        filteredTransactionsOfUserByDate = finalTransactions
        historyTotalTransactionsCount = finalTransactions.count
    }

    // MARK: - Fetch Batches by Date
    func getBatchesByDate(startDate: Date, endDate: Date) async {
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: endDate)
        )!

        let startTs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTs   = Int64(endOfDay.timeIntervalSince1970 * 1000)

        filteredBatchesOfUserByDate = pillLocalDB.getBatchesForUserFilteredByDate(
            startDateTs: startTs,
            endDateTs: endTs
        )
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

        transactionRows = txns.map { txn in
               let counted = PillsDataLocalStorage.shared.getTotalCountForStep(
                   txnId: txn.txn_id,
                   step: .targetVerification
               )
               print("Transaction Row \(txn) \(counted)")
               return txn.toRowData(pillCount: Int(counted))
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

        batchRows = batches.map { batch in
            let count = pillLocalDB.getTransactionCount(for: batch.batch_id)
            return batch.toStockData(ndcCount: count)
        }
    }

    // MARK: - Soft Delete for Selected Date
//    func softDeleteTransactionsForSelectedDate(
//        startDate: Date,
//        endDate: Date,
//        filter: HistoryFilterType
//    ) async {
//        let toDelete = filteredTransactionsOfUserByDate
//        guard !toDelete.isEmpty else { return }
//        for txn in toDelete {
//            pillLocalDB.softDeleteTransaction(txnId: txn.txn_id)
//        }
//        await getTransactionsByDate(startDate: startDate, endDate: endDate, filter: filter)
//    }
    
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
                pillLocalDB.softDeleteTransaction(txnId: txn.txn_id)
            }
            await getTransactionsByDate(startDate: startDate, endDate: endDate, filter: filter)

        case .regular:
            let batchIdsToDelete = Set(batchRows.map { $0.batchId })  // ← StockData.batchId field
            let toDelete = filteredBatchesOfUserByDate.filter {
                batchIdsToDelete.contains($0.batch_id)
            }
            guard !toDelete.isEmpty else { return }

            // deleteBatches soft-deletes both the batch AND its child transactions in one call
            pillLocalDB.deleteBatches(ids: Set(toDelete.map { $0.batch_id }))

            await getBatchesByDate(startDate: startDate, endDate: endDate)
        }

        applyFilters(status: status, search: search)
    }

    // MARK: - Soft Delete Single Transaction (used from detail view)
    func softDeleteTransaction(txnId: Int64) async {
        pillLocalDB.softDeleteTransaction(txnId: txnId)
    }

    // MARK: - Status Counts
    func getStatusCounts(for type: HistoryFilterType) -> (all: Int, completed: Int, pending: Int) {
        if type == .fixed {
            let txns = filteredTransactionsOfUserByDate
            return (
                all: txns.count,
                completed: txns.filter { $0.status == CountStatus.COMPLETED.rawValue }.count,
                pending:   txns.filter { $0.status == CountStatus.PARTIAL.rawValue }.count
            )
        } else {
            let batches = filteredBatchesOfUserByDate
            return (
                all: batches.count,
                completed: batches.filter { $0.status == CountStatus.COMPLETED.rawValue }.count,
                pending:   batches.filter { $0.status == CountStatus.PARTIAL.rawValue }.count
            )
        }
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
        let count = pillLocalDB.getTotalCountForStep(
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
        selectedBatch = pillLocalDB.fetchBatchById(batchId)
        let txns = pillLocalDB.fetchTransactionsByBatch(batchId: batchId)
        groupedTransactionsForBatch = mapGroupedTransactions(txns: txns)
    }

    private func mapGroupedTransactions(txns: [PillCountTransactionEntity]) -> [GroupedTransaction] {
        let groupedByNdc = Dictionary(grouping: txns) { $0.drug?.ndc ?? "" }
        return groupedByNdc.map { ndc, txnList in
            let drugName = txnList.first?.drug?.drug_name ?? "Unknown"
            let lotGrouped = Dictionary(grouping: txnList) { "\($0.lot_no ?? "")|\($0.expiry ?? "")" }
            var lotDetails: [LotDetail] = []
            var totalSealed: Int32 = 0
            var totalOpen: Int32 = 0
            for (_, lotTxns) in lotGrouped {
                let sealed = lotTxns.reduce(0) { $0 + ($1.bottle_qty * ($1.drug?.package_qty ?? 0)) }
                let open = lotTxns.reduce(0) { $0 + $1.loose_qty }
                totalSealed += sealed
                totalOpen += open
                lotDetails.append(LotDetail(
                    lot: lotTxns.first?.lot_no ?? "",
                    expiry: lotTxns.first?.expiry ?? "",
                    sealedQty: sealed,
                    openQty: open
                ))
            }
            return GroupedTransaction(
                txnId: txnList.first?.txn_id ?? 0,
                ndc: ndc,
                drugName: drugName,
                total: totalSealed + totalOpen,
                sealedBottles: totalSealed,
                sealedBottleQty: txnList.first?.bottle_qty ?? 0,
                openPills: totalOpen,
                lotDetails: lotDetails
            )
        }
    }

    // MARK: - Batch Detail: Soft delete selected NDCs
    func softDeleteNdcsFromBatch(ndcs: Set<String>, batchId: Int64) {
        let txns = pillLocalDB.fetchTransactionsByBatch(batchId: batchId)
        for txn in txns where ndcs.contains(txn.drug?.ndc ?? "") {
            pillLocalDB.softDeleteTransaction(txnId: txn.txn_id)
        }
        prepareBatchDetails(for: batchId)
    }

    // MARK: - Batch Detail: Clear on disappear
    func clearBatchDetail() {
        selectedBatchId = nil
        selectedBatch = nil
        groupedTransactionsForBatch = []
    }

    // MARK: - Helper: Parse CountType from raw string
    func countType(from rawValue: String?) -> CountType {
        guard let rawValue, let type = CountType(rawValue: rawValue) else { return .REGULAR }
        return type
    }

    // MARK: - Reset (on logout)
    func resetState() {
        filteredTransactionsOfUserByDate = []
        filteredBatchesOfUserByDate = []
        transactionRows = []
        batchRows = []
        historyTotalTransactionsCount = 0
        selectedTransactionId = nil
        detailsByStep = [:]
        selectedBatchId = nil
        selectedBatch = nil
        groupedTransactionsForBatch = []
    }
}
