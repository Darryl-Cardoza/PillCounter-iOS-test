//
//  StockCountBatchDetail.swift
//  PillCounter
//
//  Created by Bhushan Patil on 31/03/26.
//

import SwiftUI

struct StockCountBatchDetail: View {

    // environment properties
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @Environment(\.isLandscape) private var isLandscape

    // delete state
    @State private var isEditing: Bool = false
    @State private var selectedTxnIds: Set<Int64> = []

    // end batch
    @State private var showEndBatchPopUp: Bool = false
    @State private var showExportPopUp: Bool = false

    // transactions that are in the batch
    @State private var transactions: [StockTransaction] = [
        StockTransaction(
            id: 1,
            drugName: "Levothyroxine 50mg",
            ndc: "423",
            total: 8500,
            stockBottles: 1500,
            openPills: 500
        ),
        StockTransaction(
            id: 2,
            drugName: "Levothyroxine 50mg",
            ndc: "423",
            total: 8500,
            stockBottles: nil,
            openPills: nil
        ),
        StockTransaction(
            id: 3,
            drugName: "Levothyroxine 50mg",
            ndc: "423",
            total: 8500,
            stockBottles: nil,
            openPills: nil
        ),
    ]

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1,
                topContent: {
                    mainContent
                },
                bottomContent: {
                    EmptyView()
                },
                headerActions: {
                    
                    if isEditing {

                        // EDIT MODE
                        HStack {

                            // Select All
                            Button {
                                toggleSelectAll()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(
                                        systemName: areAllSelected
                                            ? "checkmark.square.fill" : "square"
                                    )
                                    .foregroundColor(
                                        areAllSelected
                                            ? appColors.secondary : .gray
                                    )

                                    Text(
                                        areAllSelected
                                            ? "Deselect All" : "Select All"
                                    )
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(appColors.text)
                                }
                            }

                            Spacer()

                            // Delete + Cancel
                            HStack(spacing: 16) {

                                // DELETE
                                Button {
                                    deleteSelectedTransactions()
                                } label: {
                                    Text("Delete")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(
                                            selectedTxnIds.isEmpty
                                                ? .gray : appColors.secondary
                                        )
                                }
                                .disabled(selectedTxnIds.isEmpty)

                                // CANCEL
                                Button {
                                    withAnimation {
                                        isEditing = false
                                        selectedTxnIds.removeAll()
                                    }
                                } label: {
                                    Text("Cancel")
                                        .foregroundColor(appColors.text)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .background(appColors.primaryBackground)

                    } else {

                        // NORMAL MODE

                        HStack(spacing: 16) {

                            // PDF BUTTON (your existing one)
                            Button {
                                showExportPopUp.toggle()
                            } label: {
                                Image("pdf")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 26, height: 26)
                                    .overlay { appColors.primary }
                                    .mask(
                                        Image("pdf")
                                            .resizable()
                                            .scaledToFit()
                                    )
                            }

                            // TRASH → Enter edit mode
                            Button {
                                withAnimation {
                                    isEditing = true
                                    selectedTxnIds.removeAll()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appColors.primary)
                            }
                        }
                        .padding(.trailing)
                    }
                },
                showBackButton: !isEditing,
                showHamburgerMenu: false,
                title: isEditing ? "" : "BATCH ID 3445",
                headerActionsBackground: appColors.primaryBackground,
                onBack: {
                    router.setRoot(
                        to: .authentication(.login(.dashboard(.dashboardHome)))
                    )
                }
            )
            .customPopup(isPresented: $showEndBatchPopUp) {
                showEndBatchPopup
            }
            .customPopup(isPresented: $showExportPopUp) {
                showConfirmExportPopup
            }
        }
    }

    // MARK: VIEWS
    @ViewBuilder
    private var mainContent: some View {

        VStack(spacing: 0) {

            // SCROLLABLE CONTENT
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {

                    StockTransactionListView(
                        transactions: $transactions,
                        selectedIds: $selectedTxnIds,
                        isEditing: $isEditing
                    )

                }
                .padding(isLandscape ? 20 : 0)
                .padding(.bottom, 20)
            }

            // FIXED BUTTONS (ALWAYS BOTTOM)
            EqualWidthHStackButtons(spacing: 16) {

                PillCountingButton(
                    title: "END BATCH",
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        showEndBatchPopUp.toggle()
                    }
                )

                PillCountingButton(
                    title: "ADD",
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        // TODO
                    }
                )
            }
            .padding()
        }
        .padding(.top, isLandscape ? SafeAreaInsets.top + 40 : 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }


    // MARK: HELPERS
    private var areAllSelected: Bool {
        // replace with your actual data source
        let allIds: Set<Int64> = [1, 2, 3, 4]
        return !allIds.isEmpty && selectedTxnIds == allIds
    }

    private func toggleSelectAll() {
        let allIds: Set<Int64> = [1, 2, 3, 4]  // replace with real txn IDs

        if selectedTxnIds == allIds {
            selectedTxnIds.removeAll()
        } else {
            selectedTxnIds = allIds
        }
    }

    private func deleteSelectedTransactions() {
        // TODO: Replace with API call
        // viewmodel.deleteTransactions(selectedTxnIds)

        withAnimation(.easeInOut(duration: 0.30)) {
            transactions.removeAll { txn in
                selectedTxnIds.contains(txn.id)
            }
        }

        selectedTxnIds.removeAll()
        isEditing = false
    }
}


// MARK: POPUPS
extension StockCountBatchDetail{
    
    private var showEndBatchPopup: some View {
        ConfirmationDialogue(
            title: NSLocalizedString("CONFIRM_END_BATCH", comment: ""),
            message: nil,
            cancelButtonText: "NO",
            confirmButtonText: "YES",
            onCancel: {
                showEndBatchPopUp = false
            },
            onConfirm: {
                showEndBatchPopUp = false
            }
        )
    }
    
    private var showConfirmExportPopup: some View {
        ConfirmationDialogue(
            title: NSLocalizedString("CONFIRM_EXPORT", comment: ""),
            message: nil,
            cancelButtonText: "NO",
            confirmButtonText: "YES",
            onCancel: {
                showExportPopUp = false
            },
            onConfirm: {
                showExportPopUp = false
            }
        )
    }
}
