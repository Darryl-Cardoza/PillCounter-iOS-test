//
//  DashboardView.swift
//  PillCounter
//
//  B2B dashboard UI. Data, merging, filtering and stat-card derivation live in
//  DashboardViewModel; this view owns layout and navigation only.
//

import SwiftUI

// MARK: - Main view

struct DashboardView: View {

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel

    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var locationService = LocationService.shared

    // userId is stored in Keychain via AppStorageManager — @AppStorage reads UserDefaults
    // and would always return "". Read directly from the Keychain-backed store instead.
    private var userId: String { AppStorageManager.shared.userId ?? "" }
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser:
        Bool = true
    private var isPmsIntegrated: Bool {
        AppStorageManager.shared.isPmsIntegrated || AppStorageManager.shared.isStandalone
    }
    @AppStorage(AppStorageManager.AppStorageKeys.selectedTerminalName)
    var selectedTerminalName: String = ""

    /// Shown when a dispense action is tapped while PMS integration is off.
    @State private var showFeatureUnavailablePopup: Bool = false
    @State private var hasCheckedNewUser: Bool = false
    @State private var selectedQueueTab: Int = 0  // 0 = Today's Queue, 1 = Recent Activity

    // Bucket-picker state is local to this screen's popup. The chosen bucket is
    // handed to the stock-count flow via the navigation route, so the dashboard
    // needs no stock-count or pill-scan view model.
    @State private var bucketOptions: [String] = []
    @State private var selectedBucket: String = ""

    // The bucket popup is presented as a function of the data itself: it's shown
    // exactly when bucketOptions is non-empty. Driving presentation off a separate
    // Bool meant the data write and the show write were two independent @State
    // updates — on first launch SwiftUI could evaluate the popup body before the
    // bucketOptions write propagated, rendering an empty list. With one source of
    // truth, the popup can never appear without its options.
    private var showSelectBucketIdPopup: Binding<Bool> {
        Binding(
            get: { !bucketOptions.isEmpty },
            set: { if !$0 { bucketOptions = [] } }
        )
    }

    @Environment(\.isLandscape) private var isLandscape

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

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
        // Queue refreshes on any transaction store change (create/update/delete/
        // status), which covers scan completion — so no PillScanViewModel observer
        // is needed here.
        .onReceive(TransactionStore.shared.transactionsDidChange) {
            viewModel.loadQueueData(userId: userId)
        }
        .customPopup(isPresented: showSelectBucketIdPopup) {
            selectBucketPopUp
        }
        .customPopup(isPresented: $showFeatureUnavailablePopup) {
            featureUnavailablePopUp
        }
    }

    private var featureUnavailablePopUp: some View {
        ConfirmationDialogue(
            title: L10n.Menu.featureNotAvailableTitle,
            message: L10n.Menu.featureNotAvailableMessage,
            cancelButtonText: "",
            confirmButtonText: L10n.Common.ok,
            showSingleConfirmButton: true,
            onCancel: {},
            onConfirm: { showFeatureUnavailablePopup = false }
        )
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
                        QuickActionCardCompact(
                            iconName: "dispense_dashboard_icon",
                            title: L10n.Dashboard.FixedCount.title,
                            subtitle: L10n.Dashboard.FixedCount.subtitle,
                            action: navigateToDispense
                        )
                        .frame(maxHeight: .infinity)
                        QuickActionCardCompact(
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
                            QuickActionCardExpanded(
                                iconName: "icon_dashboard_dispense",
                                title: L10n.Dashboard.FixedCount.title,
                                subtitle: L10n.Dashboard.FixedCount.subtitle,
                                action: navigateToDispense
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            QuickActionCardExpanded(
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
                    .frame(width: isIpad ? 50 : 30, height: isIpad ? 50 : 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        userViewModel.pharmacyName.isEmpty
                            ? L10n.Dashboard.pharmacyPlaceholder
                            : userViewModel.pharmacyName
                    )
                    .font(.system(size: isIpad ? 20 : 17, weight: .semibold))
                    .foregroundColor(appColors.text)
                    
                    // Showing terminal name and username
                    let displayName = isPmsIntegrated && !selectedTerminalName.isEmpty
                        ? "\(selectedTerminalName) | \(userViewModel.fullName)"
                        : userViewModel.fullName

                    Text(displayName)
                        .font(.system(size: isIpad ? 15 : 13))
                        .foregroundColor(appColors.text.opacity(0.6))
                }
            }

            Spacer()

            // Right: PMS status + Hamburger menu
            if isPmsIntegrated {
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
        QuickActionCardPortrait(
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
            title: viewModel.emptyQueueTitle(),
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
        // SwipeablePager hosts each page in a UIHostingController, so both pages
        // must resolve to the same `Page` type — hence the AnyView at this
        // boundary. (The per-row builder inside queueScrollContent stays
        // strongly typed; only the two top-level pages are erased.)
        SwipeablePager(selection: $selectedQueueTab) { index in
            if index == 0 {
                AnyView(
                    queueScrollContent(
                        items: viewModel.filteredQueueItems,
                        idPrefix: "queue"
                    ) {
                        DashboardTodaysQueueRow(
                            item: $0,
                            router: router,
                            // PMS off → block dispense rows in the pending queue list;
                            // tapping shows the popup instead of resuming the scan.
                            // (The Dispense quick-action card is NOT blocked.)
                            onDispenseBlocked: isPmsIntegrated
                                ? nil
                                : { showFeatureUnavailablePopup = true }
                        )
                    }
                )
            } else {
                AnyView(
                    queueScrollContent(
                        items: viewModel.filteredRecentItems,
                        idPrefix: "recent"
                    ) {
                        DashboardRecentActivityRow(item: $0, router: router)
                    }
                )
            }
        }
    }

    private func queueScrollContent<Row: View>(
        items: [DashboardQueueItem],
        idPrefix: String,
        @ViewBuilder rowBuilder: @escaping (DashboardQueueItem) -> Row
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

    // MARK: - Navigation helpers

    private func navigateToDispense() {
        router.selectedPillScanningIsDispense = true
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
                await userViewModel.checkAndRefreshTokenIfNeeded()
                await userViewModel.getUser(forceRemote: true)
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
        DashboardSelectBucketPopup(
            bucketOptions: bucketOptions,
            selectedBucket: $selectedBucket,
            onCancel: { bucketOptions = [] },
            onConfirm: {
                let bucket = selectedBucket
                bucketOptions = []
                createBatchAndNavigate(bucketId: bucket)
            }
        )
    }

    private func handleInventoryTapped() {
        // First visit: onAppear's getUser may still be in flight, so the
        // Keychain-backed bucket list can be empty here even though the user
        // does have buckets. `userViewModel.bucket` is a computed property over
        // Keychain (not @Published), so SwiftUI never re-renders this popup when
        // it populates — which is why buckets only appeared on a later visit.
        // Resolve the list before presenting so it's always correct.
        // UserViewModel is @MainActor, so this Task runs on the main actor —
        // the UI mutations below are safe without an explicit MainActor.run.
        Task {
            // Read straight from the Keychain-backed store rather than through
            // userViewModel.bucket — same source, but makes it explicit this is a
            // point-in-time read with no SwiftUI binding.
            var buckets = AppStorageManager.shared.bucket
            var meaningful = buckets.filter { $0 != "NORMAL" && !$0.isEmpty }

            if meaningful.isEmpty {
                // Buckets may simply not have loaded yet — fetch user data and retry
                // once before falling back to NORMAL. Force the remote call:
                // getUser() serves from the local cache when a local user exists,
                // and the cache path never writes the bucket list (only the remote
                // auth/me path does). Without forceRemote the retry returned early
                // with no buckets — which is why the popup was empty on first launch.
                await userViewModel.getUser(forceRemote: true)
                buckets = AppStorageManager.shared.bucket
                meaningful = buckets.filter { $0 != "NORMAL" && !$0.isEmpty }
            }

            if meaningful.isEmpty {
                // No real bucket choices — skip popup, use NORMAL directly
                createBatchAndNavigate(bucketId: "NORMAL")
            } else {
                // Presentation is derived from bucketOptions (see showSelectBucketIdPopup):
                // setting it both fills the list AND shows the popup in one atomic
                // @State update, so the list is never empty on first render.
                selectedBucket = buckets.first ?? ""
                bucketOptions = buckets
            }
        }
    }

    private func createBatchAndNavigate(bucketId: String) {
        // Pass the bucket in the route; the scan screen starts the new batch in
        // onAppear, so the dashboard needs no StockCountViewModel.
        router.navigate(
            to: .authentication(
                .login(.dashboard(.pillCount(.scan(.stockCount, bucketId: bucketId))))
            )
        )
    }
}
