    //
    //  StockCountPartialBatchList.swift
    //  PillCounter
    //
    //  Created by Bhushan Patil on 01/04/26.
    //

    import SwiftUI

    struct StockCountPartialBatchListScreen: View {

        @Environment(\.isLandscape) private var isLandscape
        @EnvironmentObject private var appColors: AppColors
        @EnvironmentObject private var router: Router
        @EnvironmentObject private var stockCountViewMoel: StockCountViewModel

        @State private var selectedBatchId: Int64?
        @State private var pendingAction: TransactionAction?
        @State private var selectedTransactionDetailOption: TransactionDetailOption = .resume
        @State private var batchCounts: [Int64: Int] = [:]
        @State private var batches: [BatchCountEntity] = []
        @State private var resetList: Bool = false
        
        //Added For Animation
        @State private var appearedIds: Set<Int64> = []
        @State private var listReady: Bool = false
        @State private var deletingIds: Set<Int64> = []
        


        var body: some View {
            GenericListScreen<BatchCountEntity, TransactionDetailOption>(
                items: batches,
                title: L10n.StockCountBatchList.pendingBatches,
                resetTrigger: resetList,
                // ROW UI — selectedIds is Set<Int64> from GenericListScreen
                rowView: { batch, isEditing, selectedIds in
                    AnyView(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(deletingIds.contains(batch.batch_id) ? 0.12 : 0))
                                .animation(.easeIn(duration: 0.15), value: deletingIds.contains(batch.batch_id))

                            StockItemRowView(
                                data: batch.toStockData(ndcCount: batchCounts[batch.batch_id] ?? 0)
                            )
                            .listRowAnimated(
                                id: batch.batch_id,
                                index: batches.firstIndex(where: { $0.batch_id == batch.batch_id }) ?? 0,
                                isEditing: isEditing,
                                isSelected: selectedIds.contains(batch.batch_id),
                                isDeleting: deletingIds.contains(batch.batch_id),
                                highlightColor: appColors.secondary
                            )
                        }
                        .collapsible(isVisible: !deletingIds.contains(batch.batch_id))
                        .selectableEffect(
                            isSelected: selectedIds.contains(batch.batch_id),
                            highlightColor: appColors.secondary
                        )
                        .animation(
                            .spring(response: 0.38, dampingFraction: 0.82),
                            value: deletingIds.contains(batch.batch_id)
                        )
                        .onAppear {
                            guard !appearedIds.contains(batch.batch_id) else { return }
                            let index = batches.firstIndex(where: {
                                $0.batch_id == batch.batch_id
                            }) ?? 0
                            withAnimation(
                                .spring(response: 0.42, dampingFraction: 0.78)
                                .delay(Double(index) * 0.07)
                            ) {
                                appearedIds.insert(batch.batch_id)
                            }
                        }
                    )
                },

                // SEARCH
                searchMatcher: { batch, query in
                    String(batch.batch_id).localizedCaseInsensitiveContains(query) ||
                    String(batch.bucket_id ?? "").localizedCaseInsensitiveContains(query)
                },

                // ROW TAP
                onRowTap: { batch in
                    guard let freshBatch = stockCountViewMoel.batchDAO
                        .fetchById(batch.batch_id) else {
                        return
                    }
                    selectedBatchId = freshBatch.batch_id
                    stockCountViewMoel.currentBatch = freshBatch
//                    router.navigate(
//                        to: .authentication(
//                            .login(
//                                .dashboard(
//                                    .pillCount(.stockCount(.stockCountBatchDetail))
//                                )
//                            )
//                        )
//                    )
                },

                // MENU LONG PRESS
                onMenuTap: { batch in
                    selectedBatchId = batch.batch_id
                },

                //DELETE — receives Set<Int64> directly, no mapping needed
                onDelete: { ids in
                    pendingAction = .multiDelete(ids)
                },

                //MENU ACTIONS
                onSelectOption: { option, _ in
                    handleMenuAction(option)
                },

                menuOptions: TransactionDetailOption.allCases,
                optionLabel: { $0.rawValue },
                filterView: nil
            )
            .onAppear {
                reloadBatches()
            }
            .onReceive(stockCountViewMoel.batchDAO.transactionsDidChange
                .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            ) { _ in
                reloadBatches()
            }
            .customPopup(
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                )
            ) {
                if pendingAction != nil {
                    commonConfirmationDialog
                }
            }
        
        }

        // MARK: - Batch Row
        private func batchRow(
            _ batch: BatchCountEntity,
            isEditing: Bool,
            selectedIds: Set<Int64>
        ) -> some View {
            let count = batchCounts[batch.batch_id] ?? 0
            
            return HStack(spacing: 16) {

                if isEditing {
                    PillCounterCheckbox(
                        isChecked: Binding(
                            get: { selectedIds.contains(batch.batch_id) },
                            set: { _ in }
                        ),
                        size: 20,
                        tintColor: appColors.primary
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ThumbnailImageView(
                    imagePath: "",
                    width: 80,
                    height: 64,
                    placeholderImageName: batch.req_id_from_pms != nil ? "new_rx" : "batch_icon",
                    isFromPms: false,
                    showImageBackground: appColors.primaryBackground
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        L10n.StockCountBatchList.batchPrefix(
                            String(batch.batch_id)
                        )
                    )
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(appColors.text)

                    HStack(spacing: 10) {
                        Text(DateUtils.formatToDayMonthYearTime(batch.start_date_time))
                            .font(.system(size: 12))
                            .foregroundColor(appColors.text.opacity(0.7))

                        if batch.bucket_id != "NORMAL" {
                            Text(batch.bucket_id ?? "")
                                .font(.system(size: 12))
                                .foregroundColor(appColors.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: 16))
                    .foregroundColor(appColors.secondary)
                    .padding(.trailing, 10)
            }
            .padding(12)
            .background(appColors.secondaryBackground)
            .cornerRadius(10)
        }

        // MARK: - Reload
        private func reloadBatches() {
            batches = stockCountViewMoel.loadBatches()
            batchCounts = Dictionary(
                uniqueKeysWithValues: batches.map { batch in
                    return (key: batch.batch_id,
                            value: stockCountViewMoel.batchDAO
                                .getTransactionCount(for: batch.batch_id))
                }
            )
        }
    }

    // MARK: - Menu Action Handler
    extension StockCountPartialBatchListScreen {
        fileprivate func handleMenuAction(_ option: TransactionDetailOption) {
            switch option {
            case .resume:
                break
            case .delete:
                if let id = selectedBatchId {
                    pendingAction = .delete(id)
                }
            case .forceComplete:
               return
            }
        }
    }

    // MARK: - Popups
    extension StockCountPartialBatchListScreen {

        private var commonConfirmationDialog: some View {
            ConfirmationDialogue(
                title: dialogTitle,
                message: dialogMessage,
                cancelButtonText: L10n.Common.cancel,
                confirmButtonText: confirmButtonTitle,
                onCancel: {
                    pendingAction = nil
                },
                onConfirm: {
                    handleConfirmedAction()
                }
            )
        }
        private func handleConfirmedAction() {
            guard let action = pendingAction else { return }
            pendingAction = nil

            switch action {
            case .delete(let id):
                deletingIds.insert(id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    stockCountViewMoel.batchDAO.softDelete(ids: [id])
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        batches.removeAll { $0.batch_id == id }
                    }
                    deletingIds.remove(id)
                    resetList.toggle()
                }


            case .multiDelete(let ids):
                deletingIds.formUnion(ids)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    stockCountViewMoel.batchDAO.softDelete(ids: ids)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        batches.removeAll { ids.contains($0.batch_id) }
                    }
                    deletingIds.subtract(ids)
                    resetList.toggle()
                }
            }
        }

        private var dialogTitle: String {
            switch pendingAction {
            case .delete:
                return L10n.StockCountBatchList.confirmDeleteTitle

            case .multiDelete:
                return L10n.StockCountBatchList.deleteSelectedTitle
            case .none:        return ""
            }
        }

        private var dialogMessage: String {
            switch pendingAction {
            case .delete:
                return L10n.StockCountBatchList.deleteBatchMessage

            case .multiDelete:
                return L10n.StockCountBatchList.deleteSelectedBatchesMessage
            case .none:        return ""
            }
        }

        private var confirmButtonTitle: String {
            switch pendingAction {
            case .delete, .multiDelete:
                return L10n.Common.delete
            case .none:                 return ""
            }
        }
    }
