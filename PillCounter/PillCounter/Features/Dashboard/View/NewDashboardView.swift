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

private struct DashboardStatCard: Identifiable {
    let id: String
    let iconName: String
    let iconColor: Color
    let count: Int
    let label: String
    let action: () -> Void
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
    @AppStorage(AppStorageManager.AppStorageKeys.isNewUser) var isNewUser: Bool = true
    @AppStorage(AppStorageManager.AppStorageKeys.isHl7Enable) var isHl7Enable: Bool = false
    @AppStorage(AppStorageManager.AppStorageKeys.selectedTerminalName) var selectedTerminalName: String = ""

    @State private var showStockCountPopup: Bool = false
    @State private var selectedStockCountOption: StockCountOption = .newBatch
    @State private var showSelectBucketIdPopup: Bool = false
    @State private var hasCheckedNewUser: Bool = false
    @State private var selectedQueueTab: Int = 0  // 0 = Today's Queue, 1 = Recent Activity
    @State private var dispensePartial: [PillCountTransactionEntity] = []
    @State private var inventoryPartial: [BatchCountEntity] = []
    @State private var pillCounts: [Int64: Int] = [:]
    @State private var batchNdcCounts: [Int64: Int] = [:]

    private let transactionDAO = TransactionStore.shared
    private let batchDAO = BatchStore.shared
    private let detailDAO = TransactionDetailStore.shared
    private let userStore = UserStore.shared

    private var isIpad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var mergedQueueItems: [DashboardQueueItem] {
        let dispenseItems = dispensePartial.map {
            DashboardQueueItem.dispense($0, pillCount: pillCounts[$0.txn_id] ?? 0)
        }
        let inventoryItems = inventoryPartial.map {
            DashboardQueueItem.inventory($0, ndcCount: batchNdcCounts[$0.batch_id] ?? 0)
        }
        return (dispenseItems + inventoryItems).sorted { $0.sortDate < $1.sortDate }
    }

    // MARK: - Stat cards built from live data

    private var statCards: [DashboardStatCard] {
        [
            DashboardStatCard(
                id: "disp-high-priority",
                iconName: "exclamationmark.circle.fill",
                iconColor: appColors.secondary,
                count: userViewModel.fixedCountTransactionPartialCount,
                label: "Disp.\nHigh Priority",
                action: {
                    router.selectedPillScanningType = .FIXED
                    router.navigate(to: .authentication(.login(.dashboard(.fixedCountPartial))))
                }
            ),
            DashboardStatCard(
                id: "disp-pending",
                iconName: "clock",
                iconColor: appColors.secondary,
                count: userViewModel.fixedCountTransactionPartialCount,
                label: "Disp.\nPending",
                action: {
                    router.selectedPillScanningType = .FIXED
                    router.navigate(to: .authentication(.login(.dashboard(.fixedCountPartial))))
                }
            ),
            DashboardStatCard(
                id: "disp-cont-drugs",
                iconName: "pills.fill",
                iconColor: appColors.secondary,
                count: userViewModel.fixedCountTransactionCompletedCount,
                label: "Disp.\nCont. Drugs",
                action: {
                    router.navigate(to: .authentication(.user(.userSettings(.History(.fixed, .completed)))))
                }
            ),
            DashboardStatCard(
                id: "disp-hazardous",
                iconName: "shield.fill",
                iconColor: appColors.secondary,
                count: 3,
                label: "Disp.\nHazardous",
                action: {}
            ),
            DashboardStatCard(
                id: "inv-cycle-count",
                iconName: "arrow.triangle.2.circlepath",
                iconColor: appColors.primary,
                count: stockCountViewModel.totalBatchCount,
                label: "Inv.\nCycle Count",
                action: {
                    router.navigate(to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountPartialBatchListScreen))))))
                }
            ),
            DashboardStatCard(
                id: "inv-pending-batch",
                iconName: "tray.full.fill",
                iconColor: appColors.primary,
                count: stockCountViewModel.totalCompletedBatchCount,
                label: "Inv.\nPending Batch",
                action: {
                    router.navigate(to: .authentication(.user(.userSettings(.History(.regular, .completed)))))
                }
            ),
        ]
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            appColors.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.top, safeAreaTop)

                // Fixed section — does not scroll
                VStack(alignment: .leading, spacing: 0) {
                    quickActionsSection
                        .padding(.bottom, 20)
                    statCardsSection
                        .padding(.bottom, 24)
                    Rectangle()
                        .fill(appColors.text.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.bottom, 24)
                    queueTabHeaders
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Swipeable scrollable queue content
                TabView(selection: $selectedQueueTab) {
                    queueScrollContent(items: mergedQueueItems)
                        .tag(0)
                    queueScrollContent(items: []) // Recent Activity placeholder
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: selectedQueueTab)
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
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: pillScanViewModel.showToast)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear(perform: onAppear)
        .customPopup(isPresented: $showStockCountPopup) { stockCountPopUp }
        .customPopup(isPresented: $showSelectBucketIdPopup) { selectBucketPopUp }
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
                    Text(userViewModel.pharmacyName.isEmpty ? "Pharmacy" : userViewModel.pharmacyName)
                        .font(.system(size: isIpad ? 18 : 15, weight: .semibold))
                        .foregroundColor(appColors.text)
                    if !selectedTerminalName.isEmpty {
                        Text("Terminal \(selectedTerminalName)")
                            .font(.system(size: isIpad ? 13 : 11))
                            .foregroundColor(appColors.text.opacity(0.6))
                    }
                }
            }

            Spacer()

            // Right: PMS status + Hamburger menu
            if isHl7Enable {
                PMSConnectionButtonView(pmsConnectionState: userViewModel.pmsConnectionState)
            }

            Button {
                router.navigate(to: .authentication(.user(.hamburgerMenu)))
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: isIpad ? 26 : 22, weight: .semibold))
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
                .font(.system(size: isIpad ? 13 : 11, weight: .semibold))
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
                        action: { showStockCountPopup = true; resetStockCountSelection() }
                    )
                }
            } else {
                VStack(spacing: 14) {
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
                        action: { showStockCountPopup = true; resetStockCountSelection() }
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
                .frame(width: isIpad ? 90 : 70, height: isIpad ? 90 : 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isIpad ? 22 : 18, weight: .semibold))
                        .foregroundColor(appColors.secondary)
                    Text(subtitle)
                        .font(.system(size: isIpad ? 14 : 12))
                        .foregroundColor(appColors.text.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, isIpad ? 24 : 16)
            .padding(.vertical, isIpad ? 48 : 40)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
        Button(action: card.action) {
            VStack(alignment: .leading, spacing: 4) {
                // Icon top-right
                HStack {
                    Spacer()
                    Image(systemName: card.iconName)
                        .font(.system(size: 13))
                        .foregroundColor(card.iconColor)
                }

                // Count
                Text("\(card.count)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(appColors.primary)
                    .padding(.top, 4)

                // Label
                Text(card.label)
                    .font(.system(size: 10))
                    .foregroundColor(appColors.text.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
                    Text("No pending items")
                        .font(.system(size: 13))
                        .foregroundColor(appColors.text.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                } else {
                    ForEach(items) { item in
                        queueRowView(item: item)
                    }
                }
            }
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
                    .font(.system(size: isIpad ? 12 : 11, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? appColors.text : appColors.text.opacity(0.45))
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
            Button {
                router.selectedPillScanningType = .FIXED
                router.navigate(to: .authentication(.login(.dashboard(.fixedCountPartial))))
            } label: {
                dashboardDispenseRow(data: data)
            }
            .buttonStyle(PlainButtonStyle())

        case .inventory(let batch, let ndcCount):
            let data = batch.toStockData(ndcCount: ndcCount)
            Button {
                router.navigate(to: .authentication(.login(.dashboard(.pillCount(.stockCount(.stockCountPartialBatchListScreen))))))
            } label: {
                dashboardInventoryRow(data: data)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func dashboardDispenseRow(data: TransactionRowData) -> some View {
        HStack(spacing: 12) {
            ThumbnailImageView(
                imagePath: data.barcodeImagePath,
                width: 56,
                height: 56,
                cornerRadius: 8,
                borderColor: appColors.primaryBackground,
                placeholderImageName: "dispense_placeholder",
                placeholderBackgroundColor: appColors.text,
                placeholderSize: CGSize(width: 22, height: 22),
                showImageBackground: appColors.primaryBackground
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("NDC \(data.ndc)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(appColors.primary)
                        .lineLimit(1)
                    if !data.drugType.isEmpty {
                        Text(data.drugType)
                            .font(.system(size: 11))
                            .foregroundColor(appColors.text.opacity(0.5))
                    }
                }
                Text(data.drugName)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(DateUtils.formatToUSDateTime(data.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.5))
                    if !data.bucketId.isEmpty && data.bucketId != "NORMAL" {
                        Text(data.bucketId)
                            .font(.system(size: 11))
                            .foregroundColor(appColors.text.opacity(0.7))
                    }
                }
            }

            Spacer()

            let fillFraction: Double = data.targetCount > 0
                ? min(Double(data.pillCount) / Double(data.targetCount), 1.0) : 0
            VStack(spacing: 4) {
                DonutProgressView(fraction: fillFraction, appColors: appColors, size: 26)
                Text("\(data.pillCount)/\(data.targetCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(appColors.secondary)
            }
            .padding(.trailing, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func dashboardInventoryRow(data: StockData) -> some View {
        HStack(spacing: 12) {
            ThumbnailImageView(
                imagePath: nil,
                width: 56,
                height: 56,
                cornerRadius: 8,
                borderColor: appColors.primaryBackground,
                placeholderImageName: data.isFromPms ? "dispense_placeholder" : "batch_icon",
                placeholderBackgroundColor: appColors.text,
                placeholderSize: CGSize(width: 22, height: 22),
                showImageBackground: appColors.primaryBackground
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(String(data.batchId))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appColors.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(DateUtils.formatToUSDateTime(data.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.5))
                    if data.bucketId != "NORMAL" {
                        Text(data.bucketId)
                            .font(.system(size: 11))
                            .foregroundColor(appColors.text.opacity(0.7))
                    }
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Text(String(data.ndcCount))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(appColors.secondary)
                Text("NDCs")
                    .font(.system(size: 11))
                    .foregroundColor(appColors.text.opacity(0.6))
            }
            .padding(.trailing, 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func loadQueueData() {
        guard let user = userStore.fetchByUserId(userId) else { return }

        let fixed = transactionDAO.fetchPartial(for: user, countType: .FIXED)
        let regular = transactionDAO.fetchPartial(for: user, countType: .REGULAR)
        dispensePartial = (fixed + regular)

        var counts: [Int64: Int] = [:]
        for txn in dispensePartial {
            counts[txn.txn_id] = detailDAO.totalCount(txnId: txn.txn_id)
        }
        pillCounts = counts

        let batches = batchDAO.fetchAllPartial()
        inventoryPartial = batches

        var ndcCounts: [Int64: Int] = [:]
        for batch in batches {
            ndcCounts[batch.batch_id] = batchDAO.getTransactionCount(for: batch.batch_id)
        }
        batchNdcCounts = ndcCounts
    }

    // MARK: - Navigation helpers

    private func navigateToDispense() {
        router.selectedPillScanningType = .FIXED
        router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.rx_label))))))
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
    }

    // MARK: - Popups (same logic as original DashboardView)

    private var stockCountPopUp: some View {
        VStack(spacing: 35) {
            VStack(alignment: .leading) {
                Text(L10n.Dashboard.Popup.whatWouldYouDo)
                    .font(.system(size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(appColors.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 28) {
                PillCountingRadioButton(
                    option: StockCountOption.newBatch,
                    selectedOption: $selectedStockCountOption,
                    label: L10n.Dashboard.Popup.createNewBatch,
                    selectedColor: appColors.secondary,
                    unselectedColor: .gray,
                    size: 20,
                    lineWidth: 2,
                    textColor: appColors.text
                )
                PillCountingRadioButton(
                    option: StockCountOption.existingBatch,
                    selectedOption: $selectedStockCountOption,
                    label: L10n.Dashboard.Popup.continueLastBatch,
                    selectedColor: appColors.secondary,
                    unselectedColor: .gray,
                    size: 20,
                    lineWidth: 2,
                    textColor: appColors.text
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EqualWidthHStackButtons(spacing: 20) {
                PillCountingButton(
                    iconName: nil,
                    title: L10n.Common.cancel,
                    textColor: appColors.text,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: { showStockCountPopup = false }
                )
                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        switch selectedStockCountOption {
                        case .newBatch:
                            let buckets = userViewModel.bucket
                            pillScanViewModel.bucketOptions = buckets
                            pillScanViewModel.selectedBucket = buckets.first ?? ""
                            showSelectBucketIdPopup = true
                            showStockCountPopup = false
                        case .existingBatch:
                            if stockCountViewModel.continueLastBatch() {
                                router.selectedPillScanningType = .REGULAR
                                router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.stockCount))))))
                                resetStockCountSelection()
                            } else {
                                pillScanViewModel.showToastMessage(text: L10n.Menu.noLastBatchFound)
                            }
                            showStockCountPopup = false
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var selectBucketPopUp: some View {
        VStack(spacing: 35) {
            VStack(alignment: .leading) {
                Text(L10n.Dashboard.Popup.selectBucket)
                    .font(.system(size: 16))
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
                    font: .system(size: 14, weight: .semibold),
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
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        handleStockCountSelectedOption()
                        showSelectBucketIdPopup = false
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
    }

    private func handleStockCountSelectedOption() {
        stockCountViewModel.createNewBatch(bucketId: pillScanViewModel.selectedBucket)
        router.selectedPillScanningType = .REGULAR
        router.navigate(to: .authentication(.login(.dashboard(.pillCount(.scan(.stockCount))))))
        resetStockCountSelection()
    }

    private func resetStockCountSelection() {
        selectedStockCountOption = .newBatch
    }
}
