//
//  UserHistoryView.swift
//  PillCounter
//
//  Created by HC on 06/11/25.
//

import SwiftUI

struct UserHistoryView: View {

    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors

    // Default to today, but we handle the "Initial Load" separately
    @State private var startDate: Date? = Date()
    @State private var endDate: Date? = nil
    
    @State private var showDeleteConfirmation: Bool = false

    // Environment varibales
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var router: Router

    // MARK: - SEARCH STATE
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    
    @StateObject private var pdfService = PDFShareService.shared
    
    // MARK: - Filter State
    let filterType: HistoryFilterType
    @State private var activeTypeFilter: HistoryFilterType = .regular
    @State private var activeStatusFilter: HistoryStatusFilter = .all



    

    // MARK: MAIN VIEW
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 0.5,
                topContent: {
                    userHistoryContent()
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
                                // Logic to close search mode
                                withAnimation(.spring()) {
                                    isSearching = false
                                    searchText = ""
                                    isSearchFieldFocused = false
                                }
                            }
                        )
                        .transition(
                            .move(edge: .trailing).combined(with: .opacity))

                    } else {
                        // --- STANDARD MODE HEADER ---
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
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    PillCountingLoader()
                }
            }
        }
        .onAppear {
            activeTypeFilter = filterType
            fetchAll()
        }

        .onChange(of: startDate) { _, _ in fetchAll() }
        .onChange(of: endDate) { _, _ in fetchAll() }

        .onChange(of: activeTypeFilter) { _, _ in
            activeStatusFilter = .all
            searchText = ""
            fetchAll()
        }

        .onChange(of: activeStatusFilter) { _, _ in
            userViewModel.applyFilters(
                status: activeStatusFilter,
                search: searchText,
                pillScanViewModel: pillScanViewModel
            )
        }

        .onChange(of: searchText) { _, _ in
            userViewModel.applyFilters(
                status: activeStatusFilter,
                search: searchText,
                pillScanViewModel: pillScanViewModel
            )
        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            deleteConfirmationPopUp
        }
    }

    private func fetchAll() {
        guard let start = startDate else {
            userViewModel.filteredTransactionsOfUserByDate = []
            userViewModel.filteredBatchesOfUserByDate = []
            return
        }

        let end = endDate ?? start

        Task {
            await userViewModel.getTransactionsByDate(
                startDate: start,
                endDate: end,
                filter: activeTypeFilter
            )

            await userViewModel.getBatchesByDate(
                startDate: start,
                endDate: end
            )

            await MainActor.run {
                userViewModel.applyFilters(
                    status: activeStatusFilter,
                    search: searchText,
                    pillScanViewModel: pillScanViewModel
                )
            }
        }
    }
    // MARK: DELETE CONFIRMATION POPUP
    private var deleteConfirmationPopUp: some View {
        VStack {
            ConfirmationDialogue(
                title: "Confirm Delete",
                message:
                    "Are you sure you want to delete the records for the selected date? This action cannot be undone.",
                cancelButtonText: "NO",
                confirmButtonText: "YES"
            ) {
                showDeleteConfirmation = false
            } onConfirm: {
                Task {
                    guard let start = startDate else { return }
                    
                    await userViewModel.softDeleteTransactionsForSelectedDate(
                        startDate: start,
                        endDate: endDate ?? start,
                        filter: activeTypeFilter
                    )

                    showDeleteConfirmation = false
                }
            }


        }
        .frame(width: 275)
    }

    // MARK: TRANSACTION LIST
    private var userHistoryTransactionsList: some View {
        VStack (spacing:8){
                VStack(spacing: 15){
                    HStack{
                        txnTypeFileter
                        if !userViewModel.filteredTransactionsOfUserByDate.isEmpty {
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Image("delete")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        appColors.primary
                                    )
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
            

            // list of transactions.
            Spacer().frame(height: 15)

            ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading) {
                        if activeTypeFilter == .fixed {
                            if userViewModel.filteredTransactionsOfUserByDate.isEmpty {
                                ContentUnavailableView(
                                    "No History",
                                    systemImage: "clock.arrow.circlepath",
                                    description: Text(
                                        "No transactions found for this period.")
                                )
                                .padding(.top, 40)
                            }else if userViewModel.transactionRows.isEmpty {
                                // Search returned nothing
                                ContentUnavailableView(
                                    "No Results",
                                    systemImage: "magnifyingglass",
                                    description: Text("No transactions match your search.")
                                )
                                .padding(.top, 40)

                            }else{
                                ForEach(userViewModel.transactionRows) { row in
                                    DispenseItemRowView(data: row, appColors: appColors)
                                }
                            }
                        } else {
                            if userViewModel.filteredBatchesOfUserByDate.isEmpty {
                                ContentUnavailableView(
                                    "No History",
                                    systemImage: "clock.arrow.circlepath",
                                    description: Text(
                                        "No Batches found for this period.")
                                )
                                .padding(.top, 40)
                            }else if userViewModel.batchRows.isEmpty {
                                // Search returned nothing
                                ContentUnavailableView(
                                    "No Results",
                                    systemImage: "magnifyingglass",
                                    description: Text("No Batches match your search.")
                                )
                                .padding(.top, 40)
                                
                            }else{
                                ForEach(userViewModel.batchRows) { row in
                                    StockItemRowView(data: row, appColors: appColors)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)

            }
            .animation(nil, value: activeTypeFilter)
            .animation(nil, value: userViewModel.transactionRows.count)
            .animation(nil, value: userViewModel.batchRows.count)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
        .cornerRadius(24)
    }

    // MARK: CALENDAR
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
    
    private var statusFilterChips: some View {
        let counts = userViewModel.getStatusCounts(for: activeTypeFilter)
        return HStack(spacing: 8) {
              statusChip(label: "All", count: counts.all, status: .all)
              statusChip(label: "Completed", count: counts.completed, status: .completed)
              statusChip(label: "Pending", count: counts.pending, status: .pending)
              Spacer()
          }
    }
    
    private var txnTypeFileter: some View {
        let dispenseCount = userViewModel.filteredTransactionsOfUserByDate.count
        let stockCount = userViewModel.filteredBatchesOfUserByDate.count
        return HStack(spacing: 8) {

            txnTypeStatusChip(label: "Dispensed", count: dispenseCount, status: .fixed)
            txnTypeStatusChip(label: "Stock Count", count: stockCount, status: .regular)
            Spacer()
        }
    }

    @ViewBuilder
    private func statusChip(label: String, count: Int, status: HistoryStatusFilter) -> some View {
        let isActive = activeStatusFilter == status
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { activeStatusFilter = status }
        } label: {
            Text("\(label) (\(count))")
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundColor(appColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isActive ? appColors.primary: appColors.secondaryBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func txnTypeStatusChip(label: String, count: Int, status: HistoryFilterType) -> some View {
        let isActive = activeTypeFilter == status
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                print("Before:", activeTypeFilter)
                activeTypeFilter = status
                print("After:", activeTypeFilter)
            }
        } label: {
            Text("\(label) (\(count))")
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundColor(appColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isActive ? appColors.primary: appColors.secondaryBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subview for Cleaner Code
struct TransactionRow: View {
    let txn: PillCountTransactionEntity
    let appColors: AppColors
    let pillScanViewModel: PillScanViewModel

    var body: some View {
        HStack(spacing: 16) {

            // Image placeholder or Actual Image
            ThumbnailImageView(imagePath: txn.barcode_image, width: 80, height: 60)

            VStack(alignment: .leading, spacing: 4) {

                Text(txn.drug?.drug_name ?? "Unknown Pill")
                    .foregroundColor(appColors.text)
                    .font(.headline)
                    .lineLimit(2)

                Text(convertInt64ToDate(txn.created_at))
                    .foregroundColor(appColors.text.opacity(0.7))
                    .font(.subheadline)
            }

            Spacer()

            // Calculated Pill Count for this specific transaction
            // We need to sum the details for this row
//            let count =
//                (txn.pillCountTransactionDetails
//                as? Set<PillCountTransactionDetailsEntity>)?
//                .reduce(0) { $0 + Int($1.pill_count) } ?? 0

            
            let count = getTotalPillCount(for: txn)
            let targetCount = txn.target_count

            let notes = txn.note
         
            let isRegular = (txn.count_type == CountType.REGULAR.rawValue)

            let displayText = isRegular
                ? "\(count)"
                : "\(count) / \(targetCount)"

            

            HStack(spacing: 15) {
                if txn.status ==  CountStatus.PARTIAL.rawValue && targetCount != count {
                    Image("partial")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .overlay(
                            appColors.primary
                        )
                        .mask(
                            Image("partial")
                                .resizable()
                                .scaledToFit()
                        )
                } else if let notes, !notes.isEmpty {
                    Image("notes")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .overlay(appColors.primary)
                        .mask(
                            Image("notes")
                                .resizable()
                                .scaledToFit()
                        )
                }

                Text(displayText)
                    .foregroundColor(appColors.text)
                    .fontWeight(.bold)

            
            }
            .padding(.trailing)
        }
        .padding(.top, 10)
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .cornerRadius(12)
    }

    func loadImage(from fileName: String) -> UIImage? {
        let fileManager = FileManager.default
        guard
            let documentsUrl = fileManager.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else { return nil }
        let fileUrl = documentsUrl.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: fileUrl.path)
    }

    func convertInt64ToDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yyyy hh:mm a"
        return formatter.string(from: date)
    }
    
    private func getTotalPillCount(for transaction: PillCountTransactionEntity)
        -> Int
    {
        let detailsArray =
            (transaction.pillCountTransactionDetails?.allObjects
                as? [PillCountTransactionDetailsEntity]) ?? []
        return pillScanViewModel.getTotalPillCountOfCurrentTransactionByType(
            type:.targetVerification,
            details: detailsArray.filter { !$0.is_deleted }
        )
    }
}
