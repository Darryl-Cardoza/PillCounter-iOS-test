//
//  StockCountComponents.swift
//  PillCounter
//
//  Created by Bhushan Patil on 01/04/26.
//


import SwiftUI

struct StockTransactionListView: View {
    
    @Binding var transactions: [GroupedTransaction]
    @Binding var selectedIds: Set<String>
    @Binding var isEditing: Bool
    
    @EnvironmentObject private var appColors: AppColors
    @State private var expandedNdc: String? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(transactions.enumerated()), id: \.element.ndc) { index, txn in
                HStack(spacing: 12) {
                    
                    // CHECKBOX
                    if isEditing {
                        Image(
                            systemName: selectedIds.contains(txn.ndc)
                            ? "checkmark.square.fill"
                            : "square"
                        )
                        .foregroundColor(
                            selectedIds.contains(txn.ndc)
                            ? appColors.secondary : .gray
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {  
                                toggleSelection(txn.ndc)
                            }
                        }
                    }
                    
                    ControlledCollapsibleBox(
                        isExpanded: Binding(
                            get: { expandedNdc == txn.ndc },
                            set: { newValue in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedNdc = newValue ? txn.ndc : nil
                                    if newValue {
                                        selectedIds = [txn.ndc]
                                    } else {
                                        selectedIds.remove(txn.ndc)
                                    }
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
                            
                            // ── SEALED BOTTLES SECTION ──
                            let sealedDetails = txn.lotDetails.filter { $0.sealedQty > 0 }
                            let sealedTotal = sealedDetails.reduce(Int32(0)) { $0 + $1.sealedQty }
                            
                            HStack {
                                Text(L10n.StockCountSheet.sealedBottles)
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
                                LotColumnHeader()
                                ForEach(sealedDetails, id: \.lot) { detail in
                                    LotRow(lot: detail.lot, expiry: detail.expiry, qty: detail.sealedQty)
                                }
                                LotTotalRow(total: sealedTotal)
                            }
                            
                            // ── OPENED BOTTLES SECTION ──
                            let openDetails = txn.lotDetails.filter { $0.openQty > 0 }
                            let openTotal = openDetails.reduce(Int32(0)) { $0 + $1.openQty }
                            
                            HStack {
                                Text(L10n.StockCountSheet.openedBottles)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(appColors.text)
                                Spacer()
//                                Text("\(txn.openPills)")
//                                    .font(.system(size: 14, weight: .semibold))
//                                    .foregroundColor(appColors.text)
                            }
                            .padding(.top, 16)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 4)
                            
                            if !openDetails.isEmpty {
                                LotColumnHeader()
                                ForEach(openDetails, id: \.lot) { detail in
                                    LotRow(lot: detail.lot, expiry: detail.expiry, qty: detail.openQty)
                                }
                                LotTotalRow(total: openTotal)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
                .selectableEffect(
                    isSelected: selectedIds.contains(txn.ndc),
                    highlightColor: appColors.secondary
                )
            }
        }
        .padding(.horizontal)
    }
    
    // ✅ FIXED: Moved inside the struct so it can mutate @Binding
    private func toggleSelection(_ ndc: String) {
        if selectedIds.contains(ndc) {
            selectedIds.remove(ndc)
        } else {
            selectedIds.insert(ndc)
        }
    }
}

// MARK: - Lot Row
struct LotRow: View {
    let lot: String
    let expiry: String
    let qty: Int32
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.vertical,5)

            HStack {
                let isLotEmpty = lot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let isExpiryEmpty = expiry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if isLotEmpty && isExpiryEmpty {
                    Text("-")
                        .font(.system(size: 13))
                        .foregroundColor(appColors.text.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)

                } else {
                    Text(lot)
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
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Lot Column Header

struct LotColumnHeader: View {
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        HStack {
            Text(L10n.StockCountSheet.lotNumber)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(L10n.StockCountSheet.expiryDate)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .frame(width: 110, alignment: .leading)

            Text(L10n.StockCountSheet.pills)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(appColors.text)
                .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}

// MARK: - Lot Total Row

struct LotTotalRow: View {
    let total: Int32
    @EnvironmentObject private var appColors: AppColors

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.vertical, 5)

            HStack {
                Text(L10n.StockCountSheet.total)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(total)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.text)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - ControlledCollapsibleBox

struct ControlledCollapsibleBox<Header: View, Content: View>: View {

    @Binding var isExpanded: Bool
    let header: Header
    let content: Content

    @EnvironmentObject private var appColors: AppColors

    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self._isExpanded = isExpanded
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }

            if isExpanded {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .background(appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

    
