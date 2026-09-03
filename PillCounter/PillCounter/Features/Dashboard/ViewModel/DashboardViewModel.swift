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

/// Wraps a plain DTO (`TransactionRowData`/`StockData`), never a live
/// `NSManagedObject` — the entire Today's Queue / Recent Activity dataset is
/// fetched, decrypted, and mapped to these DTOs once, off-main, in
/// `loadQueueData` (see its doc comment). Navigation reads only the id
/// fields (`txnId`/`batchId`) and re-fetches on the destination screen, so
/// nothing here needs a live managed object.
enum DashboardQueueItem: Identifiable {
    case dispense(TransactionRowData)
    case inventory(StockData)

    var id: String {
        switch self {
        case .dispense(let row): return "d-\(row.txnId)"
        case .inventory(let row): return "i-\(row.batchId)"
        }
    }

    var sortDate: Int64 {
        switch self {
        case .dispense(let row): return row.createdAt
        case .inventory(let row): return row.createdAt
        }
    }

    var isHighPriority: Bool {
        switch self {
        case .dispense(let row):
            return row.txnPriority?
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

/// Stat-card counts, fetched once per `loadQueueData` / data-change via true
/// COUNT queries (no row materialization) — kept separate from the paginated
/// `dispensePartial`/`inventoryPartial` display arrays so the numbers don't
/// change as more pages load, and so a large pending queue doesn't have to
/// be fetched/decrypted in full just to count it.
struct DashboardStatCounts {
    var pendingDispense = 0
    var highPriority = 0
    var controlled = 0
    var hazardous = 0
    var cycleCount = 0
    var pendingBatch = 0
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

    // Loaded data — the full Today's Queue / Recent Activity dataset,
    // fetched entirely by `loadQueueData` (no further paging).
    @Published private(set) var dispensePartial: [TransactionRowData] = []
    @Published private(set) var dispenseCompleted: [TransactionRowData] = []
    @Published private(set) var inventoryPartial: [StockData] = []
    @Published private(set) var inventoryCompleted: [StockData] = []

    private var statCounts = DashboardStatCounts()

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
    private func isRegular(_ row: TransactionRowData) -> Bool {
        !row.isDispense
    }

    // MARK: - Merged queues

    private var mergedQueueItems: [DashboardQueueItem] {
        let dispenseItems = dispensePartial
            .filter { !isRegular($0) }
            .map { DashboardQueueItem.dispense($0) }
        let inventoryItems = inventoryPartial.map { DashboardQueueItem.inventory($0) }
        return (dispenseItems + inventoryItems).sorted {
            if $0.isHighPriority != $1.isHighPriority { return $0.isHighPriority }
            return $0.sortDate < $1.sortDate
        }
    }

    private var mergedRecentItems: [DashboardQueueItem] {
        let dispenseItems = dispenseCompleted
            .filter { !isRegular($0) }
            .map { DashboardQueueItem.dispense($0) }
        let inventoryItems = inventoryCompleted.map { DashboardQueueItem.inventory($0) }
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
            case (.dispense(let row), .highPriority):
                // Matches TransactionStore.countPendingDispense's DB predicate
                // (`txn_priority ==[c] "high"`) exactly — case-insensitive,
                // no trimming, so card counts and list rows agree.
                return row.txnPriority?.lowercased() == "high"
            case (.dispense(let row), .hazardous):
                return row.isHazardous
            case (.dispense(let row), .controlled):
                // Matches TransactionStore.countPendingDispense's DB predicate
                // (`drug.drug_type != nil AND drug.drug_type != ""`) exactly —
                // no trimming, so card counts and list rows agree even on a
                // whitespace-only drug_type.
                return !row.drugType.isEmpty
            case (.dispense, .dispPending):
                return true
            case (.inventory(let row), .cycleCount):
                return !((row.reqIdFromPms ?? "").isEmpty)
            case (.inventory(let row), .pendingBatch):
                return (row.reqIdFromPms ?? "").isEmpty
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
        [
            DashboardStatCard(
                id: "disp-high-priority",
                iconName: "icon_priority",
                iconColor: iconColor,
                count: statCounts.highPriority,
                label: L10n.Dashboard.StatCards.highPriority,
                filter: .highPriority
            ),
            DashboardStatCard(
                id: "disp-pending",
                iconName: "partial",
                iconColor: iconColor,
                count: statCounts.pendingDispense,
                label: L10n.Dashboard.StatCards.dispensePending,
                filter: .dispPending
            ),
            DashboardStatCard(
                id: "disp-cont-drugs",
                iconName: "icon_controlled",
                iconColor: iconColor,
                count: statCounts.controlled,
                label: L10n.Dashboard.StatCards.controlledDrug,
                filter: .controlled
            ),
            DashboardStatCard(
                id: "disp-hazardous",
                iconName: "icon_hazardous",
                iconColor: iconColor,
                count: statCounts.hazardous,
                label: L10n.Dashboard.StatCards.hazardous,
                filter: .hazardous
            ),
            DashboardStatCard(
                id: "inv-cycle-count",
                iconName: "new_rx",
                iconColor: iconColor,
                count: statCounts.cycleCount,
                label: L10n.Dashboard.StatCards.cycleCount,
                filter: .cycleCount
            ),
            DashboardStatCard(
                id: "inv-pending-batch",
                iconName: "batch_icon",
                iconColor: iconColor,
                count: statCounts.pendingBatch,
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

    /// True only while the FIRST `loadQueueData` call of this view model's
    /// lifetime is in flight — a large dataset makes that fetch (stat
    /// counts, the full Today's Queue/Recent Activity dataset, batched
    /// pill/ndc counts) take long enough to read as a frozen screen rather
    /// than a loading one. Later calls (the transactionsDidChange refresh,
    /// or `startDashboardLoad`'s second call after user data settles) update
    /// the lists silently — the screen already has data on screen by then,
    /// so re-showing the overlay would just be a needless flash.
    @Published var isInitialLoading = true
    private var hasLoadedOnce = false

    /// Loads the ENTIRE Today's Queue (all pending dispense + inventory
    /// items) and ENTIRE Recent Activity (today's completed items) in one
    /// pass — no further paging. Previously this loaded in `dashboardPageSize`
    /// chunks as the user scrolled; because the merged list is globally
    /// re-sorted (`mergedQueueItems`/`mergedRecentItems`) on every access,
    /// each new page landing could shift already-visible rows to a new
    /// position (a newly-fetched high-priority or earlier-dated item sorting
    /// ahead of what was already on screen), which — combined with the
    /// order-sensitive `.animation` on the list — made rows visibly reshuffle
    /// mid-scroll, reading as items randomly appearing/disappearing. Fetching
    /// everything once, sorted once, removes that entirely.
    ///
    /// The fetch, every relationship read (`.drug`), and every row's decrypt
    /// happen inside one background context's `performAndWait` — mirroring
    /// the History detail screen's fix — so a large dataset (thousands of
    /// rows) doesn't block the main thread. Only the mapped `TransactionRowData`/
    /// `StockData` arrays (already carrying their own `pillCount`/`ndcCount`)
    /// cross back to the main actor; no `NSManagedObject` from that context
    /// is retained.
    func loadQueueData(userId: String) async {
        let isFirstLoad = !hasLoadedOnce
        if isFirstLoad { isInitialLoading = true }
        defer {
            hasLoadedOnce = true
            if isFirstLoad { isInitialLoading = false }
        }

        guard let user = userStore.fetchByUserId(userId) else { return }
        let userObjectId = user.objectID

        let startOfToday = Calendar.current.startOfDay(for: Date())
        let todayStartTs = Int64(startOfToday.timeIntervalSince1970 * 1000)
        let todayEndTs = Int64(Date().timeIntervalSince1970 * 1000)

        // Stat-card counts: true COUNT queries, independent of the display
        // lists below — cheap, no row materialization, so these stay on the
        // main-thread stores as before.
        statCounts = DashboardStatCounts(
            pendingDispense: transactionStore.countPendingDispense(for: user, facet: .all),
            highPriority: transactionStore.countPendingDispense(for: user, facet: .highPriority),
            controlled: transactionStore.countPendingDispense(for: user, facet: .controlled),
            hazardous: transactionStore.countPendingDispense(for: user, facet: .hazardous),
            cycleCount: batchStore.countPendingInventory(facet: .cycleCount),
            pendingBatch: batchStore.countPendingInventory(facet: .pendingBatch)
        )

        // Captured as locals before entering Task.detached — `self` is
        // @MainActor-isolated, so its stored `transactionStore`/`batchStore`/
        // `detailStore` (non-Sendable protocol types) cannot be captured
        // directly into a detached closure. The stores themselves are safe to
        // call from any thread (every call is confined via their own
        // `sync`/explicit-context `performAndWait`), so capturing the
        // references (not `self`) is sufficient.
        let transactionStore = self.transactionStore
        let batchStore = self.batchStore
        let detailStore = self.detailStore

        let result = await Task.detached(priority: .userInitiated) { () -> QueueLoadResult in
            let bgContext = CoreDataManager.shared.backgroundContext
            return bgContext.performAndWait { () -> QueueLoadResult in
                guard let bgUser = try? bgContext.existingObject(with: userObjectId) as? UserEntity else {
                    return QueueLoadResult.empty
                }

                let fixedTxns = transactionStore.fetchPartial(for: bgUser, isDispense: true, in: bgContext)
                let regularTxns = transactionStore.fetchPartial(for: bgUser, isDispense: false, in: bgContext)
                let pendingDispense = (fixedTxns + regularTxns).filter {
                    $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue
                }
                let pendingInventory = batchStore.fetchAllPartial(in: bgContext)

                let completedTxns = transactionStore.fetchByTimeRange(
                    for: bgUser, startTime: todayStartTs, endTime: todayEndTs, in: bgContext
                ).filter { $0.status == CountStatus.COMPLETED.rawValue }
                let completedBatches = batchStore.fetchByDateRange(
                    startTs: todayStartTs, endTs: todayEndTs, in: bgContext
                ).filter { $0.status == CountStatus.COMPLETED.rawValue }

                let allTxnIds = (pendingDispense + completedTxns).map { $0.txn_id }
                let stepTotals = detailStore.totalCountsForSteps(
                    txnIds: allTxnIds, step: .targetVerification, in: bgContext
                )
                let pillCounts = stepTotals.mapValues { Int($0) }

                let allBatchIds = (pendingInventory + completedBatches).map { $0.batch_id }
                let batchNdcCounts = batchStore.transactionCounts(for: allBatchIds, in: bgContext)

                return QueueLoadResult(
                    dispensePartial: pendingDispense.map { $0.toRowData(pillCount: pillCounts[$0.txn_id] ?? 0) },
                    dispenseCompleted: completedTxns.map { $0.toRowData(pillCount: pillCounts[$0.txn_id] ?? 0) },
                    inventoryPartial: pendingInventory.map { $0.toStockData(ndcCount: batchNdcCounts[$0.batch_id] ?? 0) },
                    inventoryCompleted: completedBatches.map { $0.toStockData(ndcCount: batchNdcCounts[$0.batch_id] ?? 0) }
                )
            }
        }.value

        dispensePartial = result.dispensePartial
        dispenseCompleted = result.dispenseCompleted
        inventoryPartial = result.inventoryPartial
        inventoryCompleted = result.inventoryCompleted
    }
}

/// Plain result of one `loadQueueData` background fetch — crosses the
/// context boundary as DTOs only (see that method's doc comment).
private struct QueueLoadResult {
    let dispensePartial: [TransactionRowData]
    let dispenseCompleted: [TransactionRowData]
    let inventoryPartial: [StockData]
    let inventoryCompleted: [StockData]

    static let empty = QueueLoadResult(
        dispensePartial: [], dispenseCompleted: [], inventoryPartial: [], inventoryCompleted: []
    )
}
