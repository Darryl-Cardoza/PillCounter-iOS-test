//
//  UserHistoryView.swift
//  PillCounter
//
//  Features/History/Presentation/View/UserHistoryView.swift
//

import SwiftUI
import Foundation

struct UserHistoryView: View {
    
    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var historyViewModel: HistoryViewModel
    
    @EnvironmentObject private var toastManager: ToastManager

    // MARK: - Date State
    @State private var showDeleteConfirmation: Bool = false

    // MARK: - Search State
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - PDF
    @StateObject private var pdfService = PDFShareService.shared

    // MARK: - Filter State
    let filterType: HistoryFilterType
    let stautsType: HistoryStatusFilter
    @State private var activeTypeFilter: HistoryFilterType = .fixed
    @State private var activeStatusFilter: HistoryStatusFilter = .all
    
    @State private var listVersion: Int = 0
    @State private var hasAppeared: Bool = false
    @State private var appearedTxnIds: Set<String> = []
    @State private var appearedBatchIds: Set<Int64> = []

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            ZStack {
                BaseView(
                    topRatio: computedTopRatio,
                    topContent: {
                        topContentView
                    },
                    bottomContent: {
                        bottomContentView
                    },
                    headerActions: {
                        headerActionsView
                    },
                    showBackButton: !isSearching,
                    showHamburgerMenu: false,
                    title: isSearching ? "" : L10n.History.title
                )
                
                if pdfService.isLoading {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        PillCountingLoader()
                    }
                }
            }
            .onAppear {
                activeTypeFilter = filterType
                activeStatusFilter = stautsType
                fetchAll()
                DispatchQueue.main.async {
                    hasAppeared = true
                }
            }
            .onChange(of: historyViewModel.selectedStartDate) { _, _ in fetchAll() }
            .onChange(of: historyViewModel.selectedEndDate)   { _, _ in fetchAll() }
            .onChange(of: activeTypeFilter) { _, _ in
                if hasAppeared {
                    activeStatusFilter = .all
                }
                searchText = ""
                fetchAll()
            }
            .onChange(of: activeStatusFilter) { _, _ in
                appearedTxnIds.removeAll()
                appearedBatchIds.removeAll()
                historyViewModel.applyFilters(status: activeStatusFilter, search: searchText)
                listVersion += 1
            }
            .onChange(of: searchText) { _, _ in
                appearedTxnIds.removeAll()
                appearedBatchIds.removeAll()
                historyViewModel.applyFilters(status: activeStatusFilter, search: searchText)
                listVersion += 1
            }
            .customPopup(isPresented: $showDeleteConfirmation) {
                deleteConfirmationPopUp
            }
        }
    }

    // MARK: - Top Ratio
    // Portrait: 0.4 normal / 0.2 searching (top-bottom split by height)
    // Landscape: 0.4 normal (left-right split by width) / 1.0 searching (full-width left panel)
    private var computedTopRatio: CGFloat {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        if isLandscape && isSearching { return  1.0 }
        if isSearching { return isLandscape ? 0 : 0.10 }
        if isLandscape {
            return isIPad ? 0.40 : 0.40
        }
        return isIPad ? 0.40 : 0.35
    }


    // MARK: - Top Content
    @ViewBuilder
    private var topContentView: some View {
        if isLandscape && isSearching {
            landscapeSearchContent
        } else if !isSearching {
            userHistoryContent()
        }
    }

    // MARK: - Bottom Content
    @ViewBuilder
    private var bottomContentView: some View {
        if isLandscape && isSearching {
            EmptyView()
        } else {
            userHistoryTransactionsList
        }
    }

    // MARK: - Header Actions (portrait + landscape)
    @ViewBuilder
    private var headerActionsView: some View {
        if isSearching {
            UnderlinedSearchBar(
                text: $searchText,
                isFocused: $isSearchFieldFocused,
                appColors: appColors,
                onExitSearch: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSearching = false
                        searchText = ""
                        isSearchFieldFocused = false
                    }
                }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if !isLandscape {
            // Portrait only — in landscape the search icon lives in the calendar panel
            HStack {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSearching = true
                        isSearchFieldFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(appColors.primary)
                }
            }
            .padding(.trailing, 16)
            .transition(.opacity)
        }
    }

    // MARK: - Landscape Search Content
    // topRatio: 1.0 so this is the full screen; top-pad to clear the header overlay.
    private var landscapeSearchContent: some View {
        userHistoryTransactionsList
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appColors.secondaryBackground)
            .padding(.top, 40)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSearching)
    }

    // MARK: - Fetch All
    private func fetchAll() {
        guard let start = historyViewModel.selectedStartDate else {
            historyViewModel.filteredTransactionsOfUserByDate = []
            historyViewModel.filteredBatchesOfUserByDate = []
            return
        }

        let end = historyViewModel.selectedEndDate ?? start

        Task {
            await historyViewModel.getTransactionsByDate(
                startDate: start,
                endDate: end,
                filter: activeTypeFilter
            )
            await historyViewModel.getBatchesByDate(startDate: start, endDate: end)
            historyViewModel.applyFilters(status: activeStatusFilter, search: searchText)
            appearedTxnIds.removeAll()
            appearedBatchIds.removeAll()
            listVersion += 1
        }
    }

    
    // MARK: - Delete Confirmation Popup
    private var deleteConfirmationPopUp: some View {
        ConfirmationDialogue(
            title: L10n.History.confirmDelete,
            message: L10n.History.deleteConfirmMessage,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes,
            onCancel: {
                showDeleteConfirmation = false
            },
            onConfirm: {
                Task {
                    guard let start = historyViewModel.selectedStartDate else { return }
                    await historyViewModel.softDeleteTransactionsForSelectedDate(
                        startDate: start,
                        endDate: historyViewModel.selectedEndDate ?? start,
                        filter: activeTypeFilter,
                        status: activeStatusFilter,
                        search: searchText
                    )
                    showDeleteConfirmation = false
                }
            }
        )
        .frame(width: 275)
    }

    // MARK: - Transaction List (used as bottomContent in normal mode, and inside
    private var userHistoryTransactionsList: some View {
        VStack(spacing: 8) {
            if !isSearching{
                VStack(spacing: 15) {
                    HStack {
                        txnTypeFilter
                        let isEmpty = activeTypeFilter == .fixed
                            ? historyViewModel.transactionRows.isEmpty
                            : historyViewModel.batchRows.isEmpty

                        if !isEmpty {
                            Button {
                                let isEmpty: Bool
                                
                                if activeTypeFilter == .fixed {
                                    isEmpty = historyViewModel.transactionRows.isEmpty
                                } else {
                                    isEmpty = historyViewModel.batchRows.isEmpty
                                }
                                
                                if isEmpty {
                                    toastManager.show(message: L10n.History.noItemsToDelete)
                                } else {
                                    showDeleteConfirmation = true
                                }
                                
                            } label: {
                                Image("delete")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .overlay(appColors.primary)
                                    .mask(Image("delete").resizable().scaledToFit())
                            }
                        }
                    }
                    statusFilterChips
                }
                
                Spacer().frame(height: 10)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading) {
                    if activeTypeFilter == .fixed {
                        transactionContent
                    } else {
                        batchContent
                    }
                }
                .padding(.bottom, 20)
            }
            .id(listVersion)
            .animation(nil, value: activeTypeFilter)
            .animation(nil, value: historyViewModel.transactionRows.count)
            .animation(nil, value: historyViewModel.batchRows.count)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
        .cornerRadius(24)
    }

    // MARK: - Transaction Content
    @ViewBuilder
    private var transactionContent: some View {
        if historyViewModel.filteredTransactionsOfUserByDate.isEmpty {
            ContentUnavailableView(
                L10n.History.noHistory,
                systemImage: "clock.arrow.circlepath",
                description: Text(L10n.History.noTransactionsFound)
            )
            .padding(.top, 40)
        } else if historyViewModel.transactionRows.isEmpty {
            ContentUnavailableView(
                L10n.History.noResults,
                systemImage: "magnifyingglass",
                description: Text(L10n.History.noTransactionsMatch)
            )
            .padding(.top, 40)
        } else {
            ForEach(Array(historyViewModel.transactionRows.enumerated()), id: \.element.id) { index, row in
                let didAppear = appearedTxnIds.contains(row.id)

                DispenseItemRowView(data: row)
                    .onTapGesture {
                        historyViewModel.selectedTransactionId = Int64(row.id) ?? 0
                        router.navigate(to: .authentication(.user(.userSettings(.HistoryTransactionDetail))))
                    }
                    .opacity(didAppear ? 1 : 0)
                    .offset(y: didAppear ? 0 : 20)
                    .onAppear {
                        guard !appearedTxnIds.contains(row.id) else { return }
                        withAnimation(
                            .spring(response: 0.42, dampingFraction: 0.78)
                                .delay(Double(index) * 0.06)
                        ) {
                            appearedTxnIds.insert(row.id)
                        }
                    }
            }
        }
    }

    // MARK: - Batch Content
    @ViewBuilder
    private var batchContent: some View {
        if historyViewModel.filteredBatchesOfUserByDate.isEmpty {
            ContentUnavailableView(
                L10n.History.noHistory,
                systemImage: "clock.arrow.circlepath",
                description: Text(L10n.History.noBatchesFound)
            )
            .padding(.top, 40)
        } else if historyViewModel.batchRows.isEmpty {
            ContentUnavailableView(
                L10n.History.noResults,
                systemImage: "magnifyingglass",
                description: Text(L10n.History.noBatchesMatch)
            )
            .padding(.top, 40)
        } else {
            ForEach(Array(historyViewModel.batchRows.enumerated()), id: \.element.batchId) { index, row in
                let hasAppeared = appearedBatchIds.contains(row.batchId)
                StockItemRowView(data: row)
                    .onTapGesture {
                        historyViewModel.selectedBatchId = row.batchId
                        router.navigate(to: .authentication(.user(.userSettings(.HistoryBatchDetail))))
                    }
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 20)
                    .onAppear {
                        guard !appearedBatchIds.contains(row.batchId) else { return }
                        withAnimation(
                            .spring(response: 0.42, dampingFraction: 0.78)
                                .delay(Double(index) * 0.06)
                        ) {
                            appearedBatchIds.insert(row.batchId)
                        }
                    }
            }
        }
    }

    // MARK: - Calendar
    private func userHistoryContent() -> some View {
        ZStack(alignment: .topTrailing) {
            PillCountingCalendar(
                selectedColor: appColors.primary,
                textColor: appColors.text,
                backgroundColor: .clear,
                startDate: $historyViewModel.selectedStartDate,
                endDate: $historyViewModel.selectedEndDate,
                monthsToShow: $historyViewModel.calendarMonthsToShow
            )
            .padding(.top,  52)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isLandscape {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSearching = true
                        isSearchFieldFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(appColors.primary)
                }
                .padding(.top, 10)
                .frame(height: 52, alignment: .center)
                .padding(.trailing, 16)
            }
        }
        .background(appColors.secondaryBackground)
    }

    // MARK: - Status Filter Chips
    private var statusFilterChips: some View {
        let counts = historyViewModel.getStatusCounts(for: activeTypeFilter)

        return HStack(spacing: 8) {
            FilterChip(
                label: L10n.History.filterAll,
                count: counts.all,
                value: HistoryStatusFilter.all,
                selectedValue: activeStatusFilter
            ) { activeStatusFilter = $0 }

            FilterChip(
                label: L10n.History.filterCompleted,
                count: counts.completed,
                value: .completed,
                selectedValue: activeStatusFilter
            ) { activeStatusFilter = $0 }

            FilterChip(
                label: L10n.History.filterPending,
                count: counts.pending,
                value: .pending,
                selectedValue: activeStatusFilter
            ) { activeStatusFilter = $0 }

            Spacer()
        }
    }

    // MARK: - Type Filter Chips
    private var txnTypeFilter: some View {
        let dispenseCount = historyViewModel.filteredTransactionsOfUserByDate.count
        let stockCount    = historyViewModel.filteredBatchesOfUserByDate.count

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabItem(
                    label: "\(L10n.History.filterDispensed) (\(dispenseCount))",
                    isSelected: activeTypeFilter == .fixed
                ) {
                    activeTypeFilter = .fixed
                }

                TabItem(
                    label: "\(L10n.History.filterStockCount) (\(stockCount))",
                    isSelected: activeTypeFilter == .regular
                ) {
                    activeTypeFilter = .regular
                }

                Spacer()
            }

            Divider()
        }
    }
    
    private struct TabItem: View {
        let label: String
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 0) {
                    Text(label)
                        .font(.system(size: 14, weight: isSelected ? .semibold	 : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                }
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .frame(maxWidth: 150)
        }
    }
        
}
