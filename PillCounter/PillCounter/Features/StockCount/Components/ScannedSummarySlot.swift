//
//  ScannedSummarySlot.swift
//  PillCounter
//

import SwiftUI

struct ScannedSummarySlot: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let onEndCount: () -> Void
    var isIpadPortrait: Bool = false

    var body: some View {
        let totalNdc  = stockCountViewModel.groupedTransactions.count
        let totalPill = stockCountViewModel.groupedTransactions.reduce(0) { $0 + Int($1.total) }

        return VStack(spacing: 12) {

            // ── Header — mirrors ScannedDrugDetailsSlot header row ──
            Text("SCANNED DRUG DETAILS")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isIpadPortrait ? 12 : 14)

            // ── Scan placeholder ──
            VStack(spacing: 12) {
                Image("icon_scan_stock_bottle")
                    .renderingMode(.template)
                    .foregroundColor(appColors.secondary)

                Text("Scan a new Stock bottle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(appColors.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Summary footer ──
            VStack(spacing: 12) {
                Text("SCANNED SUMMARY")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total NDCs")
                            .font(.system(size: 13))
                            .foregroundColor(appColors.text.opacity(0.6))
                        Text("\(totalNdc)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(appColors.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Pills")
                            .font(.system(size: 13))
                            .foregroundColor(appColors.text.opacity(0.6))
                        Text("\(totalPill)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(appColors.secondary)
                    }
                    .padding(.leading, 24)

                    Spacer()

                    PillCountingButton(
                        iconName: nil, title: "END COUNT",
                        textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                        font: .system(size: 13, weight: .bold),
                        cornerRadius: 22, horizontalPadding: 18, verticalPadding: 13, iconSize: 0,
                        action: onEndCount
                    )
                    .fixedSize()
                }
            }
            .padding(.bottom,isIpadPortrait ? 14 : 14)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
        .modifier(BottomSheetStyle(enabled: !isIpadPortrait))
    }
}
