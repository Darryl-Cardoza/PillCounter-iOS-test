//
//  UnSyncedTxnView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 09/02/26.
//

import SwiftUI


struct UnsyncedTransactionView: View {

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    contentView
                },
                bottomContent: {
//                    syncButton
                },
                headerActions: {
                    EmptyView()
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: "UNSYNCED TRANSACTIONS"
            )

        }
        .onAppear {
            Task {
                await userViewModel.getUnsyncedTransactions()
            }
        }
    }
}



private extension UnsyncedTransactionView {

    var contentView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                if userViewModel.unsyncedTransactions.isEmpty {
                    emptyState
                        .padding(.top, 90)
                } else {
                    ForEach(userViewModel.unsyncedTransactions, id: \.txn_id) { txn in
                        listItem(
                            name: txn.drug?.drug_name ?? "N/A",
                            date:
                                "\(Formatter.getDateString(from: txn.created_at)) • " +
                                "\(Formatter.getTimeString(from: txn.created_at))",
                            count: "\(txn.target_count)",
                            barcodeImagePath: txn.barcode_image,
                            isFromPms: txn.is_from_pms
                        )
                    }
                    .padding(.top, 90)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(appColors.secondaryBackground)
        .safeAreaInset(edge: .bottom) {
            syncButton
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(
                    appColors.secondaryBackground
                        .ignoresSafeArea(edges: .bottom)
                )
        }
    }
}



private extension UnsyncedTransactionView {

    func listItem(
        name: String,
        date: String,
        count: String,
        barcodeImagePath: String?,
        isFromPms: Bool
    ) -> some View {

        HStack(spacing: 16) {

            ThumbnailImageView(
                imagePath: barcodeImagePath,
                isFromPms: isFromPms
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(date)
                        .font(.system(size: 12))
                        .foregroundColor(appColors.text.opacity(0.7))

                    if isFromPms {
                        Text("PMS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appColors.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(count)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(appColors.text)
        }
        .padding(10)
        .background(
            colorScheme == .dark
                ? Color.black.opacity(0.85)
                : Color.white
        )
        .cornerRadius(10)
    }
}


    private extension UnsyncedTransactionView {

        var syncButton: some View {
            ZStack {
                Button {
                    Task {
                        
                    }
                } label: {
                    Text("SYNC ALL")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 48)
                        .background(appColors.primary)
                        .cornerRadius(24)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, SafeAreaInsets.bottom + 10)
            .background(Color.clear)
        }
    }


private extension UnsyncedTransactionView {

    var emptyState: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No unsynced transactions")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("All transactions are successfully synced.")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            Spacer()
        }
        .background(appColors.secondaryBackground)
        .padding(.top,30)
    }
        
}

