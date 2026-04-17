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
    @State private var showMenuOptions: Bool = false
    @State private var selectedTransactionDetailOption: TransactionDetailOption = .resume
    @State private var batchCounts: [Int64: Int] = [:]
    @State private var batches: [BatchCountEntity] = []
    @State private var resetList: Bool = false

    var body: some View {
        GenericListScreen<BatchCountEntity, TransactionDetailOption>(
            items: batches,
            title: "PARTIAL COUNTS",
            resetTrigger: resetList,
          
            
            // ROW UI — selectedIds is Set<Int64> from GenericListScreen
            rowView: { batch, isEditing, selectedIds in
                AnyView(
                    batchRow(batch, isEditing: isEditing, selectedIds: selectedIds)
                )
            },

            // SEARCH
            searchMatcher: { batch, query in
                String(batch.batch_id).localizedCaseInsensitiveContains(query) ||
                String(batch.bucket_id ?? "").localizedCaseInsensitiveContains(query)
            },

            // ROW TAP
            onRowTap: { batch in
                guard let freshBatch = stockCountViewMoel.pillDataLocalStorage
                    .fetchBatchById(batch.batch_id) else {
                    return
                }
                selectedBatchId = freshBatch.batch_id
                stockCountViewMoel.currentBatch = freshBatch
                router.navigate(
                    to: .authentication(
                        .login(
                            .dashboard(
                                .pillCount(.stockCount(.stockCountBatchDetail))
                            )
                        )
                    )
                )
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
            optionLabel: { $0.rawValue }
        )
        .onAppear {
            reloadBatches()
        }
        .onReceive(stockCountViewMoel.pillDataLocalStorage.transactionsDidChange
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
        .customPopup(isPresented: $showMenuOptions) {
            menuOptions
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
                placeholderImageName: batch.req_id_from_pms != nil ? "new_rx" : "batch_icon",
                isFromPms: false,
                showImageBackground: appColors.primaryBackground
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Batch \(String(batch.batch_id))")
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
        let loaded = stockCountViewMoel.loadBatches()
        batches = loaded
        batchCounts = Dictionary(
            uniqueKeysWithValues: loaded.map { batch in
                return (key: batch.batch_id,
                        value: stockCountViewMoel.pillDataLocalStorage
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
            if let id = selectedBatchId {
                pendingAction = .forceComplete(id)
            }
        }
    }
}

// MARK: - Popups
extension StockCountPartialBatchListScreen {

    private var menuOptions: some View {
        MenuOption(
            options: TransactionDetailOption.allCases,
            selectedOption: $selectedTransactionDetailOption,
            isPresented: $showMenuOptions,
            label: { $0.rawValue },
            onSelect: { option in
                switch option {
                case .resume:
                    if let batch = batches.first(where: { $0.batch_id == selectedBatchId }) {
                        stockCountViewMoel.currentBatch = batch
                    }
                    showMenuOptions = false
                    router.navigate(
                        to: .authentication(
                            .login(
                                .dashboard(
                                    .pillCount(.stockCount(.stockCountBatchDetail))
                                )
                            )
                        )
                    )
                case .delete:
                    if let id = selectedBatchId {
                        showMenuOptions = false
                        pendingAction = .delete(id)
                    }
                case .forceComplete:
                    if let id = selectedBatchId {
                        showMenuOptions = false
                        pendingAction = .forceComplete(id)
                    }
                }
            }
        )
    }

    private var commonConfirmationDialog: some View {
        ConfirmationDialogue(
            title: dialogTitle,
            message: dialogMessage,
            cancelButtonText: "CANCEL",
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
            stockCountViewMoel.pillDataLocalStorage.deleteBatches(ids: [id])
            resetList.toggle()
            reloadBatches()

        case .forceComplete(let id):
            print("Force complete \(id)")

        case .multiDelete(let ids):
            stockCountViewMoel.pillDataLocalStorage.deleteBatches(ids: ids)
            resetList.toggle()
            reloadBatches()
        }
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .delete:      return "Confirm Delete"
        case .forceComplete: return "Force Complete"
        case .multiDelete: return "Delete Selected"
        case .none:        return ""
        }
    }

    private var dialogMessage: String {
        switch pendingAction {
        case .delete:      return "Are you sure you want to delete this batch?"
        case .forceComplete: return "Are you sure you want to force complete this batch?"
        case .multiDelete: return "Are you sure you want to delete selected batches?"
        case .none:        return ""
        }
    }

    private var confirmButtonTitle: String {
        switch pendingAction {
        case .delete, .multiDelete: return "DELETE"
        case .forceComplete:        return "CONFIRM"
        case .none:                 return ""
        }
    }
}
