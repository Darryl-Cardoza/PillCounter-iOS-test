//
//  NewDashboardViewModel.swift
//  PillCounter
//
//  Owns all data loading, merging, filtering and stat-card derivation for
//  NewDashboardView. Self-contained: it talks only to the local data stores and
//  has no dependency on any other view model. The view keeps UI layout and
//  navigation; this type keeps the data.
//

import SwiftUI

// MARK: - Unified queue item model

enum DashboardQueueItem: Identifiable {
    case dispense(PillCountTransactionEntity, pillCount: Int)
    case inventory(BatchCountEntity, ndcCount: Int)

    var id: String {
        switch self {
        case .dispense(let txn, _): return "d-\(txn.txn_id)"
        case .inventory(let batch, _): return "i-\(batch.batch_id)"
        }
    }

    var sortDate: Int64 {
        switch self {
        case .dispense(let txn, _): return txn.created_at
        case .inventory(let batch, _): return batch.start_date_time
        }
    }
}

// MARK: - Stat card model

enum StatCardFilter {
    case highPriority
    case hazardous
    case controlled
    case dispPending
    case cycleCount
    case pendingBatch
}

struct DashboardStatCard: Identifiable {
    let id: String
    let iconName: String
    let iconColor: Color
    let count: Int
    let label: String
    let filter: StatCardFilter?
}

// MARK: - View model

@MainActor
final class NewDashboardViewModel: ObservableObject {

    // Loaded data
    @Published private(set) var dispensePartial: [PillCountTransactionEntity] = []
    @Published private(set) var dispenseCompleted: [PillCountTransactionEntity] = []
    @Published private(set) var inventoryPartial: [BatchCountEntity] = []
    @Published private(set) var inventoryCompleted: [BatchCountEntity] = []
    @Published private(set) var pillCounts: [Int64: Int] = [:]
    @Published private(set) var batchNdcCounts: [Int64: Int] = [:]

    // Active stat-card filter (nil == no filter)
    @Published var activeFilterCardId: String? = nil

    private let transactionDAO = TransactionStore.shared
    private let batchDAO = BatchStore.shared
    private let detailDAO = TransactionDetailStore.shared
    private let userStore = UserStore.shared

    // MARK: - Regular-count exclusion

    /// REGULAR-count transactions are inventory/stock counts surfaced as their own
    /// batch rows — they must never appear as dispense rows in either dashboard tab,
    /// under any stat-card filter. Excluded at the merge source so both the lists and
    /// the filtered views drop them.
    private func isRegular(_ txn: PillCountTransactionEntity) -> Bool {
        txn.count_type?.uppercased() == CountType.REGULAR.rawValue
    }

    // MARK: - Merged queues

    var mergedQueueItems: [DashboardQueueItem] {
        let dispenseItems = dispensePartial
            .filter { !isRegular($0) }
            .map {
                DashboardQueueItem.dispense(
                    $0,
                    pillCount: pillCounts[$0.txn_id] ?? 0
                )
            }
        let inventoryItems = inventoryPartial.map {
            DashboardQueueItem.inventory(
                $0,
                ndcCount: batchNdcCounts[$0.batch_id] ?? 0
            )
        }
        return (dispenseItems + inventoryItems).sorted {
            $0.sortDate < $1.sortDate
        }
    }

    var mergedRecentItems: [DashboardQueueItem] {
        let dispenseItems = dispenseCompleted
            .filter { !isRegular($0) }
            .map {
                DashboardQueueItem.dispense(
                    $0,
                    pillCount: pillCounts[$0.txn_id] ?? 0
                )
            }
        let inventoryItems = inventoryCompleted.map {
            DashboardQueueItem.inventory(
                $0,
                ndcCount: batchNdcCounts[$0.batch_id] ?? 0
            )
        }
        return (dispenseItems + inventoryItems).sorted {
            $0.sortDate > $1.sortDate
        }
    }

    var filteredQueueItems: [DashboardQueueItem] {
        filtered(mergedQueueItems)
    }

    var filteredRecentItems: [DashboardQueueItem] {
        filtered(mergedRecentItems)
    }

    // MARK: - Filtering

    private func applyFilter(
        _ filter: StatCardFilter,
        to items: [DashboardQueueItem]
    ) -> [DashboardQueueItem] {
        items.filter { item in
            switch (item, filter) {
            case (.dispense(let txn, _), .highPriority):
                return txn.txn_priority?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "high"
            case (.dispense(let txn, _), .hazardous):
                return txn.drug?.is_hazardous == true
            case (.dispense(let txn, _), .controlled):
                let t =
                    txn.drug?.drug_type?.trimmingCharacters(in: .whitespaces)
                    ?? ""
                return !t.isEmpty
            case (.dispense, .dispPending):
                return true
            case (.inventory(let batch, _), .cycleCount):
                return !((batch.req_id_from_pms ?? "").isEmpty)
            case (.inventory(let batch, _), .pendingBatch):
                return (batch.req_id_from_pms ?? "").isEmpty
            default:
                return false
            }
        }
    }

    private func filtered(_ items: [DashboardQueueItem]) -> [DashboardQueueItem] {
        guard let cardId = activeFilterCardId,
            let card = statCards(iconColor: .clear).first(where: { $0.id == cardId }),
            let filter = card.filter
        else {
            return items
        }
        return applyFilter(filter, to: items)
    }

    /// Toggle a stat-card filter on/off.
    func toggleFilter(cardId: String) {
        activeFilterCardId = activeFilterCardId == cardId ? nil : cardId
    }

    // MARK: - Stat cards built from live data

    /// `iconColor` is supplied by the view from the active theme so this type
    /// stays free of any `AppColors` (EnvironmentObject) dependency.
    func statCards(iconColor: Color) -> [DashboardStatCard] {
        // Counts must match the dispense rows shown in the tabs, which exclude
        // REGULAR (inventory) transactions — so count against the same slice.
        let dispensePartialFixed = dispensePartial.filter { !isRegular($0) }
        return [
            DashboardStatCard(
                id: "disp-high-priority",
                iconName: "icon_priority",
                iconColor: iconColor,
                count: dispensePartialFixed.filter {
                    $0.txn_priority?.trimmingCharacters(in: .whitespaces)
                        .lowercased() == "high"
                }.count,
                label: L10n.Dashboard.StatCards.highPriority,
                filter: .highPriority
            ),
            DashboardStatCard(
                id: "disp-pending",
                iconName: "partial",
                iconColor: iconColor,
                count: dispensePartialFixed.count,
                label: L10n.Dashboard.StatCards.dispensePending,
                filter: .dispPending
            ),
            DashboardStatCard(
                id: "disp-cont-drugs",
                iconName: "icon_controlled",
                iconColor: iconColor,
                count: dispensePartialFixed.filter {
                    let t =
                        $0.drug?.drug_type?.trimmingCharacters(in: .whitespaces)
                        ?? ""
                    return !t.isEmpty
                }.count,
                label: L10n.Dashboard.StatCards.controlledDrug,
                filter: .controlled
            ),
            DashboardStatCard(
                id: "disp-hazardous",
                iconName: "icon_hazardous",
                iconColor: iconColor,
                count: dispensePartialFixed.filter { $0.drug?.is_hazardous == true }
                    .count,
                label: L10n.Dashboard.StatCards.hazardous,
                filter: .hazardous
            ),
            DashboardStatCard(
                id: "inv-cycle-count",
                iconName: "new_rx",
                iconColor: iconColor,
                count: inventoryPartial.filter {
                    !($0.req_id_from_pms ?? "").isEmpty
                }.count,
                label: L10n.Dashboard.StatCards.cycleCount,
                filter: .cycleCount
            ),
            DashboardStatCard(
                id: "inv-pending-batch",
                iconName: "batch_icon",
                iconColor: iconColor,
                count: inventoryPartial.filter {
                    ($0.req_id_from_pms ?? "").isEmpty
                }.count,
                label: L10n.Dashboard.StatCards.pendingBatch,
                filter: .pendingBatch
            ),
        ]
    }

    // MARK: - Empty-state copy

    func emptyQueueTitle(iconColor: Color) -> String {
        guard let cardId = activeFilterCardId,
            let card = statCards(iconColor: iconColor).first(where: { $0.id == cardId })
        else {
            return L10n.Dashboard.EmptyState.caughtUpTitle
        }
        return card.count == 0
            ? L10n.Dashboard.EmptyState.caughtUpTitle
            : L10n.Dashboard.EmptyState.noMatchingTitle
    }

    func emptyQueueSubtitle(selectedQueueTab: Int) -> String {
        selectedQueueTab == 0
            ? L10n.Dashboard.EmptyState.noPendingSubtitle
            : L10n.Dashboard.EmptyState.noRecentSubtitle
    }

    // MARK: - Data loading

    func loadQueueData(userId: String) {
        guard let user = userStore.fetchByUserId(userId) else { return }

        // Partial (Today's Queue)
        let fixed = transactionDAO.fetchPartial(for: user, countType: .FIXED)
        let regular = transactionDAO.fetchPartial(for: user, countType: .REGULAR)
        dispensePartial = (fixed + regular).filter {
            $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue
        }
        printQueue(dispensePartial)

        // Completed (Recent Activity) — all user transactions filtered to COMPLETED status
        let allUserTxns = transactionDAO.fetchAll(for: user)
        dispenseCompleted = allUserTxns.filter {
            $0.status == CountStatus.COMPLETED.rawValue
        }

        var counts: [Int64: Int] = [:]
        for txn in dispensePartial + dispenseCompleted {
            counts[txn.txn_id] = Int(
                detailDAO.totalCountForStep(
                    txnId: txn.txn_id,
                    step: .targetVerification
                )
            )
        }
        pillCounts = counts

        let batches = batchDAO.fetchAllPartial()
        inventoryPartial = batches

        let completedBatches = batchDAO.fetchAllCompleted()
        inventoryCompleted = completedBatches

        var ndcCounts: [Int64: Int] = [:]
        for batch in batches + completedBatches {
            ndcCounts[batch.batch_id] = batchDAO.getTransactionCount(
                for: batch.batch_id
            )
        }
        batchNdcCounts = ndcCounts
    }

    /// Fetch a fresh batch for navigation. Returns nil if it no longer exists.
    func freshBatch(batchId: Int64) -> BatchCountEntity? {
        batchDAO.fetchById(batchId)
    }

    // MARK: - Debug logging

    private func printQueue(_ transactions: [PillCountTransactionEntity]) {
        #if DEBUG
        let sep = String(repeating: "─", count: 80)
        print("\n\(sep)")
        print("📋 TODAY'S QUEUE — \(transactions.count) transaction(s)")
        print(sep)
        for (i, t) in transactions.enumerated() {
            print("[\(i + 1)] txn_id          : \(t.txn_id)")
            print("    local_id        : \(t.local_id)")
            print("    drug_id         : \(t.drug_id)")
            print("    drug_name       : \(t.drug?.drug_name ?? "-")")
            print("    drug_ndc        : \(t.drug?.ndc ?? "-")")
            print("    drug_type       : \(t.drug?.drug_type ?? "-")")
            print("    is_hazardous    : \(t.drug?.is_hazardous ?? false)")
            print("    count_type      : \(t.count_type ?? "-")")
            print("    status          : \(t.status ?? "-")")
            print("    target_count    : \(t.target_count)")
            print("    bottle_qty      : \(t.bottle_qty)")
            print("    loose_qty       : \(t.loose_qty)")
            print("    batch_id        : \(t.batch_id)")
            print("    rx_no           : \(t.rx_no ?? "-")")
            print("    req_id          : \(t.req_id ?? "-")")
            print("    txn_priority    : \(t.txn_priority ?? "-")")
            print("    bucket_id       : \(t.bucket_id ?? "-")")
            print("    workflow_step   : \(t.workflow_step ?? "-")")
            print("    barcode_image   : \(t.barcode_image ?? "-")")
            print("    lot_no          : \(t.lot_no ?? "-")")
            print("    expiry          : \(t.expiry ?? "-")")
            print("    note            : \(t.note ?? "-")")
            print("    patient_name    : \(t.patient_name ?? "-")")
            print("    refill_no       : \(t.refill_no ?? "-")")
            print("    substitute_drug_id: \(t.substitute_drug_id)")
            print("    is_from_pms     : \(t.is_from_pms)")
            print("    is_ndc_verfied  : \(t.is_ndc_verfied)")
            print("    is_substitute   : \(t.is_substitute)")
            print("    is_synced       : \(t.is_synced)")
            print("    is_deleted      : \(t.is_deleted)")
            print("    gloves_detected : \(t.gloves_detected)")
            print("    created_at      : \(t.created_at)")
            print("    updated_at      : \(t.updated_at)")
            print("hazardous tray detected: \(t.hazardous_tray_detected)")
            if i < transactions.count - 1 {
                print("    \(String(repeating: "·", count: 40))")
            }
        }
        print(sep)
        #endif
    }
}
