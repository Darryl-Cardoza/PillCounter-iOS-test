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
                title: L10n.Unsync.screenTitle,
                backgroundColor: appColors.primaryBackground
            )
        }
    }
}

// MARK: - Main Content

private extension UnsyncedTransactionView {

    var contentView: some View {
        
        let isEmpty = viewModel.batches.isEmpty && viewModel.transactions.isEmpty

        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                if isEmpty {
                    VStack {
                        EmptyStateView(
                            imageName: "check_with_circle",
                            systemImageName: nil,
                            title: L10n.Unsync.allSynced,
                            subtitle: nil
                        )
                        .padding(.top, 120)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    LazyVStack(spacing: 20) {
                        batchesSection
                        transactionsSection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .padding(.top, 64)
        .background(appColors.primaryBackground)
        .safeAreaInset(edge: .bottom) {
            VStack (spacing: 5){
                if !isEmpty {
                    if  userViewModel.pmsConnectionState == .disconnected{
                        PillCountInstructionOverlay(text: L10n.Unsync.pmsNotConnected, backgroundOpacity: 1)
                    }
                    syncButtonArea
                        .padding(.bottom, 8)
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
                sectionHeader(title: L10n.Unsync.stocks, count: viewModel.totalUnsyncedBatchCount)

                ForEach(Array(viewModel.batches.enumerated()), id: \.offset) { index, batch in
                    StockItemRowView(
                        data: batch
                    )
                    .listRowAnimated(
                        id: Int64(index),
                        index: index,
                        isEditing: false,
                        isSelected: false,
                        isDeleting: false,
                        highlightColor: appColors.secondary
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
                sectionHeader(title: L10n.Unsync.dispenses, count: viewModel.totalUnsyncedTransactionCount)

                ForEach(Array(viewModel.transactions.enumerated()), id: \.offset) { index, txn in
                    DispenseItemRowView(
                        data: txn
                    )
                    .listRowAnimated(
                        id: Int64(index),
                        index: index,
                        isEditing: false,
                        isSelected: false,
                        isDeleting: false,
                        highlightColor: appColors.secondary
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
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(appColors.text.opacity(0.5))
                .kerning(1.2)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
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
//            if viewModel.batches.isEmpty {
//                Text(L10n.Unsync.pmsNotConnected)
//                    .font(.system(size: 12))
//                    .foregroundColor(                                 userViewModel.pmsConnectionState == .disconnected
//                                                                      ? Color.black : appColors.text
//                    )
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .background(appColors.secondaryBackground)
//            }

            Button {
                Task { await viewModel.syncAll() }
            } label: {
                ZStack {
                    if viewModel.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(L10n.Unsync.syncAll)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(
                                userViewModel.pmsConnectionState == .disconnected
                                ? appColors.text
                                    : .white
                            )
                    }
                }
                .frame(width: 140, height: 48)
                .background(
                    userViewModel.pmsConnectionState == .disconnected
                    ? appColors.secondaryBackground.opacity(0.5)
                    : appColors.primary
                )
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

