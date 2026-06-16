//
//  DashboardQueueRows.swift
//  PillCounter
//
//  Row views for the dashboard's two queue tabs:
//  - `DashboardTodaysQueueRow`  — Today's Queue (partial items → resume scan/count)
//  - `DashboardRecentActivityRow` — Recent Activity (completed items → history detail)
//
//  Both render a dispense or inventory row and navigate via the route. Setup of
//  the destination session happens on the target screen (the route carries the
//  id), so these rows only need the Router.
//

import SwiftUI

/// Today's Queue row — partial transactions/batches. Tapping resumes the
/// active scan (dispense) or stock-count (inventory) screen.
struct DashboardTodaysQueueRow: View {
    let item: DashboardQueueItem
    let router: Router

    var body: some View {
        switch item {
        case .dispense(let txn, let pillCount):
            DispenseItemRowView(data: txn.toRowData(pillCount: pillCount))
                .onTapGesture {
                    // Self-describing navigation: pass the txn id + scan type. The
                    // scan screen fetches the txn and sets up the session onAppear.
                    let scanType: ScanType = txn.is_ndc_verfied ? .resumeCount : .barcode
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(scanType, txnId: txn.txn_id))))
                        )
                    )
                }

        case .inventory(let batch, let ndcCount):
            StockItemRowView(data: batch.toStockData(ndcCount: ndcCount))
                .onTapGesture {
                    // Pass the batch id; the scan screen resumes the session onAppear.
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(.stockCount, batchId: batch.batch_id))))
                        )
                    )
                }
        }
    }
}

/// Recent Activity row — completed transactions/batches. Tapping opens the
/// corresponding history detail screen (which fetches the entity by id).
struct DashboardRecentActivityRow: View {
    let item: DashboardQueueItem
    let router: Router

    var body: some View {
        switch item {
        case .dispense(let txn, let pillCount):
            DispenseItemRowView(data: txn.toRowData(pillCount: pillCount))
                .onTapGesture {
                    router.navigate(
                        to: .authentication(.user(.userSettings(.HistoryTransactionDetail(txn.txn_id))))
                    )
                }

        case .inventory(let batch, let ndcCount):
            StockItemRowView(data: batch.toStockData(ndcCount: ndcCount))
                .onTapGesture {
                    router.navigate(
                        to: .authentication(.user(.userSettings(.HistoryBatchDetail(batch.batch_id))))
                    )
                }
        }
    }
}
