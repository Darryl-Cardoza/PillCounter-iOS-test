//
//  StockCountComponents.swift
//  PillCounter
//
//  Created by Bhushan Patil on 01/04/26.
//

import SwiftUI

struct StockTransaction: Identifiable, Hashable {
    let id: Int64
    let drugName: String
    let ndc: String
    let total: Int
    let stockBottles: Int?
    let openPills: Int?
}

struct StockTransactionListView: View {

    // binding variables -- for the transactions
    @Binding var transactions: [StockTransaction]
    @Binding var selectedIds: Set<Int64>
    @Binding var isEditing: Bool

    @EnvironmentObject private var appColors: AppColors

    // Only ONE open at a time
    @State private var expandedId: Int64? = nil

    var body: some View {
        VStack(spacing: 12) {

            ForEach(transactions) { txn in

                HStack(spacing: 12) {

                    // CHECKBOX
                    if isEditing {
                        Image(
                            systemName: selectedIds.contains(txn.id)
                                ? "checkmark.square.fill"
                                : "square"
                        )
                        .foregroundColor(
                            selectedIds.contains(txn.id)
                                ? appColors.secondary : .gray
                        )
                        .onTapGesture {
                            toggleSelection(txn.id)
                        }
                    }

                    ControlledCollapsibleBox(
                        isExpanded: Binding(
                            get: { expandedId == txn.id },
                            set: { expandedId = $0 ? txn.id : nil }
                        )
                    ) {

                        // HEADER
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(txn.drugName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(appColors.text)

                                Text(txn.ndc)
                                    .font(.system(size: 12))
                                    .foregroundColor(
                                        appColors.text.opacity(0.7)
                                    )
                            }

                            Spacer()

                            Text("\(txn.total)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(appColors.secondary)
                        }

                    }
                    content: {

                        VStack(spacing: 12) {
                            HStack {
                                Text("Stock Bottles")
                                    .font(.system(size: 14, weight: .regular))
                                Spacer()
                                Text("\(txn.stockBottles ?? 0) pills")
                                    .font(.system(size: 14, weight: .regular))
                            }
                            
                            Divider()

                            HStack {
                                Text("Open Pills")
                                    .font(.system(size: 14, weight: .regular))
                                Spacer()
                                Text("\(txn.openPills ?? 0) pills")
                                    .font(.system(size: 14, weight: .regular))
                            }
                        }
                        .padding(.horizontal,8)
                        .foregroundColor(appColors.text)
                    }
                }
            }

        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func transactionHeader(_ txn: StockTransaction) -> some View {
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
        .padding()
    }


    private func toggleExpansion(_ id: Int64) {
        if expandedId == id {
            expandedId = nil
        } else {
            expandedId = id
        }
    }
    private func toggleSelection(_ id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
}

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

            // HEADER
            header
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                }

            // EXPANDED CONTENT
            if isExpanded {
                VStack(spacing: 18) {
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
