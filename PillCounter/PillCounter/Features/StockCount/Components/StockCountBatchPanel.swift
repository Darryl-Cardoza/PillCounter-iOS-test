//
//  StockCountBatchPanel.swift
//  PillCounter
//

import SwiftUI

struct StockCountBatchPanel<BottomContent: View>: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let topPadding: CGFloat
    let hideHeader: Bool
    let onScanPills: (() -> Void)?
    let bottomContent: () -> BottomContent

    init(topPadding: CGFloat = 0, hideHeader: Bool = false, onScanPills: (() -> Void)? = nil, @ViewBuilder bottomContent: @escaping () -> BottomContent) {
        self.topPadding = topPadding
        self.hideHeader = hideHeader
        self.onScanPills = onScanPills
        self.bottomContent = bottomContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if !hideHeader {
                HStack(spacing: 8) {
                    Text("Batch Stock Count")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(appColors.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    scanPillsButton
                }
                .padding(.horizontal, 20)
                .padding(.top, topPadding + 16)
                .padding(.bottom, 12)
            }

            HStack(spacing: 4) {
                Text(recentLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.4))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(appColors.primary)
            }
            .padding(.horizontal, 22)
            .padding(.top, hideHeader ? 16 : 0)
            .padding(.bottom, 8)

            if stockCountViewModel.groupedTransactions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(stockCountViewModel.groupedTransactions, id: \.ndc) { txn in
                            countRow(txn)
                        }
                    }
                }
            }

            bottomContent()
        }
        .background(appColors.primaryBackground)
    }

    // MARK: - Sub-views

    private var scanPillsButton: some View {
        PillCountingButton(
            iconName: nil, title: "SCAN PILLS",
            textColor: appColors.primary, backgroundColor: .clear,
            borderColor: appColors.primary,
            font: .system(size: 11, weight: .bold),
            cornerRadius: 20, horizontalPadding: 14, verticalPadding: 12, iconSize: 0,
            action: { onScanPills?() }
        )
        .fixedSize()
    }

    private var recentLabel: String {
        let n = stockCountViewModel.groupedTransactions.count
        return n > 0 ? "RECENT BATCH COUNT (\(n))" : "RECENT BATCH COUNT"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(appColors.text.opacity(0.2))
            Text("No items added yet")
                .font(.system(size: 13))
                .foregroundColor(appColors.text.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func countRow(_ txn: GroupedTransaction) -> some View {
        let isSelected = stockCountViewModel.selectedGroupedTransaction?.ndc == txn.ndc
        return VStack(spacing: 0) {
            BatchCountCard(txn: txn, isSelected: isSelected) {
                if isSelected {
                    stockCountViewModel.selectedGroupedTransaction = nil
                    stockCountViewModel.scannedDrugData = nil
                } else {
                    stockCountViewModel.selectTransaction(txn)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
