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

// MARK: - Stat card model

private enum StatCardFilter {
    case highPriority
    case hazardous
    case controlled
}

private struct DashboardStatCard: Identifiable {
    let id: String
    let iconName: String
    let iconColor: Color
    let count: Int
    let label: String
    let filter: StatCardFilter?
}

// MARK: - Main view

struct NewDashboardView: View {

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @StateObject private var locationService = LocationService.shared

    @AppStorage(AppStorageManager.AppStorageKeys.userId) var userId: String = ""
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true
    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable) var isHl7Enable:
        Bool = false
    @AppStorage(AppStorageManager.AppStorageKeys.selectedTerminalName)
    var selectedTerminalName: String = ""

    @State private var showSelectBucketIdPopup: Bool = false
    @State private var hasCheckedNewUser: Bool = false
    @State private var selectedQueueTab: Int = 0  // 0 = Today's Queue, 1 = Recent Activity
    @State private var dispensePartial: [PillCountTransactionEntity] = []
    @State private var inventoryPartial: [BatchCountEntity] = []
    @State private var pillCounts: [Int64: Int] = [:]
    @State private var batchNdcCounts: [Int64: Int] = [:]
    @State private var activeFilterCardId: String? = nil
    @State private var selectedIds: Set<Int64> = []

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

    private var filteredQueueItems: [DashboardQueueItem] {
        guard let cardId = activeFilterCardId,
              let card = statCards.first(where: { $0.id == cardId }),
              let filter = card.filter else {
            return mergedQueueItems
        }
        return mergedQueueItems.filter { item in
            switch (item, filter) {
            case (.dispense(let txn, _), .highPriority):
                let p = txn.txn_priority?.trimmingCharacters(in: .whitespaces) ?? ""
                return !p.isEmpty
            case (.dispense(let txn, _), .hazardous):
                return txn.drug?.is_hazardous == true
            case (.dispense(let txn, _), .controlled):
                let t = txn.drug?.drug_type?.trimmingCharacters(in: .whitespaces) ?? ""
                return !t.isEmpty
            default:
                return false
            }
        }
    }

    // MARK: - Stat cards built from live data

    private var statCards: [DashboardStatCard] {
        [
            DashboardStatCard(
                id: "disp-high-priority",
                iconName: "icon_priority",
                iconColor: appColors.secondary,
                count: dispensePartial.filter {
                    let p = $0.txn_priority?.trimmingCharacters(in: .whitespaces) ?? ""
                    return !p.isEmpty
                }.count,
                label: "High Priority",
                filter: .highPriority
            ),
            DashboardStatCard(
                id: "disp-pending",
                iconName: "partial",
                iconColor: appColors.secondary,
                count: userViewModel.fixedCountTransactionPartialCount,
                label: "Disp. Pending",
                filter: nil
            ),
            DashboardStatCard(
                id: "disp-cont-drugs",
                iconName: "icon_controlled",
                iconColor: appColors.secondary,
                count: dispensePartial.filter {
                    let t = $0.drug?.drug_type?.trimmingCharacters(in: .whitespaces) ?? ""
                    return !t.isEmpty
                }.count,
                label: "Cont. Drugs",
                filter: .controlled
            ),
            DashboardStatCard(
                id: "disp-hazardous",
                iconName: "icon_hazardous",
                iconColor: appColors.secondary,
                count: dispensePartial.filter { $0.drug?.is_hazardous == true }.count,
                label: "Hazardous",
                filter: .hazardous
            ),
            DashboardStatCard(
                id: "inv-cycle-count",
                iconName: "new_rx",
                iconColor: appColors.secondary,
                count: stockCountViewModel.totalBatchCount,
                label: "Cycle Count",
                filter: nil
            ),
            DashboardStatCard(
                id: "inv-pending-batch",
                iconName: "batch_icon",
                iconColor: appColors.secondary,
                count: stockCountViewModel.totalCompletedBatchCount,
                label: "Pending Batch",
                filter: nil
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

            // Toast
            if pillScanViewModel.showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image("app_icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text(pillScanViewModel.toastMessage)
                            .font(.subheadline)
                            .foregroundColor(appColors.secondaryBackground)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(appColors.text.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: pillScanViewModel.showToast)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear(perform: onAppear)
        .onChange(of: pillScanViewModel.currentTransaction) { _, _ in
            loadQueueData()
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
                Rectangle()
                    .fill(appColors.text.opacity(0.18)) 
                    .frame(height: 1)
                    .padding(.bottom, 20)
                queueTabHeaders
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            TabView(selection: $selectedQueueTab) {
                queueScrollContent(items: filteredQueueItems)
                    .tag(0)
                queueScrollContent(items: [])
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: selectedQueueTab)
        }
    }

    // MARK: - Phone landscape body

    private var phoneLandscapeBody: some View {
        GeometryReader { screen in
            let headerHeight = safeAreaTop + 52.0
            let panelHeight = screen.size.height - headerHeight

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, safeAreaTop)
                    .frame(height: headerHeight)

                HStack(alignment: .top, spacing: 0) {
                    // Left panel: quick action cards stacked vertically
                    VStack(spacing: 10) {
                        phoneQuickActionCard(
                            iconName: "dispense_dashboard_icon",
                            title: "Dispense",
                            subtitle: "Tap to scan Rx Labels",
                            action: navigateToDispense
                        )
                        .frame(maxHeight: .infinity)
                        phoneQuickActionCard(
                            iconName: "placeholder_history",
                            title: "Inventory",
                            subtitle: "Start inventory count",
                            action: handleInventoryTapped
                        )
                        .frame(maxHeight: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(width: screen.size.width * 0.28)
                    .frame(height: panelHeight)

                    // Middle panel: stat cards vertically scrollable
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(statCards) { card in
                                statCardView(card: card)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                    }
                    .frame(width: screen.size.width * 0.18)
                    .frame(height: panelHeight)

                    // Right panel: queue
                    VStack(alignment: .leading, spacing: 0) {
                        queueTabHeaders
                            .padding(.top, 10)

                        TabView(selection: $selectedQueueTab) {
                            queueScrollContent(items: filteredQueueItems)
                                .tag(0)
                            queueScrollContent(items: [])
                                .tag(1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .animation(
                            .easeInOut(duration: 0.25),
                            value: selectedQueueTab
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)
                }
                .frame(height: panelHeight)
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
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.6))
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
            let leftWidth = (screen.size.width - 1) * 0.5
            let rightWidth = screen.size.width - leftWidth - 1
            // equal pad on all 4 sides + gap between two rows
            let rowHeight = (panelHeight - pad * 3) / 2
            let actionWidth = leftWidth * 0.68
            let statsWidth = leftWidth - actionWidth - pad * 3

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, safeAreaTop)
                    .frame(height: headerHeight)

                HStack(alignment: .top, spacing: 0) {

                    // ── Left 50%: [Dispense | 3 stats] over [Inventory | 3 stats] ──
                    VStack(spacing: 0) {
                        let cardHeight = (rowHeight - pad * 2) / 3

                        VStack(spacing: pad) {
                            HStack(alignment: .top, spacing: pad) {
                                landscapeQuickActionCard(
                                    iconName: "dispense_dashboard_icon",
                                    title: "Dispense",
                                    subtitle: "Scan Rx Labels",
                                    action: navigateToDispense
                                )
                                .frame(width: actionWidth)
                                .frame(height: rowHeight)

                                VStack(spacing: pad) {
                                    ForEach(Array(statCards.prefix(3))) { card in
                                        statCardView(card: card)
                                            .frame(width: statsWidth)
                                            .frame(height: cardHeight)
                                    }
                                }
                                .frame(width: statsWidth)
                                .frame(height: rowHeight)
                            }

                            HStack(alignment: .top, spacing: pad) {
                                landscapeQuickActionCard(
                                    iconName: "placeholder_history",
                                    title: "Inventory",
                                    subtitle: "Start inventory count",
                                    action: handleInventoryTapped
                                )
                                .frame(width: actionWidth)
                                .frame(height: rowHeight)

                                VStack(spacing: pad) {
                                    ForEach(Array(statCards.dropFirst(3))) { card in
                                        statCardView(card: card)
                                            .frame(width: statsWidth)
                                            .frame(height: cardHeight)
                                    }
                                }
                                .frame(width: statsWidth)
                                .frame(height: rowHeight)
                            }
                        }
                        .padding(pad)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: leftWidth)
                    .frame(height: panelHeight)

                    // Divider
                    Rectangle()
                        .fill(appColors.text.opacity(0.18))
                        .frame(width: 1)
                        .frame(height: panelHeight)

                    // ── Right 45%: queue tabs + list ──
                    VStack(alignment: .leading, spacing: 0) {
                        queueTabHeaders
                            .padding(.top, pad)
                            .padding(.horizontal, pad)

                        TabView(selection: $selectedQueueTab) {
                            queueScrollContent(items: filteredQueueItems)
                                .tag(0)
                            queueScrollContent(items: [])
                                .tag(1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .animation(.easeInOut(duration: 0.25), value: selectedQueueTab)
                    }
                    .frame(width: rightWidth)
                    .frame(height: panelHeight)
                }
                .frame(height: panelHeight)
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
                            .stroke(appColors.primary.opacity(0.25), lineWidth: 6)
                            .blur(radius: 3)
                        Circle()
                            .stroke(appColors.primary, lineWidth: 2.5)
                        Image(iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(appColors.secondary)
                            .padding(circleSize * 0.22)
                    }
                    .frame(width: circleSize, height: circleSize)

                    VStack(spacing: 3) {
                        Text(title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(appColors.secondary)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(appColors.text.opacity(0.6))
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
                            ? "Pharmacy" : userViewModel.pharmacyName
                    )
                    .font(.system(size: isIpad ? 20 : 17, weight: .semibold))
                    .foregroundColor(appColors.text)
                    if !selectedTerminalName.isEmpty {
                        Text("Terminal \(selectedTerminalName)")
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
            Text("QUICK ACTIONS")
                .font(.system(size: isIpad ? 15 : 13, weight: .semibold))
                .foregroundColor(appColors.text.opacity(0.5))
                .tracking(1)

            if isIpad {
                HStack(spacing: 14) {
                    quickActionCard(
                        iconName: "dispense_dashboard_icon",
                        title: "Dispense",
                        subtitle: "Tap to scan Rx Labels",
                        action: navigateToDispense
                    )
                    quickActionCard(
                        iconName: "placeholder_history",
                        title: "Inventory",
                        subtitle: "Start inventory count",
                        action: handleInventoryTapped
                    )
                }
            } else {
                VStack(spacing: 10) {
                    quickActionCard(
                        iconName: "dispense_dashboard_icon",
                        title: "Dispense",
                        subtitle: "Tap to scan Rx Labels",
                        action: navigateToDispense
                    )
                    quickActionCard(
                        iconName: "placeholder_history",
                        title: "Inventory",
                        subtitle: "Start inventory count",
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
                        .foregroundColor(appColors.text.opacity(0.6))
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
                        .frame(width: 18, height: 18)
                        .foregroundColor(card.iconColor)
                }

                Text("\(card.count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(appColors.primary)
                    .padding(.top, 4)

                Text(card.label)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appColors.secondaryBackground)
            .cornerRadius(14)
            .shadow(
                color: isActive ? appColors.secondary.opacity(0.6) : appColors.text.opacity(0.05),
                radius: isActive ? 8 : 4,
                x: 0,
                y: isActive ? 0 : 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? appColors.secondary.opacity(0.8) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Queue section

    private var queueTabHeaders: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                queueTabHeader(title: "TODAY'S QUEUE", index: 0)
                queueTabHeader(title: "RECENT ACTIVITY", index: 1)
            }
            Divider()
        }
    }

    private func queueScrollContent(items: [DashboardQueueItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if items.isEmpty {
                    Text(activeFilterCardId != nil ? "No matching items" : "No pending items")
                        .font(.system(size: 15))
                        .foregroundColor(appColors.text.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                        .transition(.opacity)
                } else {
                    ForEach(items) { item in
                        queueRowView(item: item)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                )
                            )
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: items.map(\.id))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private func queueTabHeader(title: String, index: Int) -> some View {
        let isSelected = selectedQueueTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedQueueTab = index
            }
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(
                        .system(
                            size: isIpad ? 14 : 13,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .foregroundColor(
                        isSelected
                            ? appColors.text : appColors.text.opacity(0.45)
                    )
                    .tracking(0.8)

                Rectangle()
                    .fill(isSelected ? appColors.secondary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func queueRowView(item: DashboardQueueItem) -> some View {
        switch item {
        case .dispense(let txn, let pillCount):
            let data = txn.toRowData(pillCount: pillCount)
            let isSelected = selectedIds.contains(txn.txn_id)
            DispenseItemRowView(data: data, appColors: appColors)
                .selectableEffect(isSelected: isSelected, highlightColor: appColors.primary)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedIds.insert(txn.txn_id)
                    }
                    let countType =
                        txn.count_type?.uppercased() == CountType.REGULAR.rawValue
                        ? CountType.REGULAR : CountType.FIXED
                    router.selectedPillScanningType = countType
                    userViewModel.currentTransactionTxnId = txn.txn_id
                    pillScanViewModel.selectedTransaction = txn
                    router.navigate(
                        to: .authentication(
                            .login(.dashboard(.pillCount(.scan(.barcode))))
                        )
                    )
                }

        case .inventory(let batch, let ndcCount):
            let data = batch.toStockData(ndcCount: ndcCount)
            let isSelected = selectedIds.contains(batch.batch_id)
            StockItemRowView(data: data, appColors: appColors)
                .selectableEffect(isSelected: isSelected, highlightColor: appColors.primary)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedIds.insert(batch.batch_id)
                    }
                    router.navigate(
                        to: .authentication(
                            .login(
                                .dashboard(
                                    .pillCount(
                                        .stockCount(
                                            .stockCountPartialBatchListScreen
                                        )
                                    )
                                )
                            )
                        )
                    )
                }
        }
    }

    private func printQueue(_ transactions: [PillCountTransactionEntity]) {
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
            if i < transactions.count - 1 { print("    \(String(repeating: "·", count: 40))") }
        }
        print(sep)
    }

    private func loadQueueData() {
        guard let user = userStore.fetchByUserId(userId) else { return }

        let fixed = transactionDAO.fetchPartial(for: user, countType: .FIXED)
        let regular = transactionDAO.fetchPartial(
            for: user,
            countType: .REGULAR
        )
        dispensePartial = (fixed + regular)
        printQueue(dispensePartial)

        var counts: [Int64: Int] = [:]
        for txn in dispensePartial {
            counts[txn.txn_id] = detailDAO.totalCount(txnId: txn.txn_id)
        }
        pillCounts = counts

        let batches = batchDAO.fetchAllPartial()
        inventoryPartial = batches

        var ndcCounts: [Int64: Int] = [:]
        for batch in batches {
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
        Task(priority: .background) {
            await userViewModel.checkAndRefreshTokenIfNeeded()
        }

        if isNewUser && !hasCheckedNewUser {
            hasCheckedNewUser = true
            router.navigate(to: .authentication(.user(.userSettings(.profile))))
        } else {
            Task {
                await userViewModel.getUser()
                stockCountViewModel.getCountData()
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
                        createBatchAndNavigate(bucketId: pillScanViewModel.selectedBucket)
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
