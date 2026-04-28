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
    
    let filterType: HistoryFilterType

    private var displayedTransactions: [PillCountTransactionEntity] {

        guard !searchText.isEmpty else {
            return userViewModel.filteredTransactionsOfUserByDate
        }

        let lowercasedQuery = searchText.lowercased()

        return userViewModel.filteredTransactionsOfUserByDate.filter { txn in

            let drugName = txn.drug?.drug_name?.lowercased() ?? ""
            let note = txn.note?.lowercased() ?? ""
            let status = txn.status?.lowercased() ?? ""

            return drugName.contains(lowercasedQuery)
                || note.contains(lowercasedQuery)
                || status.contains(lowercasedQuery)
        }
    }

    

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
            fetchTransactions()
        }
        .onChange(of: startDate) { _, _ in
            fetchTransactions()
        }
        .onChange(of: endDate) { _, _ in
            fetchTransactions()
        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            deleteConfirmationPopUp
        }
    }
    
    private func fetchTransactions() {

        guard let start = startDate else {
            userViewModel.filteredTransactionsOfUserByDate = []
            return
        }

        Task {
            await userViewModel.getTransactionsByDate(
                startDate: start,
                endDate: endDate ?? start,
                filter: filterType
            )
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
                        filter: filterType
                    )

                    showDeleteConfirmation = false
                }
            }


        }
        .frame(width: 275)
    }

    // MARK: TRANSACTION LIST
    private var userHistoryTransactionsList: some View {
        VStack {

            if !userViewModel.filteredTransactionsOfUserByDate.isEmpty {
                HStack(spacing: 15) {
                    // MARK: DYNAMIC COUNTS
                    // Shows: "5 Txns • 120 Pills" or similar
                    Text(
                        "\(displayedTransactions.count) counts"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(appColors.text)

                    Spacer()

                    // icons
                    Button {
                        // something
                        if let vc = UIApplication.shared.topMostViewController(),
                           let start = startDate {

                            let exportStart = start
                            let exportEnd = endDate ?? start

                            let formattedDate = "\(Formatter.getDateString(from: Int64(exportStart.timeIntervalSince1970 * 1000))) - \(Formatter.getDateString(from: Int64(exportEnd.timeIntervalSince1970 * 1000)))"

                            PDFShareService.shared.generateAndShareUserHistoryPDF(
                                selectedDate: formattedDate,
                                transactions: userViewModel.filteredTransactionsOfUserByDate,
                                presentingVC: vc
                            )
                        }

                    } label: {
                        Image("pdf")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .overlay(
                                appColors.secondary
                            )
                            .mask(
                                Image("pdf")
                                    .resizable()
                                    .scaledToFit()
                            )
                    }.padding(.trailing,20)

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image("delete")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .overlay(
                                appColors.secondary
                            )
                            .mask(
                                Image("delete")
                                    .resizable()
                                    .scaledToFit()
                            )
                    }

                }
                .padding(.horizontal, isLandscape ? 40 : 5)
                .padding(.top, isLandscape ? SafeAreaInsets.top + 10 : 10)
            }

            // list of transactions.
            Spacer().frame(height: 10)

            ScrollView(showsIndicators: false) {
                if userViewModel.filteredTransactionsOfUserByDate.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(
                            "No transactions found for this period.")
                    )
                    .padding(.top, 40)
                }else if displayedTransactions.isEmpty {
                    
                    // Search returned nothing
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No transactions match your search.")
                    )
                    .padding(.top, 40)

                } else {
                    VStack(alignment: .leading) {
                        ForEach(
                            displayedTransactions,
                            id: \.txn_id
                        ) { txn in
                            TransactionRow(txn: txn, appColors: appColors,pillScanViewModel: pillScanViewModel)
                                .onTapGesture {
                                    Task {
                                        await pillScanViewModel
                                            .getCurrentTransaction(
                                                txnId: txn.txn_id)

                                        // making sure that current transaction of the pill scan view model for the tapped transaction.
                                        router.navigate(
                                            to: .authentication(
                                                .user(
                                                    .userSettings(
                                                        .HistoryTransactionDetail
                                                    ))))
                                    }
                                }

                            Divider()
                                .foregroundStyle(appColors.text)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }

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
