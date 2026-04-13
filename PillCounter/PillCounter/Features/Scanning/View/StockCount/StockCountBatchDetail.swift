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
    @EnvironmentObject private var stockCountVieModel: StockCountViewModel

    // delete state
    @State private var isEditing: Bool = false
    @State private var selectedTxnIds: Set<String> = []
    // end batch
    @State private var showEndBatchPopUp: Bool = false
    @State private var showExportPopUp: Bool = false

    private var allIds: Set<String> {
        Set(stockCountVieModel.groupedTransactions.map { $0.ndc })
    }


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
                title: isEditing ? "" :  String( "BATCH ID \(stockCountVieModel.currentBatch?.batch_id ?? 0)"),
                headerActionsBackground: appColors.primaryBackground,
                onBack: {
                    router.navigateBack()
                }
            )
            .onAppear(){
                stockCountVieModel.loadTransactions()
            }
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
            if stockCountVieModel.groupedTransactions.isEmpty {
                EmptyStateView(
                    imageName: "fixed_count",
                    systemImageName: nil,
                    title: "No Transactions Yet",
                    subtitle: "Start adding items to this batch"
                )
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        StockTransactionListView(
                            transactions: $stockCountVieModel.groupedTransactions,
                            selectedIds: $selectedTxnIds,
                            isEditing: $isEditing
                        )

                    }
                    .padding(isLandscape ? 20 : 0)
                    .padding(.bottom, 20)
                }
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
                        router.navigate(
                            to: .authentication(
                                .login(
                                    .dashboard(
                                        .pillCount(.barcodeScanning(.stockCount))
                                    )
                                )
                            )
                        )
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
        !allIds.isEmpty && selectedTxnIds == allIds
    }

    private func toggleSelectAll() {
        if selectedTxnIds == allIds {
            selectedTxnIds.removeAll()
        } else {
            selectedTxnIds = allIds
        }
    }

    private func deleteSelectedTransactions() {
        withAnimation(.easeInOut(duration: 0.30)) {
           
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
                if let batchId = stockCountVieModel.currentBatch?.batch_id {
                    stockCountVieModel.completeBatch(batchId: batchId)
                }
                router.setRoot(to: .authentication(.login(.dashboard(.dashboardHome))))
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
