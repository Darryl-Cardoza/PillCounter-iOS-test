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

    private let localStorage = PillsDataLocalStorage.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Re-load whenever CoreData writes fire
        localStorage.transactionsDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.loadAll()
            }
            .store(in: &cancellables)

        loadAll()
    }

    // MARK: - Load

    func loadAll() {
        loadBatches()
        loadTransactions()
    }

    private func loadBatches() {
        let rawBatches = localStorage.fetchCompletedUnsyncedBatches()

        batches = rawBatches.map { batch in
            let ndcCount = localStorage.getTransactionCount(for: batch.batch_id)
            return batch.toStockData(ndcCount: ndcCount)
        }
    }
    
    private func loadTransactions() {
        let txns = localStorage.fetchCompletedUnsyncedTransactions()
       
        transactions = txns.map { txn in
               let counted = PillsDataLocalStorage.shared.getTotalCountForStep(
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
