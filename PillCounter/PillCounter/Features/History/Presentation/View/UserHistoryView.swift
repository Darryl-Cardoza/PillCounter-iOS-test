//
//  UserHistoryView.swift
//  PillCounter
//
//  Features/History/Presentation/View/UserHistoryView.swift
//

import SwiftUI

struct UserHistoryView: View {

    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router

    // MARK: - HistoryViewModel (owned by this view)
    @EnvironmentObject private var historyViewModel: HistoryViewModel

    // MARK: - Date State
    @State private var startDate: Date? = Date()
    @State private var endDate: Date? = nil
    @State private var showDeleteConfirmation: Bool = false

    // MARK: - Search State
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - PDF
    @StateObject private var pdfService = PDFShareService.shared

    // MARK: - Filter State
    let filterType: HistoryFilterType
    @State private var activeTypeFilter: HistoryFilterType = .fixed
    @State private var activeStatusFilter: HistoryStatusFilter = .all


    // MARK: - Body
    var body: some View {
        ZStack {
            BaseView(
                topRatio: isSearching ? 0.2 : 0.4,
                topContent: {
                    if !isSearching {
                        userHistoryContent()
                    }
                },
                bottomContent: {
                    userHistoryTransactionsList
                },
                headerActions: {
                    if isSearching {
                        UnderlinedSearchBar(
                            text: $searchText,
                            isFocused: $isSearchFieldFocused,
                            appColors: appColors,
                            onExitSearch: {
                                withAnimation(.spring()) {
                                    isSearching = false
                                    searchText = ""
                                    isSearchFieldFocused = false
                                }
                            }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        HStack(spacing: 16) {
                            Button {
                                withAnimation(.spring()) {
                                    isSearching = true
                                    isSearchFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appColors.secondary)
                            }
                        }
                        .padding(.trailing, 16)
                        .transition(.opacity)
                    }
                },
                showBackButton: !isSearching,
                showHamburgerMenu: false,
                title: NSLocalizedString("HISTORY", comment: "")
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
            fetchAll()
        }
        .onChange(of: startDate)        { _, _ in fetchAll() }
        .onChange(of: endDate)          { _, _ in fetchAll() }
        .onChange(of: activeTypeFilter) { _, _ in
            activeStatusFilter = .all
            searchText = ""
            fetchAll()
        }
        .onChange(of: activeStatusFilter) { _, _ in
            historyViewModel.applyFilters(status: activeStatusFilter, search: searchText)
        }
        .onChange(of: searchText) { _, _ in
            historyViewModel.applyFilters(status: activeStatusFilter, search: searchText)
        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            deleteConfirmationPopUp
        }
    }

    // MARK: - Fetch All
    private func fetchAll() {
        guard let start = startDate else {
            historyViewModel.filteredTransactionsOfUserByDate = []
            historyViewModel.filteredBatchesOfUserByDate = []
            return
        }

        let end = endDate ?? start

        Task {
            await historyViewModel.getTransactionsByDate(
                startDate: start,
                endDate: end,
                filter: activeTypeFilter
            )
            await historyViewModel.getBatchesByDate(startDate: start, endDate: end)

            historyViewModel.applyFilters(
                status: activeStatusFilter,
                search: searchText
            )
        }
    }

    // MARK: - Delete Confirmation Popup
    private var deleteConfirmationPopUp: some View {
        ConfirmationDialogue(
            title: "Confirm Delete",
            message: "Are you sure you want to delete the records for the selected date? This action cannot be undone.",
            cancelButtonText: "NO",
            confirmButtonText: "YES",
            onCancel: {
                showDeleteConfirmation = false
            },
            onConfirm: {
                Task {
                    guard let start = startDate else { return }
                    await historyViewModel.softDeleteTransactionsForSelectedDate(
                        startDate: start,
                        endDate: endDate ?? start,
                        filter: activeTypeFilter
                    )
                    showDeleteConfirmation = false
                }
            }
        )
        .frame(width: 275)
    }

    // MARK: - Transaction List
    private var userHistoryTransactionsList: some View {
        VStack(spacing: 8) {
            VStack(spacing: 15) {
                HStack {
                    txnTypeFilter
                    if !historyViewModel.filteredTransactionsOfUserByDate.isEmpty && !isSearching {
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image("delete")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .overlay(appColors.primary)
                                .mask(
                                    Image("delete")
                                        .resizable()
                                        .scaledToFit()
                                )
                        }
                    }
                }
                statusFilterChips
            }

            Spacer().frame(height: 15)

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
                "No History",
                systemImage: "clock.arrow.circlepath",
                description: Text("No transactions found for this period.")
            )
            .padding(.top, 40)
        } else if historyViewModel.transactionRows.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No transactions match your search.")
            )
            .padding(.top, 40)
        } else {
            ForEach(historyViewModel.transactionRows) { row in
                DispenseItemRowView(data: row, appColors: appColors)
                    .onTapGesture {
                        historyViewModel.selectedTransactionId = Int64(row.id)
                        router.navigate(to: .authentication(.user(.userSettings(.HistoryTransactionDetail))))
                    }
            }
        }
    }

    // MARK: - Batch Content
    @ViewBuilder
    private var batchContent: some View {
        if historyViewModel.filteredBatchesOfUserByDate.isEmpty {
            ContentUnavailableView(
                "No History",
                systemImage: "clock.arrow.circlepath",
                description: Text("No Batches found for this period.")
            )
            .padding(.top, 40)
        } else if historyViewModel.batchRows.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No Batches match your search.")
            )
            .padding(.top, 40)
        } else {
            ForEach(historyViewModel.batchRows) { row in
                StockItemRowView(data: row, appColors: appColors)
                    .onTapGesture {
                        historyViewModel.selectedBatchId = row.batchId
                        router.navigate(to: .authentication(.user(.userSettings(.HistoryBatchDetail))))
                    }
            }
        }
    }

    // MARK: - Calendar
    private func userHistoryContent() -> some View {
        PillCountingCalendar(
            selectedColor: appColors.secondary,
            textColor: appColors.text,
            backgroundColor: .clear,
            startDate: $startDate,
            endDate: $endDate
        )
        .padding(
            .top,
            isLandscape ? SafeAreaInsets.top + 50 : SafeAreaInsets.top + 30
        )
        .padding(.leading, isLandscape ? SafeAreaInsets.leading : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
    }

    // MARK: - Status Filter Chips
    private var statusFilterChips: some View {
        let counts = historyViewModel.getStatusCounts(for: activeTypeFilter)

        return HStack(spacing: 8) {
            FilterChip(
                label: "All",
                count: counts.all,
                value: HistoryStatusFilter.all,
                selectedValue: activeStatusFilter,
                appColors: appColors
            ) { activeStatusFilter = $0 }

            FilterChip(
                label: "Completed",
                count: counts.completed,
                value: .completed,
                selectedValue: activeStatusFilter,
                appColors: appColors
            ) { activeStatusFilter = $0 }

            FilterChip(
                label: "Pending",
                count: counts.pending,
                value: .pending,
                selectedValue: activeStatusFilter,
                appColors: appColors
            ) { activeStatusFilter = $0 }

            Spacer()
        }
    }

    // MARK: - Type Filter Chips
    private var txnTypeFilter: some View {
        let dispenseCount = historyViewModel.filteredTransactionsOfUserByDate.count
        let stockCount    = historyViewModel.filteredBatchesOfUserByDate.count

        return HStack(spacing: 8) {
            FilterChip(
                label: "Dispensed",
                count: dispenseCount,
                value: HistoryFilterType.fixed,
                selectedValue: activeTypeFilter,
                appColors: appColors
            ) { activeTypeFilter = $0 }

            FilterChip(
                label: "Stock Count",
                count: stockCount,
                value: .regular,
                selectedValue: activeTypeFilter,
                appColors: appColors
            ) { activeTypeFilter = $0 }

            Spacer()
        }
    }
}
