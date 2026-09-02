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
    /// When non-nil (PMS off), tapping a dispense row calls this instead of
    /// navigating — the dispense flow is gated on PMS integration.
    var onDispenseBlocked: (() -> Void)? = nil

    var body: some View {
        switch item {
        case .dispense(let row):
            DispenseItemRowView(data: row)
                .onTapGesture {
                    if let onDispenseBlocked {
                        onDispenseBlocked()
                        return
                    }
                    // Self-describing navigation: pass the txn id + scan type. The
                    // scan screen fetches the txn and sets up the session onAppear.
                    let scanType: ScanType = row.isNdcVerified ? .resumeCount : .barcode
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(scanType, txnId: row.txnId))))
                        )
                    )
                }

        case .inventory(let row):
            StockItemRowView(data: row)
                .onTapGesture {
                    // Pass the batch id; the scan screen resumes the session onAppear.
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(.stockCount, batchId: row.batchId))))
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
    /// When non-nil (PMS off), tapping a completed dispense row calls this
    /// instead of opening its history detail — dispense is PMS-gated.
    var onDispenseBlocked: (() -> Void)? = nil

    var body: some View {
        switch item {
        case .dispense(let row):
            DispenseItemRowView(data: row)
                .onTapGesture {
                    if let onDispenseBlocked {
                        onDispenseBlocked()
                        return
                    }
                    router.navigate(
                        to: .authentication(.user(.userSettings(.HistoryTransactionDetail(row.txnId))))
                    )
                }

        case .inventory(let row):
            StockItemRowView(data: row)
                .onTapGesture {
                    router.navigate(
                        to: .authentication(.user(.userSettings(.HistoryBatchDetail(row.batchId))))
                    )
                }
        }
    }
}
