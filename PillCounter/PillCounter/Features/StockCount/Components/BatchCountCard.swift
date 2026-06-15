//
//  BatchCountCard.swift
//  PillCounter
//

import SwiftUI

struct BatchCountCard: View {

    @EnvironmentObject private var appColors: AppColors
    let txn: GroupedTransaction
    var isSelected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(txn.drugName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)
                Text(txn.ndc)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text.opacity(0.48))
            }

            Spacer(minLength: 12)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .center, spacing: 2) {
                    Text("\(txn.total)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(appColors.secondary)
                        .monospacedDigit()
                    Text(L10n.StockCountSheet.pills)
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.4))
                }
                .frame(width: 64)

                VStack(alignment: .center, spacing: 2) {
                    Text("\(txn.sealedBottleQty)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(appColors.secondary)
                        .monospacedDigit()
                    Text(L10n.StockCountSheet.bottles)
                        .font(.system(size: 11))
                        .foregroundColor(appColors.text.opacity(0.4))
                }
                .frame(width: 64)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 2)
        .selectableEffect(isSelected: isSelected, highlightColor: appColors.secondary)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onTap?() }
    }
}
