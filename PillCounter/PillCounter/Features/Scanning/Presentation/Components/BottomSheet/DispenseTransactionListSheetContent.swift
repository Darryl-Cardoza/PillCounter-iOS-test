//
//  DispenseTransactionList.swift
//  PillCounter
//
//  Created by Bhushan Patil on 08/06/26.
//


import SwiftUI

/// A single scrollable "Today's Queue" list that renders only `DispenseItemRowView`
/// rows, with PENDING / PRIORITY / CONTROLLED / HAZARDOUS filter tabs.
/// Designed to live inside `BottomSheet` — full-width bottom sheet in portrait
/// and a right-side panel in landscape — on both iPhone and iPad.
struct DispenseTransactionListSheetContent: View {

    // MARK: - Filter tabs
    private enum QueueTab: Int, CaseIterable {
        case pending, priority, controlled, hazardous

        var title: String {
            switch self {
            case .pending:    return "PENDING"
            case .priority:   return "PRIORITY"
            case .controlled: return "CONTROLLED"
            case .hazardous:  return "HAZARDOUS"
            }
        }
    }

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass
    @Environment(\.isLandscape) private var isLandscape

    /// Optional tap handler. When nil, tapping a row resumes the scan/count flow.
    var onSelect: ((PillCountTransactionEntity) -> Void)? = nil
    /// Optional home handler. When set, a Home button is shown in the header that
    /// should navigate back to the dashboard and clear the back stack.

    // MARK: - Local state
    /// All pending dispense transactions (any date), sorted oldest → newest.
    @State private var allPending: [PillCountTransactionEntity] = []
    @State private var pillCounts: [Int64: Int] = [:]
    @State private var selectedTab: QueueTab = .pending

    // MARK: - DAOs
    private let transactionDAO = TransactionStore.shared
    private let detailDAO = TransactionDetailStore.shared
    private let userStore = UserStore.shared

    private var userId: String { AppStorageManager.shared.userId ?? "" }

    // MARK: - Adaptive metrics
    private var isPad: Bool { hSizeClass == .regular && vSizeClass == .regular }
    private var horizontalPadding: CGFloat { isPad ? 20 : 16 }
    private var rowSpacing: CGFloat { isPad ? 14 : 10 }
    private var titleSize: CGFloat { isPad ? 20 : 17 }
    private var tabFontSize: CGFloat { isPad ? 14 : 12 }

    // MARK: - Filtering
    /// Rows shown for the given tab.
    /// PENDING (default) shows ALL pending dispense txns, oldest → newest.
    /// The other tabs filter that same set by priority / type / hazardous.
    private func transactions(for tab: QueueTab) -> [PillCountTransactionEntity] {
        switch tab {
        case .pending:
            return allPending
        case .priority:
            return allPending.filter {
                $0.txn_priority?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "high"
            }
        case .controlled:
            return allPending.filter {
                !(($0.drug?.drug_type ?? "")
                    .trimmingCharacters(in: .whitespaces).isEmpty)
            }
        case .hazardous:
            return allPending.filter { $0.drug?.is_hazardous == true }
        }
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar

            // Paged swipe between tabs — same mechanism as the dashboard's
            // Today's Queue / Recent Activity. Swiping updates `selectedTab`
            // (and the tab bar underline) automatically.
            TabView(selection: $selectedTab) {
                ForEach(QueueTab.allCases, id: \.rawValue) { tab in
                    let rows = transactions(for: tab)
                    Group {
                        if rows.isEmpty {
                            emptyState
                        } else {
                            listView(rows)
                        }
                    }
                    .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.primaryBackground)
        .onAppear { reload() }
        .onReceive(
            transactionDAO.transactionsDidChange.receive(on: DispatchQueue.main)
        ) { reload() }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            Text("Dispense's Queue")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundColor(appColors.text)
            Spacer()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, isLandscape ? 20 : 16)
        .padding(.bottom, 12)
    }
    // MARK: - Tab bar
    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(QueueTab.allCases, id: \.rawValue) { tab in
                    tabButton(tab)
                }
            }
            .fixedSize() // shrink HStack to fit content width
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading) // anchor to left
        }
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: QueueTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { selectedTab = tab }
        } label: {
            VStack(spacing: 4) {
                Text(tab.title)
                    .font(.system(size: tabFontSize, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Rectangle()
                    .fill(isSelected ? appColors.primary : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 8) // optional: spacing between tabs
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - List
    private func listView(_ rows: [PillCountTransactionEntity]) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: rowSpacing) {
                ForEach(rows, id: \.txn_id) { txn in
                    DispenseItemRowView(
                        data: txn.toRowData(pillCount: pillCounts[txn.txn_id] ?? 0)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { handleTap(txn) }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No items in the queue")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(appColors.text.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    private func handleTap(_ txn: PillCountTransactionEntity) {
        if let onSelect {
            onSelect(txn)
            return
        }

        let countType: CountType =
            txn.count_type?.uppercased() == CountType.REGULAR.rawValue
            ? .REGULAR : .FIXED
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

    // MARK: - Data
    private func reload() {
        guard let user = userStore.fetchByUserId(userId) else {
            allPending = []
            pillCounts = [:]
            return
        }

        let fixed = transactionDAO.fetchPartial(for: user, countType: .FIXED)
        let regular = transactionDAO.fetchPartial(for: user, countType: .REGULAR)

        // Sort high-priority first, then oldest → newest within each priority tier.
        let fresh = (fixed + regular)
            .filter { $0.batch_id == 0 && $0.status != CountStatus.ON_HOLD.rawValue }
            .sorted {
                let lhsHigh = $0.txn_priority?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "high"
                let rhsHigh = $1.txn_priority?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "high"
                if lhsHigh != rhsHigh { return lhsHigh }
                return $0.created_at < $1.created_at
            }

        var counts: [Int64: Int] = [:]
        for txn in fresh {
            counts[txn.txn_id] = Int(
                detailDAO.totalCountForStep(txnId: txn.txn_id, step: .targetVerification)
            )
        }

        allPending = fresh
        pillCounts = counts
    }
}
