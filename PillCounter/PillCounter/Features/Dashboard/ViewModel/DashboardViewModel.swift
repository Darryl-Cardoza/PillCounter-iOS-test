//
//  DashboardViewModel.swift
//  PillCounter
//
//  Owns all data loading, merging, filtering and stat-card derivation for
//  DashboardView. Self-contained: it talks only to the local data stores and
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

    var isHighPriority: Bool {
        switch self {
        case .dispense(let txn, _):
            return txn.txn_priority?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "high"
        case .inventory:
            return false
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
final class DashboardViewModel: ObservableObject {

    // Loaded data
    @Published private(set) var dispensePartial: [PillCountTransactionEntity] = []
    @Published private(set) var dispenseCompleted: [PillCountTransactionEntity] = []
    @Published private(set) var inventoryPartial: [BatchCountEntity] = []
    @Published private(set) var inventoryCompleted: [BatchCountEntity] = []
    @Published private(set) var pillCounts: [Int64: Int] = [:]
    @Published private(set) var batchNdcCounts: [Int64: Int] = [:]

    // Active stat-card filter (nil == no filter)
    @Published var activeFilterCardId: String? = nil

    // Injected stores default to the production singletons, so the view can
    // create `DashboardViewModel()` unchanged. Tests pass mocks.
    private let transactionStore: TransactionDataSource
    private let batchStore: BatchDataSource
    private let detailStore: TransactionDetailDataSource
    private let userStore: UserDataSource

    init(
        transactionStore: TransactionDataSource = TransactionStore.shared,
        batchStore: BatchDataSource = BatchStore.shared,
        detailStore: TransactionDetailDataSource = TransactionDetailStore.shared,
        userStore: UserDataSource = UserStore.shared
    ) {
        self.transactionStore = transactionStore
        self.batchStore = batchStore
        self.detailStore = detailStore
        self.userStore = userStore
    }

    // MARK: - Regular-count exclusion

    /// REGULAR-count transactions are inventory/stock counts surfaced as their own
    /// batch rows — they must never appear as dispense rows in either dashboard tab,
    /// under any stat-card filter. Excluded at the merge source so both the lists and
    /// the filtered views drop them.
    private func isRegular(_ txn: PillCountTransactionEntity) -> Bool {
        txn.count_type?.uppercased() == CountType.REGULAR.rawValue
    }

    // MARK: - Merged queues

    private var mergedQueueItems: [DashboardQueueItem] {
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
            if $0.isHighPriority != $1.isHighPriority { return $0.isHighPriority }
            return $0.sortDate < $1.sortDate
        }
    }

    private var mergedRecentItems: [DashboardQueueItem] {
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

    /// Maps a stat-card id to its filter without rebuilding the whole card
    /// array (which would re-scan the data just to read one `.filter`).
    private func filter(forCardId cardId: String) -> StatCardFilter? {
        switch cardId {
        case "disp-high-priority": return .highPriority
        case "disp-pending":       return .dispPending
        case "disp-cont-drugs":    return .controlled
        case "disp-hazardous":     return .hazardous
        case "inv-cycle-count":    return .cycleCount
        case "inv-pending-batch":  return .pendingBatch
        default:                   return nil
        }
    }

    private func filtered(_ items: [DashboardQueueItem]) -> [DashboardQueueItem] {
        guard let cardId = activeFilterCardId,
            let filter = filter(forCardId: cardId)
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

    func emptyQueueTitle() -> String {
        guard let cardId = activeFilterCardId,
            let card = statCards(iconColor: .clear).first(where: { $0.id == cardId })
        else {
            return L10n.Dashboard.EmptyState.caughtUpTitle
        }
        // If the active filter's own count is 0 there's genuinely nothing in that
        // category ("caught up"); otherwise items exist but none match the
        // current tab ("no matching").
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
        let fixed = transactionStore.fetchPartial(for: user, countType: .FIXED)
        let regular = transactionStore.fetchPartial(for: user, countType: .REGULAR)
        dispensePartial = (fixed + regular).filter {
            $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue
        }
        printQueue(dispensePartial)

        // Completed (Recent Activity) — all user transactions filtered to COMPLETED status
        let allUserTxns = transactionStore.fetchAll(for: user)
        dispenseCompleted = allUserTxns.filter {
            $0.status == CountStatus.COMPLETED.rawValue
        }

        var counts: [Int64: Int] = [:]
        for txn in dispensePartial + dispenseCompleted {
            counts[txn.txn_id] = Int(
                detailStore.totalCountForStep(
                    txnId: txn.txn_id,
                    step: .targetVerification
                )
            )
        }
        pillCounts = counts

        let batches = batchStore.fetchAllPartial()
        inventoryPartial = batches

        let completedBatches = batchStore.fetchAllCompleted()
        inventoryCompleted = completedBatches

        var ndcCounts: [Int64: Int] = [:]
        for batch in batches + completedBatches {
            ndcCounts[batch.batch_id] = batchStore.getTransactionCount(
                for: batch.batch_id
            )
        }
        batchNdcCounts = ndcCounts
    }

    // MARK: - Debug logging

    /// Compact one-line-per-transaction dump of the queue. DEBUG only.
    /// (The previous 40-field dump was removed — inspect a transaction in the
    /// debugger when you need every field.)
    private func printQueue(_ transactions: [PillCountTransactionEntity]) {
        #if DEBUG
        print("📋 TODAY'S QUEUE — \(transactions.count) transaction(s)")
        for (i, t) in transactions.enumerated() {
            print("  [\(i + 1)] txn=\(t.txn_id) drug=\(t.drug?.drug_name ?? "-") "
                + "type=\(t.count_type ?? "-") status=\(t.status ?? "-") "
                + "priority=\(t.txn_priority ?? "-") batch=\(t.batch_id) "
                + "ndcVerified=\(t.is_ndc_verfied)")
        }
        #endif
    }
}
