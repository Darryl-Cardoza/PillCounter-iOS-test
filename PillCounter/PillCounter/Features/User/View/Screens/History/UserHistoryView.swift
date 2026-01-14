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
    @State private var selectedDate: Date = Date()
    @State private var showDeleteConfirmation: Bool = false

    // Environment varibales
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
    @EnvironmentObject private var router: Router

    @StateObject private var pdfService = PDFShareService.shared

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
                showBackButton: true,
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
            Task {
                // 1. On App Launch/View Appear, load the "1 Week/1 Month" range default
                await userViewModel.getTransactionsByDate(
                    selectedDate: selectedDate)

                // Allow a small delay before enabling the calendar listener to avoid instant override
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            }
        }
        .onChange(of: selectedDate) { oldValue, newValue in
            // Only fetch specific date if the user actually interacts with calendar
            // and we aren't in the initialization phase
            Task {
                // Otherwise, load specific single-day data
                await userViewModel.getTransactionsByDate(
                    selectedDate: newValue)
            }

        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            deleteConfirmationPopUp
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
                // delete all the transactions for that date.
                Task {
                    await userViewModel.softDeleteTransactionsForSelectedDate(
                        selectedDate: selectedDate
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
                        "\(userViewModel.historyTotalTransactionsCount) counts"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(appColors.text)

                    Spacer()

                    // icons
                    Button {
                        // something
                        if let vc = UIApplication.shared.topMostViewController()
                        {
                            PDFShareService.shared
                                .generateAndShareUserHistoryPDF(
                                    selectedDate: Formatter.getDateString(
                                        from: Int64(
                                            selectedDate.timeIntervalSince1970
                                                * 1000)),
                                    transactions: userViewModel
                                        .filteredTransactionsOfUserByDate,
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
                    }

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
                } else {
                    VStack(alignment: .leading) {
                        ForEach(
                            userViewModel.filteredTransactionsOfUserByDate,
                            id: \.txn_id
                        ) { txn in
                            TransactionRow(txn: txn, appColors: appColors)
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
            selectedDate: $selectedDate
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
            let count =
                (txn.pillCountTransactionDetails
                as? Set<PillCountTransactionDetailsEntity>)?
                .reduce(0) { $0 + Int($1.pill_count) } ?? 0

            let targetCount = txn.target_count

            let notes = txn.note

            HStack(spacing: 15) {
                if targetCount != count {
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

                Text("\(count)")
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
}
