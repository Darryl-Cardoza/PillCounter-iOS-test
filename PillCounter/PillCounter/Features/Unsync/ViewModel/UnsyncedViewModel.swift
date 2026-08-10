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

        batchStore.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.loadAll() }
            .store(in: &cancellables)

        transactionStore.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.loadAll() }
            .store(in: &cancellables)

        loadAll()
    }

    // MARK: - Load

    func loadAll() {
        loadBatches()
        loadTransactions()
    }

    private func loadBatches() {
        let rawBatches = batchStore.fetchCompletedUnsynced()

        batches = rawBatches.map { batch in
            let ndcCount = batchStore.getTransactionCount(for: batch.batch_id)
            return batch.toStockData(ndcCount: ndcCount)
        }
    }

    private func loadTransactions() {
        let txns = transactionStore.fetchCompletedUnsynced()

        transactions = txns.map { txn in
               let counted = transactionDetailStore.totalCountForStep(
                   txnId: txn.txn_id,
                   step: .targetVerification
               )
               print("Transaction Row \(txn) \(counted)")
               return txn.toRowData(pillCount: Int(counted))
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
