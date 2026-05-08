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
    
    @State private var exportedPDFURL: URL? = nil
    @State private var showShareSheet:  Bool = false
    @State private var showNoteOptions: Bool = false
    @State private var isGeneratingPDF: Bool = false
    
    @State private var noteError: String?

    private var allIds: Set<String> {
        Set(stockCountVieModel.groupedTransactions.map { $0.ndc })
    }
    
    private var isBatchEmpty: Bool {
        stockCountVieModel.groupedTransactions.isEmpty
    }

    private var totalPillCount: Int {
        stockCountVieModel.groupedTransactions.reduce(0) { $0 + Int($1.total) }
    }

    private var hasNoCount: Bool {
        isBatchEmpty || totalPillCount == 0
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
                    headerContent
                },
                showBackButton: !isEditing,
                showHamburgerMenu: false,
                title: isEditing ? "" :  String( "BATCH ID \(stockCountVieModel.currentBatch?.batch_id ?? 0)"),
                headerActionsBackground: appColors.primaryBackground,
                backgroundColor: appColors.primaryBackground,
                onBack: {
                    router.navigateBack()
                }
            )
            .onAppear {
                stockCountVieModel.getCountData()
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                if let url = exportedPDFURL {
                    try? FileManager.default.removeItem(at: url)
                    exportedPDFURL = nil
                }
            }) {
                if let url = exportedPDFURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .customPopup(isPresented: $showEndBatchPopUp) {
                showEndBatchPopup
            }
            .customPopup(isPresented: $showExportPopUp) {
                showConfirmExportPopup
            }
            .customPopup(isPresented: $showNoteOptions){
                showNoteOptionPopup
            }

            if isGeneratingPDF {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                PillCountingLoader()
            }
        }
    }
    
    // MARK: HEADER
    @ViewBuilder
    private var headerContent: some View{
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

                // PDF BUTTON
                Button {
                    let batch = stockCountVieModel.currentBatch
                    let txns  = stockCountVieModel.groupedTransactions
                    let note  = stockCountVieModel.note.isEmpty ? nil : stockCountVieModel.note
                    isGeneratingPDF = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        let url = StockCountPDFExporter.export(batch: batch, transactions: txns, note: note)
                        DispatchQueue.main.async {
                            isGeneratingPDF = false
                            if let url {
                                exportedPDFURL = url
                                showShareSheet = true
                            }
                        }
                    }
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
            }
            .padding(.trailing)
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
                    title: "END COUNT",
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 20,
                    iconSize: 0,
                    action: {
                        if stockCountVieModel.isNoteEnable {
                            showNoteOptions = true
                            stockCountVieModel.note = ""
                        } else {
                            showEndBatchPopUp = true
                        }
                    }
                )

                PillCountingButton(
                    title: "+ ADD",
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
            .padding(.bottom, 20)
        }
        .padding(.top, 65)
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
            message: hasNoCount
            ? "No transactions or counts added. Do you want to end the batch?"
            : nil,
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
                stockCountVieModel.note = ""
                router.setRoot(
                    to: .authentication(.login(.dashboard(.dashboardHome)))
                )
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
    
    private var showNoteOptionPopup: some View {
        NotePopupView(
            title: "Would you like to add a note?",
            showClose: true,
            text: $stockCountVieModel.note,
            errorMessage: noteError,
            primaryTitle: "YES",
            primaryAction: {
                if stockCountVieModel.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    noteError = "Please add a note"
                    return
                }

                noteError = nil
                showNoteOptions = false
                showEndBatchPopUp = true
            },
            secondaryTitle: "SKIP",
            secondaryAction: {
                noteError = nil
                showNoteOptions = false
                stockCountVieModel.note = ""
                showEndBatchPopUp = true
            },
            onClose: {
                noteError = nil
                showNoteOptions = false
                stockCountVieModel.note = ""
            }
        )
    }}

