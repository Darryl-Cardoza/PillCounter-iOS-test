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
    
    @State private var showDeleteConfirmation: Bool = false
    @State private var expandedNdc: String? = nil

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
                                // PDF export placeholder
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
                    
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: "BATCH ID \(historyViewModel.selectedBatch?.batch_id ?? 0)",
                headerActionsBackground: appColors.primaryBackground,
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
            .customPopup(isPresented: $showDeleteConfirmation) {
                deleteConfirmationPopup
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
                    title: "No Transactions",
                    subtitle: "No items found in this batch"
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
        .padding(.top, isLandscape ? SafeAreaInsets.top + 40 : 90)
        .padding(.horizontal,16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }

    // MARK: - Batch Summary Header
    private var batchSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {

            // MARK: Top Row
            HStack {
                Text("TOTAL NDC COUNT")
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
                    Text("Completed on")
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
                HStack(spacing: 12) {
            
                    ControlledCollapsibleBox(
                        isExpanded: Binding(
                            get: { expandedNdc == txn.ndc },
                            set: { expandedNdc = $0 ? txn.ndc : nil }
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
                            HStack {
                                Text("Sealed Bottles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(appColors.text)
                                Spacer()
                                Text("\(txn.sealedBottles)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(appColors.text)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)

                            ForEach(txn.lotDetails.filter { $0.sealedQty > 0 }, id: \.lot) { detail in
                                HistoryLotRow(
                                    lot: detail.lot,
                                    expiry: detail.expiry,
                                    qty: detail.sealedQty,
                                    appColors: appColors
                                )
                            }

                            // Opened Bottles Section
                            HStack {
                                Text("Opened Bottles")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(appColors.text)
                                Spacer()
                                Text("\(txn.openPills)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(appColors.text)
                            }
                            .padding(.top, 8)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)

                            ForEach(txn.lotDetails.filter { $0.openQty > 0 }, id: \.lot) { detail in
                                HistoryLotRow(
                                    lot: detail.lot,
                                    expiry: detail.expiry,
                                    qty: detail.openQty,
                                    appColors: appColors
                                )
                            }
                        }
                        .padding(.bottom, 8)
                    }
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
            CollapsibleBox(title: NSLocalizedString("NOTE", comment: ""),bgColor: appColors.secondaryBackground) {
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
            title: NSLocalizedString("CONFIRM_DELETE", comment: ""),
            message: nil,
            cancelButtonText: "NO",
            confirmButtonText: "YES",
            onCancel: {
                showDeleteConfirmation = false
            },
            onConfirm: {
              
            }
        )
    }
}

// MARK: - Lot Row
private struct HistoryLotRow: View {
    let lot: String
    let expiry: String
    let qty: Int32
    let appColors: AppColors

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.vertical, 5)

            HStack {
                let isLotEmpty = lot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isExpiryEmpty = expiry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if isLotEmpty && isExpiryEmpty {
                    Text("-")
                        .font(.system(size: 13))
                        .foregroundColor(appColors.text.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Lot \(lot)")
                        .font(.system(size: 13))
                        .foregroundColor(appColors.text.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !isExpiryEmpty {
                        Text(expiry)
                            .font(.system(size: 13))
                            .foregroundColor(appColors.text.opacity(0.6))
                            .frame(width: 110, alignment: .leading)
                    }
                }

                Text("\(qty)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(appColors.text)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
    }
}
