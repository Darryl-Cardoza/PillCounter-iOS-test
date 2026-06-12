//
//  NewDashboardView.swift
//  PillCounter
//
//  New B2B dashboard UI — replaces DashboardView visually while keeping all functionality.
//  Data, merging, filtering and stat-card derivation live in NewDashboardViewModel;
//  this view owns layout and navigation only.
//

import SwiftUI

// MARK: - Main view

struct NewDashboardView: View {

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var historyViewModel: HistoryViewModel
    @EnvironmentObject private var toastManager: ToastManager

    @StateObject private var viewModel = NewDashboardViewModel()
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

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var isLandscape: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation.isLandscape ?? false
    }

    // Theme-aware stat cards (color injected so the view model stays theme-free).
    private var statCards: [DashboardStatCard] {
        viewModel.statCards(iconColor: appColors.secondary)
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
            viewModel.loadQueueData(userId: userId)
        }
        .onReceive(TransactionStore.shared.transactionsDidChange) {
            viewModel.loadQueueData(userId: userId)
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

            queuePager
        }
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
                        PhoneQuickActionCard(
                            iconName: "dispense_dashboard_icon",
                            title: L10n.Dashboard.FixedCount.title,
                            subtitle: L10n.Dashboard.FixedCount.subtitle,
                            action: navigateToDispense
                        )
                        .frame(maxHeight: .infinity)
                        PhoneQuickActionCard(
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

                    queuePager
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight)
                }
                .frame(height: contentHeight)
            }
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
                        .foregroundColor(appColors.text)
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
                            LandscapeQuickActionCard(
                                iconName: "icon_dashboard_dispense",
                                title: L10n.Dashboard.FixedCount.title,
                                subtitle: L10n.Dashboard.FixedCount.subtitle,
                                action: navigateToDispense
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            LandscapeQuickActionCard(
                                iconName: "icon_dashboard_stock",
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

                    queuePager
                        .padding(.top, -2)
                        .frame(width: rightWidth, height: contentHeight + 2)
                }
                .frame(height: contentHeight)
            }
        }
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
                Image("icon_app")
                    .resizable()
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
                            "\(selectedTerminalName) | \(userViewModel.fullName) "
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
                .foregroundColor(appColors.text)
                .textCase(.uppercase)
                .tracking(1)

            if isIpad {
                HStack(spacing: 14) {
                    quickActionCard(
                        iconName: "icon_dashboard_dispense",
                        title: L10n.Dashboard.FixedCount.title,
                        subtitle: L10n.Dashboard.FixedCount.subtitle,
                        action: navigateToDispense
                    )
                    quickActionCard(
                        iconName: "icon_dashboard_stock",
                        title: L10n.Dashboard.RegularCount.title,
                        subtitle: L10n.Dashboard.RegularCount.subtitle,
                        action: handleInventoryTapped
                    )
                }
            } else {
                VStack(spacing: 10) {
                    quickActionCard(
                        iconName: "icon_dashboard_dispense",
                        title: L10n.Dashboard.FixedCount.title,
                        subtitle: L10n.Dashboard.FixedCount.subtitle,
                        action: navigateToDispense
                    )
                    quickActionCard(
                        iconName: "icon_dashboard_stock",
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
        DashboardQuickActionCard(
            iconName: iconName,
            title: title,
            subtitle: subtitle,
            isIpad: isIpad,
            action: action
        )
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
        DashboardStatCardView(
            card: card,
            isActive: viewModel.activeFilterCardId == card.id
        ) {
            viewModel.toggleFilter(cardId: card.id)
        }
    }

    // MARK: - Queue section

    private var queueTabHeaders: some View {
        DashboardQueueTabHeaders(
            selectedQueueTab: $selectedQueueTab,
            isIpad: isIpad
        )
    }

    private var emptyQueueState: some View {
        DashboardEmptyQueueState(
            title: viewModel.emptyQueueTitle(iconColor: appColors.secondary),
            subtitle: viewModel.emptyQueueSubtitle(selectedQueueTab: selectedQueueTab)
        )
    }

    /// Swipeable queue pager shared across portrait + landscape for consistency.
    /// Backed by `UIPageViewController` (via `SwipeablePager`) so it both swipes
    /// natively AND honors programmatic selection — tapping the "Today's Queue" /
    /// "Recent Activity" headers animate-paginates exactly like a swipe. SwiftUI's
    /// `.page`-style `TabView` ignores programmatic selection once nested in a
    /// fixed-frame `GeometryReader` (the landscape layouts), which is why header
    /// taps didn't switch the list there.
    private var queuePager: some View {
        SwipeablePager(selection: $selectedQueueTab) { index in
            if index == 0 {
                queueScrollContent(
                    items: viewModel.filteredQueueItems,
                    idPrefix: "queue"
                ) {
                    AnyView(queueRowView(item: $0))
                }
            } else {
                queueScrollContent(
                    items: viewModel.filteredRecentItems,
                    idPrefix: "recent"
                ) {
                    AnyView(recentRowView(item: $0))
                }
            }
        }
    }

    private func queueScrollContent(
        items: [DashboardQueueItem],
        idPrefix: String,
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
                        // Each page's list gets its own structural identity via
                        // .id(idPrefix) so the two ForEach trees stay separate and
                        // a row shared by both tabs isn't hidden in one of them.
                        ForEach(items) { item in
                            rowBuilder(item)
                                .transition(.opacity)
                        }
                        .id(idPrefix)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            // Animate filtered-data changes; just show the data, no per-row stagger.
            .animation(.easeInOut(duration: 0.25), value: items.map(\.id))
        }
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
                    guard let freshBatch = viewModel.freshBatch(batchId: batch.batch_id)
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
                    // The detail screen resolves the txn from
                    // historyViewModel.filteredTransactionsOfUserByDate. The dashboard
                    // never populates that array (it loads its own dispenseCompleted),
                    // so seed it with the tapped txn before navigating — otherwise the
                    // detail screen finds nothing and shows empty.
                    historyViewModel.filteredTransactionsOfUserByDate = [txn]
                    historyViewModel.selectedTransactionId = txn.txn_id
                    router.navigate(to: .authentication(.user(.userSettings(.HistoryTransactionDetail))))
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
                await MainActor.run { viewModel.loadQueueData(userId: userId) }
            }
        }

        locationService.requestPermission()
        locationService.startUpdating()
        viewModel.loadQueueData(userId: userId)

        DrugCatalogStore.shared.fetchAll()
    }

    // MARK: - Select-bucket popup

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
                    textColor: appColors.primary,
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
