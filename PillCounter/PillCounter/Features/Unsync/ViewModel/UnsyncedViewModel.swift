//
//  UnsycedViewModel.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//

//
//  UnsyncedViewModel.swift
//  PillCounter
//

import Foundation
import Combine

@MainActor
final class UnsyncedViewModel: ObservableObject {

    // MARK: - Published State

    @Published var batches: [StockData] = []
    @Published var transactions: [TransactionRowData] = []
    /// True counts, independent of the capped display lists above — the
    /// section headers show these, not `batches.count`/`transactions.count`,
    /// so a large unsynced backlog still reports its real size.
    @Published var totalUnsyncedBatchCount: Int = 0
    @Published var totalUnsyncedTransactionCount: Int = 0
    @Published var isSyncing: Bool = false
    @Published var syncError: String? = nil

    // MARK: - Private

    private let batchStore: BatchDataSource
    private let transactionStore: TransactionDataSource
    private let transactionDetailStore: TransactionDetailDataSource
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Dependencies default to the production singletons, so existing call
    /// sites (`UnsyncedViewModel()`) keep working unchanged. Tests pass mocks.
    init(
        batchStore: BatchDataSource = BatchStore.shared,
        transactionStore: TransactionDataSource = TransactionStore.shared,
        transactionDetailStore: TransactionDetailDataSource = TransactionDetailStore.shared
    ) {
        self.batchStore = batchStore
        self.transactionStore = transactionStore
        self.transactionDetailStore = transactionDetailStore

        // Debounced so a burst of writes (e.g. bulk data generation, HL7
        // sync catching up) triggers one reload instead of one per write.
        Publishers.Merge(
            batchStore.transactionsDidChange,
            transactionStore.transactionsDidChange
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            Task { await self?.loadAll() }
        }
        .store(in: &cancellables)
    }

    // MARK: - Load

    /// Unsynced is a queue screen, not a full-history browser — capping the
    /// display list to the oldest `pageLimit` (they're sorted oldest-first,
    /// so this is "sync these next") keeps every fetch bounded regardless of
    /// how large the backlog has grown. `totalUnsyncedBatchCount`/
    /// `totalUnsyncedTransactionCount` report the real total separately.
    private let pageLimit = 100

    func loadAll() async {
        loadBatches()
        loadTransactions()
    }

    private func loadBatches() {
        let rawBatches = batchStore.fetchCompletedUnsyncedPage(limit: pageLimit, offset: 0)
        totalUnsyncedBatchCount = batchStore.countCompletedUnsynced()

        let ndcCounts = batchStore.transactionCounts(for: rawBatches.map { $0.batch_id })
        batches = rawBatches.map { batch in
            batch.toStockData(ndcCount: ndcCounts[batch.batch_id] ?? 0)
        }
    }

    private func loadTransactions() {
        let txns = transactionStore.fetchCompletedUnsyncedPage(limit: pageLimit, offset: 0)
        totalUnsyncedTransactionCount = transactionStore.countCompletedUnsynced()

        let stepTotals = transactionDetailStore.totalCountsForSteps(
            txnIds: txns.map { $0.txn_id }, step: .targetVerification
        )
        transactions = txns.map { txn in
            txn.toRowData(pillCount: Int(stepTotals[txn.txn_id] ?? 0))
        }
    }
    
 

    // MARK: - Sync All

    func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil

        // TODO: Replace with your actual sync API call
        // Example:
        // do {
        //     try await SyncService.shared.syncBatches(batches)
        //     for batch in localStorage.fetchCompletedUnsyncedBatches() {
        //         localStorage.markBatchSynced(batchId: batch.batch_id)
        //     }
        //     loadAll()
        // } catch {
        //     syncError = error.localizedDescription
        // }

        isSyncing = false
    }
}
