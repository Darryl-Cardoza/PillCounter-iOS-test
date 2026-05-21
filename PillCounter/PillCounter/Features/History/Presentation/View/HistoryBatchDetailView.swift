//
//  HistoryBatchDetailView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//

import SwiftUI

struct HistoryBatchDetailView: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var historyViewModel: HistoryViewModel
    @EnvironmentObject private var userViewModel: UserViewModel
    
    @State private var showDeleteConfirmation: Bool = false
    @State private var expandedNdc: String? = nil
    @State private var exportedPDFURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var isGeneratingPDF: Bool = false

    private var allNdcs: Set<String> {
        Set(historyViewModel.groupedTransactionsForBatch.map { $0.ndc })
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
                    HStack(spacing: 16) {
                        Button {
                            let batch    = historyViewModel.selectedBatch
                            let txns     = historyViewModel.groupedTransactionsForBatch
                            let note     = batch?.note
                            let fname    = userViewModel.firstName
                            let lname    = userViewModel.lastName
                            let userName = [fname, lname].filter { !$0.isEmpty }.joined(separator: " ")
                            isGeneratingPDF = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                let url = StockCountPDFExporter.export(
                                   batch: batch,
                                   transactions: txns,
                                   note: note,
                                   userName: userName.isEmpty ? nil : userName
                               )
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
                        
                        Button {
                           showDeleteConfirmation = true
                       } label: {
                           Image("delete")
                               .resizable()
                               .scaledToFit()
                               .frame(width: 26, height: 26)
                               .overlay { appColors.primary }
                               .mask(
                                   Image("delete")
                                       .resizable()
                                       .scaledToFit()
                               )
                       }
                    }
                    .padding(.trailing)
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: String(format: L10n.History.batchIdTitle, historyViewModel.selectedBatch?.batch_id ?? 0),
                headerActionsBackground: appColors.primaryBackground,
                backgroundColor: appColors.primaryBackground,
                onBack: {
                    router.navigateBack()
                }
            )
            .onAppear {
                if let batchId = historyViewModel.selectedBatchId {
                    historyViewModel.prepareBatchDetails(for: batchId)
                }
            }
            .onDisappear {
                historyViewModel.clearBatchDetail()
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
            .customPopup(isPresented: $showDeleteConfirmation) {
                deleteConfirmationPopup
            }

            if isGeneratingPDF {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                PillCountingLoader()
            }
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 10) {
            batchSummaryHeader
            notesSection

            if historyViewModel.groupedTransactionsForBatch.isEmpty {
                EmptyStateView(
                    imageName: "fixed_count",
                    systemImageName: nil,
                    title: L10n.History.noTransactions,
                    subtitle: L10n.History.noItemsInBatch
                )
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ndcTransactionList
                    }
                    .padding(.horizontal,0)
                    .padding(.bottom, 20)
                }
            }
        }
        .padding(.top, 45)
        .padding(.horizontal,16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }

    // MARK: - Batch Summary Header
    private var batchSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {

            // MARK: Top Row
            HStack {
                Text(L10n.History.totalNdcCount)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(appColors.text)

                Spacer()

                let ndcCount = historyViewModel.groupedTransactionsForBatch.count

                Text("\(ndcCount)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(appColors.secondary)
            }

            // MARK: Bottom Row
            if let batch = historyViewModel.selectedBatch {
                HStack {
                    Text(L10n.History.completedOn)
                        .font(.system(size: 13))
                        .foregroundColor(appColors.text)

                    Spacer()
                    Text(DateUtils.formatToUSDateTime(batch.end_date_time))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(appColors.text)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(appColors.primaryBackground)
        .padding(8)
    }


    // MARK: - NDC Transaction List
    @ViewBuilder
    private var ndcTransactionList: some View {
        VStack(spacing: 12) {
            ForEach(historyViewModel.groupedTransactionsForBatch, id: \.ndc) { txn in
                ControlledCollapsibleBox(
                    isExpanded: Binding(
                        get: { expandedNdc == txn.ndc },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                expandedNdc = newValue ? txn.ndc : nil
                            }
                        }
                    )
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(txn.drugName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(appColors.text)
                            Text(txn.ndc)
                                .font(.system(size: 12))
                                .foregroundColor(appColors.text.opacity(0.7))
                        }
                        Spacer()
                        Text("\(txn.total)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(appColors.secondary)
                    }
                } content: {
                    VStack(spacing: 0) {
                        // Sealed Bottles Section
                        let sealedDetails = txn.lotDetails.filter { $0.sealedQty > 0 }
                        let sealedTotal = sealedDetails.reduce(Int32(0)) { $0 + $1.sealedQty }

                        HStack {
                            Text(L10n.History.sealedBottles)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(appColors.text)
                            Spacer()
                            Text("\(txn.sealedBottleQty)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(appColors.text)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)

                        if !sealedDetails.isEmpty {
                            LotColumnHeader(appColors: appColors)
                            ForEach(sealedDetails, id: \.lot) { detail in
                                LotRow(lot: detail.lot, expiry: detail.expiry, qty: detail.sealedQty, appColors: appColors)
                            }
                            LotTotalRow(total: sealedTotal, appColors: appColors)
                        }

                        // Opened Bottles Section
                        let openDetails = txn.lotDetails.filter { $0.openQty > 0 }
                        let openTotal = openDetails.reduce(Int32(0)) { $0 + $1.openQty }

                        HStack {
                            Text(L10n.History.openedBottles)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(appColors.text)
                            Spacer()
                        }
                        .padding(.top, 16)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)

                        if !openDetails.isEmpty {
                            LotColumnHeader(appColors: appColors)
                            ForEach(openDetails, id: \.lot) { detail in
                                LotRow(lot: detail.lot, expiry: detail.expiry, qty: detail.openQty, appColors: appColors)
                            }
                            LotTotalRow(total: openTotal, appColors: appColors)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 0)
    }

    // MARK: - Notes Section
    @ViewBuilder
    private var notesSection: some View {
        if let notes = historyViewModel.selectedBatch?.note,
           !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            CollapsibleBox(title: L10n.Common.note, bgColor: appColors.secondaryBackground) {
                Text(notes)
                    .font(.system(size: 14))
                    .foregroundStyle(appColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }


}

// MARK: - Popups
extension HistoryBatchDetailView {

    private var deleteConfirmationPopup: some View {
        ConfirmationDialogue(
            title: L10n.History.confirmDelete,
            message: nil,
            cancelButtonText: L10n.Common.no,
            confirmButtonText: L10n.Common.yes,
            onCancel: {
                showDeleteConfirmation = false
            },
            onConfirm: {
                showDeleteConfirmation = false
                  guard let batchId = historyViewModel.selectedBatch?.batch_id else { return }
                  Task {
                      await historyViewModel.softDeleteBatch(batchId: batchId)
                      router.navigateBack()
                  }
            }
        )
    }
}

