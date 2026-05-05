//
//  UnsyncedTransactionView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 27/04/26.
//

//
//  UnsyncedTransactionView.swift
//  PillCounter
//

import SwiftUI

struct UnsyncedTransactionView: View {

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appColors: AppColors

    @StateObject private var viewModel = UnsyncedViewModel()
    @EnvironmentObject private var userViewModel: UserViewModel

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    contentView
                },
                bottomContent: {
                    EmptyView()
                },
                headerActions: {
                    EmptyView()
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: "UNSYNCED TRANSACTIONS"
            )
        }
    }
}

// MARK: - Main Content

private extension UnsyncedTransactionView {

    var contentView: some View {
        let isEmpty = viewModel.batches.isEmpty && viewModel.transactions.isEmpty

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if isEmpty {
                    VStack {
                        Spacer()

                        EmptyStateView(
                            imageName: "check_with_circle",
                            systemImageName: nil,
                            title: "All transactions are synced",
                            subtitle: nil
                        )

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: UIScreen.main.bounds.height * 0.7)
                } else {
                    VStack(spacing: 16) {
                        batchesSection
                        transactionsSection
                    }
                    .padding(.top, 90)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100) // leave room for sync button
        }
        .background(appColors.primaryBackground)
        .safeAreaInset(edge: .bottom) {
            VStack (spacing: 5){
                if !isEmpty {
                    if  userViewModel.pmsConnectionState == .disconnected{
                        PillCountInstructionOverlay(text: "PMS not connected", backgroundOpacity: 1)
                    }
                    syncButtonArea
                }
            }
        }
    }
}

// MARK: - Batches Section

private extension UnsyncedTransactionView {

    @ViewBuilder
    var batchesSection: some View {
        if !viewModel.batches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title: "STOCK", count: viewModel.batches.count)

                ForEach(viewModel.batches, id: \.batchId) { batch in
                    StockItemRowView(
                        data: batch,
                        appColors: appColors
                    )
                }
            }
        }
    }
}

// MARK: - Transactions Section

private extension UnsyncedTransactionView {

    @ViewBuilder
    var transactionsSection: some View {
        if !viewModel.transactions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title: "DISPENSE", count: viewModel.transactions.count)

                ForEach(viewModel.transactions) { txn in
                    DispenseItemRowView(
                        data: txn,
                        appColors: appColors
                    )
                }
            }
        }
    }
}

// MARK: - Section Header

private extension UnsyncedTransactionView {

    func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(appColors.text.opacity(0.5))
                .kerning(1.2)

            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: 20, minHeight: 20)
                .background(appColors.primary)
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Sync Button

private extension UnsyncedTransactionView {

    var syncButtonArea: some View {
        VStack(spacing: 6) {
            // PMS status badge
            if viewModel.batches.isEmpty {
                Text("PMS not connected")
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appColors.secondaryBackground)
            }

            Button {
                Task { await viewModel.syncAll() }
            } label: {
                ZStack {
                    if viewModel.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("SYNC ALL")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 140, height: 48)
                .background(appColors.primary)
                .cornerRadius(24)
            }
            .disabled(viewModel.isSyncing)
            .opacity(viewModel.isSyncing ? 0.7 : 1.0)

            if let error = viewModel.syncError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            appColors.primaryBackground
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

