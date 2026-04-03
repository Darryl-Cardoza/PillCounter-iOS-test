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
    @State private var selectedTransactionDetailOption:
        TransactionDetailOption = .resume

    // MARK: - DUMMY DATA (Replace later)

    struct Batch: Identifiable {
        let id: Int64
        let name: String
        let date: String
        let total: String
    }

    @State private var batches: [Batch] = []

    // MARK: - FILTER

    enum BatchFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case paused = "Paused"

        var id: String { rawValue }
    }

    // MARK: - BODY

    var body: some View {
        
        GenericListScreen<Batch, TransactionDetailOption>(
            items: batches,
            title: "PARTIAL COUNTS",
            
            // 🔹 ROW UI
            rowView: { batch, isEditing, selectedIds in
                AnyView(
                    batchRow(
                        batch,
                        isEditing: isEditing,
                        selectedIds: selectedIds
                    )
                )
            },
            
            // 🔹 SEARCH
            searchMatcher: { batch, query in
                batch.name.localizedCaseInsensitiveContains(query)
                || batch.total.localizedCaseInsensitiveContains(query)
            },
            
            // 🔹 ROW TAP
            onRowTap: { batch in
                selectedBatchId = batch.id
                stockCountViewMoel.currentBatchId = batch.id
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
            
            // 🔹 MENU TAP (IMPORTANT)
            onMenuTap: { batch in
                selectedBatchId = batch.id
            },
            
            // 🔹 DELETE (MULTI)
            onDelete: { ids in
                pendingAction = .multiDelete(ids)
            },
            
            // 🔹 MENU ACTIONS
            onSelectOption: { option, item in
                handleMenuAction(option)
            },
            
            menuOptions: TransactionDetailOption.allCases,
            optionLabel: { $0.rawValue }
        )
        .onAppear {
            batches = stockCountViewMoel.loadBatches()
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
    
    private func batchRow(
        _ batch: Batch,
        isEditing: Bool,
        selectedIds: Set<Int64>
    ) -> some View {

        HStack(spacing: 16) {

            if isEditing {
                PillCounterCheckbox(
                    isChecked: Binding(
                        get: { selectedIds.contains(batch.id) },
                        set: { _ in } // handled by GenericListScreen
                    ),
                    size: 20,
                    tintColor: appColors.primary
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ThumbnailImageView(
                imagePath: "",
                placeholderImageName: "batch_icon",
                isFromPms: false,
                showImageBackground: appColors.primaryBackground
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(batch.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appColors.text)

                Text(batch.date)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text.opacity(0.7))
            }

            Spacer()

            Text(batch.total)
                .font(.system(size: 16))
                .foregroundColor(appColors.secondary)

            if !isEditing {
                Button {
                    selectedBatchId = batch.id
                    showMenuOptions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .foregroundColor(appColors.primary)
                }
            }
        }
        .padding(12)
        .background(appColors.secondaryBackground)
        .cornerRadius(10)
    }

  
}

extension StockCountPartialBatchListScreen {

    fileprivate func handleMenuAction(_ option: TransactionDetailOption) {
        switch option {
        case .resume:
            // TODO: Resume batch
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



// MARK: POPUP
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
                            pendingAction = .delete(id)
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
            // TODO: Delete single batch API
            print("Delete batch \(id)")
            
        case .forceComplete(let id):
            // TODO: Force complete batch API
            print("Force complete \(id)")
            
        case .multiDelete(let ids):
            // TODO: Delete multiple batches API
            
            withAnimation {
                batches.removeAll { ids.contains($0.id) }
            }
        }
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .delete:
            return "Confirm Delete"
        case .forceComplete:
            return "Force Complete"
        case .multiDelete:
            return "Delete Selected"
        case .none:
            return ""
        }
    }

    private var dialogMessage: String {
        switch pendingAction {
        case .delete:
            return "Are you sure you want to delete this batch?"
        case .forceComplete:
            return "Are you sure you want to force complete this batch?"
        case .multiDelete:
            return "Are you sure you want to delete selected batches?"
        case .none:
            return ""
        }
    }

    private var confirmButtonTitle: String {
        switch pendingAction {
        case .delete, .multiDelete:
            return "DELETE"
        case .forceComplete:
            return "CONFIRM"
        case .none:
            return ""
        }
    }
}
