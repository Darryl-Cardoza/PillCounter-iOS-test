//
//  StockCountRequestedList.swift
//  PillCounter
//
//  Created by Bhushan Patil on 02/04/26.
//
//
//  StockCountPartialBatchList.swift
//  PillCounter
//
//  Created by Bhushan Patil on 01/04/26.
//

import SwiftUI

struct StockCountRequestedList: View {

    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router

    // TODO: Replace with StockCountViewModel
    // @EnvironmentObject private var stockViewModel: StockCountViewModel

    @State private var selectedBatchId: Int64?

    @State private var pendingAction: TransactionAction?


    // MARK: - DUMMY DATA (Replace later)

    struct Batch: Identifiable {
        let id: Int64
        let name: String
        let date: String
        let total: String
    }

    @State private var batches: [Batch] = [
        Batch(
            id: 1,
            name: "NDC 23545-333-54",
            date: "01-02-2026 18:45 PM",
            total: "50 NDCs"
        ),
        Batch(
            id: 2,
            name: "NDC 23545-333-54",
            date: "01-02-2026 18:45 PM",
            total: "50 NDCs"
        ),
        Batch(
            id: 3,
            name: "NDC 23545-333-54",
            date: "01-02-2026 18:45 PM",
            total: "50 NDCs"
        ),
    ]

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
            title: "NDC REQUESTS",
            
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
                // TODO: Navigate to batch details
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
            },
            
            menuOptions: TransactionDetailOption.allCases,
            optionLabel: { $0.rawValue }
        )
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

            ThumbnailImageView(imagePath: "", placeholderImageName: "new_rx" ,placeholderBackgroundColor: appColors.secondary, isFromPms: false,  )

            VStack(alignment: .leading, spacing: 6) {
                Text(batch.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appColors.text)

                Text(batch.date)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text.opacity(0.7))
            }

            Spacer()
            
            Image(systemName: "partial")
                .foregroundColor(appColors.text)

            if !isEditing {
                Button {
                    selectedBatchId = batch.id
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

