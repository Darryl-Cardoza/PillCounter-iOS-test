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

    // Loaded data (paginated — grows as the user scrolls; never used for counts)
    @Published private(set) var dispensePartial: [PillCountTransactionEntity] = []
    @Published private(set) var dispenseCompleted: [PillCountTransactionEntity] = []
    @Published private(set) var inventoryPartial: [BatchCountEntity] = []
    @Published private(set) var inventoryCompleted: [BatchCountEntity] = []
    @Published private(set) var pillCounts: [Int64: Int] = [:]
    @Published private(set) var batchNdcCounts: [Int64: Int] = [:]

    /// Full (unpaginated) pending sets, fetched once per `loadQueueData` /
    /// data-change — used ONLY to compute stable stat-card counts. Kept
    /// separate from the paginated `dispensePartial`/`inventoryPartial`
    /// display arrays so the counts don't change as more pages load.
    private var allPendingDispense: [PillCountTransactionEntity] = []
    private var allPendingInventory: [BatchCountEntity] = []

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
        !txn.is_dispense
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
        // Counts come from the full unpaginated pending set (allPendingDispense/
        // allPendingInventory), NOT the paginated display arrays — otherwise the
        // numbers would change as more pages loaded while scrolling. Counts must
        // match the dispense rows shown in the tabs, which exclude REGULAR
        // (inventory) transactions — so count against the same slice.
        let dispensePartialFixed = allPendingDispense.filter { !isRegular($0) }
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
                count: allPendingInventory.filter {
                    !($0.req_id_from_pms ?? "").isEmpty
                }.count,
                label: L10n.Dashboard.StatCards.cycleCount,
                filter: .cycleCount
            ),
            DashboardStatCard(
                id: "inv-pending-batch",
                iconName: "batch_icon",
                iconColor: iconColor,
                count: allPendingInventory.filter {
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

    /// Both Dashboard tabs page through all matching data — load more as the
    /// user scrolls — rather than a hard cap, so a large pending queue or a
    /// large day's activity is fully browsable instead of silently truncated.
    let dashboardPageSize = 30

    @Published private(set) var hasMoreQueue = true
    @Published private(set) var isLoadingMoreQueue = false
    private var queueFixedOffset = 0
    private var queueRegularOffset = 0
    private var queueBatchOffset = 0
    private var queueFixedExhausted = false
    private var queueRegularExhausted = false
    private var queueBatchExhausted = false

    @Published private(set) var hasMoreRecentActivity = true
    @Published private(set) var isLoadingMoreRecentActivity = false
    private var recentTxnOffset = 0
    private var recentBatchOffset = 0
    private var recentTxnExhausted = false
    private var recentBatchExhausted = false
    private var todayStartTs: Int64 = 0
    private var todayEndTs: Int64 = 0

    func loadQueueData(userId: String) {
        guard let user = userStore.fetchByUserId(userId) else { return }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        todayStartTs = Int64(startOfToday.timeIntervalSince1970 * 1000)
        todayEndTs = Int64(Date().timeIntervalSince1970 * 1000)

        // Stat-card counts: fetched once, unpaginated, independent of the
        // display lists below — so the counts don't shift as more pages load.
        let allFixed = transactionStore.fetchPartial(for: user, isDispense: true)
        let allRegular = transactionStore.fetchPartial(for: user, isDispense: false)
        allPendingDispense = (allFixed + allRegular).filter {
            $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue
        }
        allPendingInventory = batchStore.fetchAllPartial()

        // Today's Queue — first page of pending dispense + inventory items;
        // loadMoreQueueIfNeeded fetches the rest.
        queueFixedOffset = 0
        queueRegularOffset = 0
        queueBatchOffset = 0
        queueFixedExhausted = false
        queueRegularExhausted = false
        queueBatchExhausted = false
        hasMoreQueue = true

        let fixedPage = transactionStore.fetchPartialPage(for: user, isDispense: true, limit: dashboardPageSize, offset: queueFixedOffset)
        queueFixedOffset += fixedPage.count
        queueFixedExhausted = fixedPage.count < dashboardPageSize

        let regularPage = transactionStore.fetchPartialPage(for: user, isDispense: false, limit: dashboardPageSize, offset: queueRegularOffset)
        queueRegularOffset += regularPage.count
        queueRegularExhausted = regularPage.count < dashboardPageSize

        dispensePartial = (fixedPage + regularPage).filter {
            $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue
        }
        printQueue(dispensePartial)

        let batchPage = batchStore.fetchAllPartialPage(limit: dashboardPageSize, offset: queueBatchOffset)
        queueBatchOffset += batchPage.count
        queueBatchExhausted = batchPage.count < dashboardPageSize
        inventoryPartial = batchPage

        hasMoreQueue = !(queueFixedExhausted && queueRegularExhausted && queueBatchExhausted)

        // Recent Activity — first page of today's completed activity;
        // loadMoreRecentActivityIfNeeded fetches the rest.
        recentTxnOffset = 0
        recentBatchOffset = 0
        recentTxnExhausted = false
        recentBatchExhausted = false
        hasMoreRecentActivity = true

        let txnPage = transactionStore.fetchByTimeRangePage(
            for: user, startTime: todayStartTs, endTime: todayEndTs,
            limit: dashboardPageSize, offset: recentTxnOffset
        )
        recentTxnOffset += txnPage.count
        recentTxnExhausted = txnPage.count < dashboardPageSize
        dispenseCompleted = txnPage.filter { $0.status == CountStatus.COMPLETED.rawValue }

        let completedBatchPage = batchStore.fetchByDateRangePage(
            startTs: todayStartTs, endTs: todayEndTs, limit: dashboardPageSize, offset: recentBatchOffset
        )
        recentBatchOffset += completedBatchPage.count
        recentBatchExhausted = completedBatchPage.count < dashboardPageSize
        let completedBatches = completedBatchPage.filter { $0.status == CountStatus.COMPLETED.rawValue }
        inventoryCompleted = completedBatches

        hasMoreRecentActivity = !(recentTxnExhausted && recentBatchExhausted)

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

        var ndcCounts: [Int64: Int] = [:]
        for batch in batchPage + completedBatches {
            ndcCounts[batch.batch_id] = batchStore.getTransactionCount(
                for: batch.batch_id
            )
        }
        batchNdcCounts = ndcCounts
    }

    /// Fetches and appends the next page of Today's Queue (pending dispense
    /// + inventory items). No-op if a fetch is already running or every
    /// source is exhausted.
    func loadMoreQueueIfNeeded() {
        guard hasMoreQueue, !isLoadingMoreQueue else { return }
        guard let userId = AppStorageManager.shared.userId,
              let user = userStore.fetchByUserId(userId) else { return }

        isLoadingMoreQueue = true
        defer { isLoadingMoreQueue = false }

        var newTxns: [PillCountTransactionEntity] = []

        if !queueFixedExhausted {
            let page = transactionStore.fetchPartialPage(for: user, isDispense: true, limit: dashboardPageSize, offset: queueFixedOffset)
            queueFixedOffset += page.count
            queueFixedExhausted = page.count < dashboardPageSize
            newTxns += page
        }

        if !queueRegularExhausted {
            let page = transactionStore.fetchPartialPage(for: user, isDispense: false, limit: dashboardPageSize, offset: queueRegularOffset)
            queueRegularOffset += page.count
            queueRegularExhausted = page.count < dashboardPageSize
            newTxns += page
        }

        let filteredNewTxns = newTxns.filter { $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue }
        dispensePartial += filteredNewTxns
        for txn in filteredNewTxns {
            pillCounts[txn.txn_id] = Int(
                detailStore.totalCountForStep(txnId: txn.txn_id, step: .targetVerification)
            )
        }

        if !queueBatchExhausted {
            let page = batchStore.fetchAllPartialPage(limit: dashboardPageSize, offset: queueBatchOffset)
            queueBatchOffset += page.count
            queueBatchExhausted = page.count < dashboardPageSize
            inventoryPartial += page
            for batch in page {
                batchNdcCounts[batch.batch_id] = batchStore.getTransactionCount(for: batch.batch_id)
            }
        }

        hasMoreQueue = !(queueFixedExhausted && queueRegularExhausted && queueBatchExhausted)
    }

    /// Fetches and appends the next page of today's completed activity
    /// (both transactions and batches). No-op if a fetch is already running
    /// or both sources are exhausted.
    func loadMoreRecentActivityIfNeeded() {
        guard hasMoreRecentActivity, !isLoadingMoreRecentActivity else { return }
        guard let userId = AppStorageManager.shared.userId,
              let user = userStore.fetchByUserId(userId) else { return }

        isLoadingMoreRecentActivity = true
        defer { isLoadingMoreRecentActivity = false }

        if !recentTxnExhausted {
            let page = transactionStore.fetchByTimeRangePage(
                for: user, startTime: todayStartTs, endTime: todayEndTs,
                limit: dashboardPageSize, offset: recentTxnOffset
            )
            recentTxnOffset += page.count
            recentTxnExhausted = page.count < dashboardPageSize
            let newlyCompleted = page.filter { $0.status == CountStatus.COMPLETED.rawValue }
            dispenseCompleted += newlyCompleted
            for txn in newlyCompleted {
                pillCounts[txn.txn_id] = Int(
                    detailStore.totalCountForStep(txnId: txn.txn_id, step: .targetVerification)
                )
            }
        }

        if !recentBatchExhausted {
            let page = batchStore.fetchByDateRangePage(
                startTs: todayStartTs, endTs: todayEndTs, limit: dashboardPageSize, offset: recentBatchOffset
            )
            recentBatchOffset += page.count
            recentBatchExhausted = page.count < dashboardPageSize
            let newlyCompleted = page.filter { $0.status == CountStatus.COMPLETED.rawValue }
            inventoryCompleted += newlyCompleted
            for batch in newlyCompleted {
                batchNdcCounts[batch.batch_id] = batchStore.getTransactionCount(for: batch.batch_id)
            }
        }

        hasMoreRecentActivity = !(recentTxnExhausted && recentBatchExhausted)
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
                + "isDispense=\(t.is_dispense) status=\(t.status ?? "-") "
                + "priority=\(t.txn_priority ?? "-") batch=\(t.batch_id) "
                + "ndcVerified=\(t.is_ndc_verfied)")
        }
        #endif
    }
}
