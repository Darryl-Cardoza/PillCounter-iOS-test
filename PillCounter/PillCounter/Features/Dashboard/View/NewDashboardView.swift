//
//  NewDashboardView.swift
//  PillCounter
//
//  New B2B dashboard UI — replaces DashboardView visually while keeping all functionality.
//

import SwiftUI

// MARK: - Unified queue item model

private enum DashboardQueueItem: Identifiable {
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

// MARK:- Stat card model

private enum StatCardFilter {
    case highPriority
    case hazardous
    case controlled
    case dispPending
    case cycleCount
    case pendingBatch
}

private struct DashboardStatCard: Identifiable {
    let id: String
    let iconName: String
    let iconColor: Color
    let count: Int
    let label: String
    let filter: StatCardFilter?
}
//13847
// MARK: - Main view

struct NewDashboardView: View {

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var historyViewModel: HistoryViewModel
    @EnvironmentObject private var toastManager: ToastManager
    @StateObject private var locationService = LocationService.shared

    // userId is stored in Keychain via AppStorageManager — @AppStorage reads UserDefaults
    // and would always return "". Read directly from the Keychain-backed store instead.
    private var userId: String { AppStorageManager.shared.userId ?? "" }
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true
    private var isHl7Enable: Bool { AppStorageManager.shared.isHl7Enabled }
    @AppStorage(AppStorageManager.AppStorageKeys.selectedTerminalName)
    var selectedTerminalName: String = ""

    @State private var showSelectBucketIdPopup: Bool = false
    @State private var hasCheckedNewUser: Bool = false
    @State private var selectedQueueTab: Int = 0  // 0 = Today's Queue, 1 = Recent Activity
    @State private var dispensePartial: [PillCountTransactionEntity] = []
    @State private var dispenseCompleted: [PillCountTransactionEntity] = []
    @State private var inventoryPartial: [BatchCountEntity] = []
    @State private var inventoryCompleted: [BatchCountEntity] = []
    @State private var pillCounts: [Int64: Int] = [:]
    @State private var batchNdcCounts: [Int64: Int] = [:]
    @State private var activeFilterCardId: String? = nil
    @State private var appearedQueueIds: Set<String> = []
    @State private var appearedRecentIds: Set<String> = []

    private let transactionDAO = TransactionStore.shared
    private let batchDAO = BatchStore.shared
    private let detailDAO = TransactionDetailStore.shared
    private let userStore = UserStore.shared

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var isLandscape: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation.isLandscape ?? false
    }

    private var mergedQueueItems: [DashboardQueueItem] {
        let dispenseItems = dispensePartial.map {
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

    private func filtered(_ items: [DashboardQueueItem]) -> [DashboardQueueItem]
    {
        guard let cardId = activeFilterCardId,
            let card = statCards.first(where: { $0.id == cardId }),
            let filter = card.filter
        else {
            return items
        }
        return applyFilter(filter, to: items)
    }

    private var filteredQueueItems: [DashboardQueueItem] {
        filtered(mergedQueueItems)
    }

    private var mergedRecentItems: [DashboardQueueItem] {
        let dispenseItems = dispenseCompleted.map {
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

    private var filteredRecentItems: [DashboardQueueItem] {
        filtered(mergedRecentItems)
    }

    // MARK: - Stat cards built from live data

    private var statCards: [DashboardStatCard] {
        [
            DashboardStatCard(
                id: "disp-high-priority",
                iconName: "icon_priority",
                iconColor: appColors.secondary,
                count: dispensePartial.filter {
                    let p =
                        $0.txn_priority?.trimmingCharacters(in: .whitespaces)
                        .lowercased() == "high"
                    return p
                }.count,
                label: L10n.Dashboard.StatCards.highPriority,
                filter: .highPriority
            ),
            DashboardStatCard(
                id: "disp-pending",
                iconName: "partial",
                iconColor: appColors.secondary,
                count: dispensePartial.count,
                label: L10n.Dashboard.StatCards.dispensePending,
                filter: .dispPending
            ),
            DashboardStatCard(
                id: "disp-cont-drugs",
                iconName: "icon_controlled",
                iconColor: appColors.secondary,
                count: dispensePartial.filter {
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
                iconColor: appColors.secondary,
                count: dispensePartial.filter { $0.drug?.is_hazardous == true }
                    .count,
                label: L10n.Dashboard.StatCards.hazardous,
                filter: .hazardous
            ),
            DashboardStatCard(
                id: "inv-cycle-count",
                iconName: "new_rx",
                iconColor: appColors.secondary,
                count: inventoryPartial.filter {
                    !($0.req_id_from_pms ?? "").isEmpty
                }.count,
                label: L10n.Dashboard.StatCards.cycleCount,
                filter: .cycleCount
            ),
            DashboardStatCard(
                id: "inv-pending-batch",
                iconName: "batch_icon",
                iconColor: appColors.secondary,
                count: inventoryPartial.filter {
                    ($0.req_id_from_pms ?? "").isEmpty
                }.count,
                label: L10n.Dashboard.StatCards.pendingBatch,
                filter: .pendingBatch
            ),
        ]
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            appColors.primaryBackground
                .ignoresSafeArea()

            if isIpad && isLandscape {
                landscapeBody
            } else if isPhone && isLandscape {
                phoneLandscapeBody
            } else {
                portraitBody
            }

        }
        .ignoresSafeArea(edges: .top)
        .onAppear(perform: onAppear)
        .onChange(of: pillScanViewModel.currentTransaction) { _, _ in
            loadQueueData()
        }
        .onReceive(TransactionStore.shared.transactionsDidChange) {
            loadQueueData()
        }
        .onChange(of: activeFilterCardId) { _, _ in
            appearedQueueIds.removeAll()
            appearedRecentIds.removeAll()
        }
        .customPopup(isPresented: $showSelectBucketIdPopup) {
            selectBucketPopUp
        }
    }

    // MARK: - Portrait body

    private var portraitBody: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.top, safeAreaTop)

            VStack(alignment: .leading, spacing: 0) {
                quickActionsSection
                    .padding(.bottom, 16)
                statCardsSection
                    .padding(.bottom, 28)

                queueTabHeaders
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            TabView(selection: $selectedQueueTab) {
                queueScrollContent(
                    items: filteredQueueItems,
                    idPrefix: "queue",
                    appearedIds: $appearedQueueIds
                ) {
                    AnyView(queueRowView(item: $0))
                }
                .tag(0)
                queueScrollContent(
                    items: filteredRecentItems,
                    idPrefix: "recent",
                    appearedIds: $appearedRecentIds
                ) {
                    AnyView(recentRowView(item: $0))
                }
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: selectedQueueTab)
        }
    }

    private func safeDimenstions(_ value: CGFloat, minimum: CGFloat = 1) -> CGFloat {
        value.isFinite ? max(minimum, value) : minimum
    }

    // MARK: - Phone landscape body

    private var phoneLandscapeBody: some View {
        GeometryReader { screen in
            let headerHeight = safeAreaTop + 52.0
            let panelHeight = screen.size.height - headerHeight
            let topRowHeight: CGFloat = 40
            let contentHeight = panelHeight - topRowHeight
            let leftW = screen.size.width * 0.28
            let midW = screen.size.width * 0.18

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, safeAreaTop)
                    .frame(height: headerHeight)

                // ── Shared header row ──
                HStack(spacing: 0) {
                    Text(L10n.Dashboard.quickActions)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(appColors.text)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.horizontal, 12)
                        .frame(
                            width: leftW,
                            height: topRowHeight,
                            alignment: .leading
                        )

                    Color.clear.frame(width: midW, height: topRowHeight)

                    queueTabHeaders
                        .frame(height: topRowHeight)
                        .frame(maxWidth: .infinity)
                }

                // ── Content row ──
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 10) {
                        phoneQuickActionCard(
                            iconName: "dispense_dashboard_icon",
                            title: L10n.Dashboard.FixedCount.title,
                            subtitle: L10n.Dashboard.FixedCount.subtitle,
                            action: navigateToDispense
                        )
                        .frame(maxHeight: .infinity)
                        phoneQuickActionCard(
                            iconName: "placeholder_history",
                            title: L10n.Dashboard.RegularCount.title,
                            subtitle: L10n.Dashboard.RegularCount.subtitle,
                            action: handleInventoryTapped
                        )
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(width: leftW)
                    .frame(height: contentHeight)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 15) {
                            ForEach(statCards) { card in
                                statCardView(card: card)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(width: midW)
                    .frame(height: contentHeight)

                    TabView(selection: $selectedQueueTab) {
                        queueScrollContent(
                            items: filteredQueueItems,
                            idPrefix: "queue",
                            appearedIds: $appearedQueueIds
                        ) {
                            AnyView(queueRowView(item: $0))
                        }
                        .tag(0)
                        queueScrollContent(
                            items: filteredRecentItems,
                            idPrefix: "recent",
                            appearedIds: $appearedRecentIds
                        ) {
                            AnyView(recentRowView(item: $0))
                        }
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(
                        .easeInOut(duration: 0.25),
                        value: selectedQueueTab
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: contentHeight)
                }
                .frame(height: contentHeight)
            }
        }
    }

    private func phoneQuickActionCard(
        iconName: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(appColors.primary.opacity(0.25), lineWidth: 5)
                        .blur(radius: 3)
                    Circle()
                        .stroke(appColors.primary, lineWidth: 2)
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(appColors.secondary)
                        .padding(10)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(appColors.secondary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(appColors.text)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.secondaryBackground)
            .cornerRadius(14)
            .shadow(color: appColors.text.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var phoneStatCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statCards) { card in
                    statCardView(card: card)
                        .frame(width: 88)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Landscape body (iPad only)

    private var landscapeBody: some View {
        GeometryReader { screen in
            let headerHeight = safeAreaTop + 52.0
            let panelHeight = screen.size.height - headerHeight
            let pad: CGFloat = 10
            let topRowHeight: CGFloat = 44
            let contentHeight = panelHeight - topRowHeight
            let leftWidth = (screen.size.width - 1) * 0.5
            let rightWidth = screen.size.width - leftWidth - 1
            // Left panel split: action cards | stat cards (no inner divider)
            let statsWidth = leftWidth * 0.25
            let actionWidth = leftWidth - statsWidth

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, safeAreaTop)
                    .frame(height: headerHeight)

                // ── Shared header row ──
                HStack(spacing: 0) {
                    Text(L10n.Dashboard.quickActions)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(appColors.text.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.horizontal, pad)
                        .frame(
                            width: leftWidth,
                            height: topRowHeight,
                            alignment: .leading
                        )

                    Color.clear.frame(width: 1, height: topRowHeight)

                    queueTabHeaders
                        .padding(.horizontal, pad)
                        .frame(width: rightWidth, height: topRowHeight)
                }

                // ── Content row ──
                HStack(alignment: .top, spacing: 0) {

                    // ── Left panel: [action cards | divider | stat cards] ──
                    HStack(alignment: .top, spacing: 0) {

                        // Action cards — Dispense on top, Inventory on bottom
                        VStack(spacing: pad) {
                            landscapeQuickActionCard(
                                iconName: "dispense_dashboard_icon",
                                title: L10n.Dashboard.FixedCount.title,
                                subtitle: L10n.Dashboard.FixedCount.subtitle,
                                action: navigateToDispense
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            landscapeQuickActionCard(
                                iconName: "placeholder_history",
                                title: L10n.Dashboard.RegularCount.title,
                                subtitle: L10n.Dashboard.RegularCount.subtitle,
                                action: handleInventoryTapped
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(pad)
                        .frame(width: actionWidth, height: contentHeight)

                        // Stat cards — all 6 in one column
                        VStack(spacing: 0) {
                            ForEach(statCards) { card in
                                statCardView(card: card)
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .padding(.vertical, 5)
                        .frame(width: statsWidth, height: contentHeight)
                    }
                    .frame(width: leftWidth, height: contentHeight)

                    // Main divider
                    //                    Rectangle()
                    //                        .fill(appColors.text.opacity(0.18))
                    //                        .frame(width: 1, height: contentHeight)

                    // ── Right panel: queue list ──
                    // padding(.top, -2) aligns first list item with first stat card (stat card starts at pad=10, list content starts at 12)
                    TabView(selection: $selectedQueueTab) {
                        queueScrollContent(
                            items: filteredQueueItems,
                            idPrefix: "queue",
                            appearedIds: $appearedQueueIds
                        ) {
                            AnyView(queueRowView(item: $0))
                        }
                        .tag(0)
                        queueScrollContent(
                            items: filteredRecentItems,
                            idPrefix: "recent",
                            appearedIds: $appearedRecentIds
                        ) {
                            AnyView(recentRowView(item: $0))
                        }
                        .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(
                        .easeInOut(duration: 0.25),
                        value: selectedQueueTab
                    )
                    .padding(.top, -2)
                    .frame(width: rightWidth, height: contentHeight + 2)
                }
                .frame(height: contentHeight)
            }
        }
    }

    private func landscapeQuickActionCard(
        iconName: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GeometryReader { geo in
                let circleSize = min(geo.size.width, geo.size.height) * 0.45
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .stroke(
                                appColors.primary.opacity(0.25),
                                lineWidth: 6
                            )
                            .blur(radius: 3)
                        Circle()
                            .stroke(appColors.primary, lineWidth: 2.5)
                        Image(iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(appColors.secondary)
                            .padding(circleSize * 0.3)
                    }
                    .frame(width: circleSize, height: circleSize)

                    VStack(spacing: 3) {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(appColors.secondary)
                        Text(subtitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(appColors.text)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.secondaryBackground)
            .cornerRadius(16)
            .shadow(color: appColors.text.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Safe area helper

    private var safeAreaTop: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top) ?? 0
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(alignment: .center) {
            // Left: pharmacy logo + name + terminal
            HStack(spacing: 10) {
                Image("app_icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: isIpad ? 36 : 30, height: isIpad ? 36 : 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        userViewModel.pharmacyName.isEmpty
                            ? L10n.Dashboard.pharmacyPlaceholder
                            : userViewModel.pharmacyName
                    )
                    .font(.system(size: isIpad ? 20 : 17, weight: .semibold))
                    .foregroundColor(appColors.text)
                    if !selectedTerminalName.isEmpty {
                        Text(
                            "\(L10n.Profile.terminal) \(selectedTerminalName) | \(userViewModel.fullName) "
                        )
                        .font(.system(size: isIpad ? 15 : 13))
                        .foregroundColor(appColors.text.opacity(0.6))
                    }
                }
            }

            Spacer()

            // Right: PMS status + Hamburger menu
            if isHl7Enable {
                PMSConnectionButtonView(
                    pmsConnectionState: userViewModel.pmsConnectionState
                )
            }

            Button {
                router.navigate(to: .authentication(.user(.hamburgerMenu)))
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: isIpad ? 28 : 24, weight: .semibold))
                    .foregroundColor(appColors.primary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(appColors.primaryBackground)
    }

    // MARK: - Quick actions (Dispense + Inventory)

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Dashboard.quickActions)
                .font(.system(size: isIpad ? 15 : 13, weight: .semibold))
                .foregroundColor(appColors.text.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1)

            if isIpad {
                HStack(spacing: 14) {
                    quickActionCard(
                        iconName: "dispense_dashboard_icon",
                        title: L10n.Dashboard.FixedCount.title,
                        subtitle: L10n.Dashboard.FixedCount.subtitle,
                        action: navigateToDispense
                    )
                    quickActionCard(
                        iconName: "placeholder_history",
                        title: L10n.Dashboard.RegularCount.title,
                        subtitle: L10n.Dashboard.RegularCount.subtitle,
                        action: handleInventoryTapped
                    )
                }
            } else {
                VStack(spacing: 10) {
                    quickActionCard(
                        iconName: "dispense_dashboard_icon",
                        title: L10n.Dashboard.FixedCount.title,
                        subtitle: L10n.Dashboard.FixedCount.subtitle,
                        action: navigateToDispense
                    )
                    quickActionCard(
                        iconName: "placeholder_history",
                        title: L10n.Dashboard.RegularCount.title,
                        subtitle: L10n.Dashboard.RegularCount.subtitle,
                        action: handleInventoryTapped
                    )
                }
            }
        }
    }

    private func quickActionCard(
        iconName: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(appColors.primary.opacity(0.25), lineWidth: 6)
                        .blur(radius: 3)
                    Circle()
                        .stroke(appColors.primary, lineWidth: 2.5)
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(appColors.secondary)
                        .padding(isIpad ? 18 : 14)
                }
                .frame(width: isIpad ? 90 : 60, height: isIpad ? 90 : 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(
                            .system(size: isIpad ? 24 : 20, weight: .semibold)
                        )
                        .foregroundColor(appColors.secondary)
                    Text(subtitle)
                        .font(.system(size: isIpad ? 16 : 14))
                        .fontWeight(.semibold)
                        .foregroundColor(appColors.text)
                }

                Spacer()
            }
            .padding(.horizontal, isIpad ? 24 : 16)
            .padding(.vertical, isIpad ? 48 : 22)
            .frame(maxWidth: .infinity)
            .background(appColors.secondaryBackground)
            .cornerRadius(16)
            .shadow(color: appColors.text.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Stat cards section

    @ViewBuilder
    private var statCardsSection: some View {
        if isIpad {
            // All 6 in one row on iPad (portrait and landscape)
            HStack(spacing: 12) {
                ForEach(statCards) { card in
                    statCardView(card: card)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            // Horizontally scrollable on phone
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(statCards) { card in
                        statCardView(card: card)
                            .frame(width: 100)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private func statCardView(card: DashboardStatCard) -> some View {
        let isActive = activeFilterCardId == card.id
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                activeFilterCardId = isActive ? nil : card.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    Image(card.iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(card.iconColor)
                }

                Text("\(card.count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(appColors.primary)
                    .padding(.top, 4)

                Text(card.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appColors.secondaryBackground)
            .cornerRadius(14)
            .shadow(
                color: isActive
                    ? appColors.primary.opacity(0.6)
                    : appColors.text.opacity(0.05),
                radius: isActive ? 8 : 4,
                x: 0,
                y: isActive ? 0 : 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isActive
                            ? appColors.primary.opacity(0.8) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Queue section

    private var queueTabHeaders: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                queueTabHeader(
                    title: L10n.Dashboard.HeaderTabs.todaysQueue,
                    index: 0
                )
                queueTabHeader(
                    title: L10n.Dashboard.HeaderTabs.recentActivity,
                    index: 1
                )
            }
            Divider()
        }
    }

    private func emptyQueueTitle() -> String {
        guard let cardId = activeFilterCardId,
            let card = statCards.first(where: { $0.id == cardId })
        else {
            return L10n.Dashboard.EmptyState.caughtUpTitle
        }
        return card.count == 0
            ? L10n.Dashboard.EmptyState.caughtUpTitle
            : L10n.Dashboard.EmptyState.noMatchingTitle
    }

    private func emptyQueueSubtitle() -> String {
        selectedQueueTab == 0
            ? L10n.Dashboard.EmptyState.noPendingSubtitle
            : L10n.Dashboard.EmptyState.noRecentSubtitle
    }

    private var emptyQueueState: some View {
        VStack(spacing: 16) {
            ZStack {
                Image("icon_checkmark_with_circle")
                    .renderingMode(.template)
                    .foregroundColor(appColors.secondary)
            }

            VStack(spacing: 6) {
                Text(emptyQueueTitle())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(appColors.secondary)
                    .multilineTextAlignment(.center)

                Text(emptyQueueSubtitle())
                    .font(.system(size: 14))
                    .foregroundColor(appColors.text)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private func queueScrollContent(
        items: [DashboardQueueItem],
        idPrefix: String,
        appearedIds: Binding<Set<String>>,
        rowBuilder: @escaping (DashboardQueueItem) -> AnyView
    ) -> some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if items.isEmpty {
                        emptyQueueState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geo.size.height)
                    } else {
                        // Namespace the row identity per tab so identical items
                        // (same txn/batch in both Today's Queue and Recent Activity)
                        // never share a view identity across the two TabView pages,
                        // which would make a row vanish from one tab.
                        ForEach(items) { item in
                            let didAppear = appearedIds.wrappedValue.contains(item.id)
                            rowBuilder(item)
                                .opacity(didAppear ? 1 : 0)
                                .offset(y: didAppear ? 0 : 20)
                                .id("\(idPrefix)-\(item.id)")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            // Drive the staggered appear at the list level so it always runs
            // (per-row .onAppear is unreliable inside a paged TabView — off-screen
            // pages don't fire it, leaving rows stuck at opacity 0).
            .onChange(of: items.map(\.id)) { _, newIds in
                animateAppearance(of: newIds, into: appearedIds)
            }
            .onAppear {
                animateAppearance(of: items.map(\.id), into: appearedIds)
            }
        }
    }

    /// Stagger-reveals any ids not yet marked as appeared, then records them.
    private func animateAppearance(
        of ids: [String],
        into appearedIds: Binding<Set<String>>
    ) {
        let fresh = ids.filter { !appearedIds.wrappedValue.contains($0) }
        guard !fresh.isEmpty else { return }
        for (offset, id) in fresh.enumerated() {
            withAnimation(
                .spring(response: 0.42, dampingFraction: 0.78)
                    .delay(Double(offset) * 0.06)
            ) {
                appearedIds.wrappedValue.insert(id)
            }
        }
    }

    private func queueTabHeader(title: String, index: Int) -> some View {
        let isSelected = selectedQueueTab == index
        return Button {
            selectedQueueTab = index
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(
                        .system(
                            size: isIpad ? 15 : 13,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .textCase(.uppercase)
                    .foregroundColor(appColors.text)
                    .tracking(0.8)

                Rectangle()
                    .fill(isSelected ? appColors.secondary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // Today's Queue — partial transactions, navigate to active scan/count screens
    @ViewBuilder
    private func queueRowView(item: DashboardQueueItem) -> some View {
        switch item {
        case .dispense(let txn, let pillCount):
            let data = txn.toRowData(pillCount: pillCount)
            DispenseItemRowView(data: data)
                .onTapGesture {
                    let countType =
                        txn.count_type?.uppercased()
                            == CountType.REGULAR.rawValue
                        ? CountType.REGULAR : CountType.FIXED
                    router.selectedPillScanningType = countType
                    userViewModel.currentTransactionTxnId = txn.txn_id
                    pillScanViewModel.selectedTransaction = txn
                    let scanType: ScanType = txn.is_ndc_verfied ? .resumeCount : .barcode
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(scanType))))
                        )
                    )
                }

        case .inventory(let batch, let ndcCount):
            let data = batch.toStockData(ndcCount: ndcCount)
            StockItemRowView(data: data)
                .onTapGesture {
                    guard let freshBatch = batchDAO.fetchById(batch.batch_id)
                    else { return }
                    stockCountViewModel.currentBatch = freshBatch
                    stockCountViewModel.reloadAllState()
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(.stockCount))))
                        )
                    )
                }
        }
    }

    // Recent Activity — completed transactions, navigate directly to history detail
    @ViewBuilder
    private func recentRowView(item: DashboardQueueItem) -> some View {
        switch item {
        case .dispense(let txn, let pillCount):
            let data = txn.toRowData(pillCount: pillCount)
            DispenseItemRowView(data: data)
                .onTapGesture {
                    historyViewModel.selectedTransactionId = txn.txn_id
                    router.navigate(
                        to: .authentication(
                            .user(.userSettings(.HistoryTransactionDetail))
                        )
                    )
                }

        case .inventory(let batch, let ndcCount):
            let data = batch.toStockData(ndcCount: ndcCount)
            StockItemRowView(data: data)
                .onTapGesture {
                    historyViewModel.prepareBatchDetails(for: batch.batch_id)
                    historyViewModel.selectedBatchId = batch.batch_id
                    router.navigate(
                        to: .authentication(
                            .user(.userSettings(.HistoryBatchDetail))
                        )
                    )
                }
        }
    }

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

    private func loadQueueData() {
        guard let user = userStore.fetchByUserId(userId) else { return }

        // Partial (Today's Queue)
        let fixed = transactionDAO.fetchPartial(for: user, countType: .FIXED)
        let regular = transactionDAO.fetchPartial(
            for: user,
            countType: .REGULAR
        )
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
            counts[txn.txn_id] = Int(detailDAO.totalCountForStep(txnId: txn.txn_id, step: .targetVerification))
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

    // MARK: - Navigation helpers

    private func navigateToDispense() {
        router.selectedPillScanningType = .FIXED
        router.navigate(
            to: .authentication(
                .login(.dashboard(.pillCount(.scan(.rx_label))))
            )
        )
    }

    // MARK: - Lifecycle

    private func onAppear() {
        if isNewUser && !hasCheckedNewUser {
            hasCheckedNewUser = true
            router.navigate(to: .authentication(.user(.userSettings(.profile))))
        } else {
            Task {
                // Only hit auth/me when the token was actually refreshed; otherwise
                // serve user data from the local cache to avoid an API call on every visit.
                let didRefresh = await userViewModel.checkAndRefreshTokenIfNeeded()
                await userViewModel.getUser(forceRemote: didRefresh)
                stockCountViewModel.getCountData()
                // Reload after async user data is ready to ensure queue is populated
                await MainActor.run { loadQueueData() }
            }
        }

        locationService.requestPermission()
        locationService.startUpdating()
        loadQueueData()

        DrugCatalogStore.shared.fetchAll()
    }

    //Popoup

    private var selectBucketPopUp: some View {
        VStack(spacing: 35) {
            VStack(alignment: .leading) {
                Text(L10n.Dashboard.Popup.selectBucket)
                    .font(.system(size: 18))
                    .fontWeight(.semibold)
                    .foregroundStyle(appColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 28) {
                ForEach(pillScanViewModel.bucketOptions, id: \.self) { bucket in
                    PillCountingRadioButton(
                        option: bucket,
                        selectedOption: $pillScanViewModel.selectedBucket,
                        label: bucket,
                        selectedColor: appColors.secondary,
                        unselectedColor: .gray,
                        size: 20,
                        lineWidth: 2,
                        textColor: appColors.text
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EqualWidthHStackButtons(spacing: 20) {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.cancel,
                    textColor: appColors.text,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 16, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: { showSelectBucketIdPopup = false }
                )
                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 16, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        createBatchAndNavigate(
                            bucketId: pillScanViewModel.selectedBucket
                        )
                        showSelectBucketIdPopup = false
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
    }

    private func handleInventoryTapped() {
        let buckets = userViewModel.bucket
        //        let buckets = ["NORMAL"]
        let meaningful = buckets.filter { $0 != "NORMAL" && !$0.isEmpty }
        if meaningful.isEmpty {
            // No real bucket choices — skip popup, use NORMAL directly
            createBatchAndNavigate(bucketId: "NORMAL")
        } else {
            pillScanViewModel.bucketOptions = buckets
            pillScanViewModel.selectedBucket = buckets.first ?? ""
            showSelectBucketIdPopup = true
        }
    }

    private func createBatchAndNavigate(bucketId: String) {
        stockCountViewModel.currentBatch = nil
        stockCountViewModel.groupedTransactions = []
        stockCountViewModel.batchNdcSet = []
        stockCountViewModel.pendingBucketId = bucketId
        router.selectedPillScanningType = .REGULAR
        router.navigate(
            to: .authentication(
                .login(.dashboard(.pillCount(.scan(.stockCount))))
            )
        )
    }
}
