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
        case .completed: batches = batches.filter { $0.status == "completed" }
        case .pending:   batches = batches.filter { $0.status == "partial" }
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
    func softDeleteTransactionsForSelectedDate(
        startDate: Date,
        endDate: Date,
        filter: HistoryFilterType
    ) async {
        let toDelete = filteredTransactionsOfUserByDate
        guard !toDelete.isEmpty else { return }
        for txn in toDelete {
            pillLocalDB.softDeleteTransaction(txnId: txn.txn_id)
        }
        await getTransactionsByDate(startDate: startDate, endDate: endDate, filter: filter)
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
                completed: batches.filter { $0.status == "completed" }.count,
                pending:   batches.filter { $0.status == "partial" }.count
            )
        }
    }

    // MARK: - Detail: Prepare step-grouped details
    func prepareDetails(for transaction: PillCountTransactionEntity) {
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
    }
}
