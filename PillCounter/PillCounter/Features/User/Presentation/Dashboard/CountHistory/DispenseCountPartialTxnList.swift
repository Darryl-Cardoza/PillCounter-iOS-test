//
//  DispenseCountPartialTxnList.swift
//  PillCounter
//

import SwiftUI

struct DispenseCountPartialTxnList: View {

    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var pillScanViewmodel: PillScanViewModel

    @State private var selectedTransasctionId: Int64?
    @State private var pendingAction: TransactionAction?
    @State private var pillCounts: [Int64: Int] = [:]
    @State private var transactions: [PillCountTransactionEntity] = []
    @State private var resetList: Bool = false
    @State private var activePmsFilter: PmsFilter = .all
    
    //Animation
    @State private var appearedIds: Set<Int64> = []
    @State private var deletingIds: Set<Int64> = []
    
    let title: String
    
    private var filteredTransactions: [PillCountTransactionEntity] {
        switch activePmsFilter {
        case .all:
            return transactions
        case .pms:
            return transactions.filter { $0.is_from_pms == true }
        case .nonPms:
            return transactions.filter { $0.is_from_pms == false }
        }
    }

    var body: some View {
        GenericListScreen<PillCountTransactionEntity, TransactionDetailOption>(
            items: filteredTransactions,
            title: title,
            resetTrigger: resetList,

            // MARK: - ROW UI
            rowView: { txn, isEditing, selectedIds in
                AnyView(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(deletingIds.contains(txn.txn_id) ? 0.12 : 0))
                            .animation(.easeIn(duration: 0.15), value: deletingIds.contains(txn.txn_id))

                        DispenseItemRowView(
                            data: txn.toRowData(pillCount: pillCounts[txn.txn_id] ?? 0),
                            appColors: appColors
                        )
                        .listRowAnimated(
                            id: txn.txn_id,
                            index: filteredTransactions.firstIndex(where: {
                                $0.txn_id == txn.txn_id
                            }) ?? 0,
                            isEditing: isEditing,
                            isSelected: selectedIds.contains(txn.txn_id),
                            isDeleting: deletingIds.contains(txn.txn_id),
                            highlightColor: appColors.secondary
                        )
                    }
                    .collapsible(isVisible: !deletingIds.contains(txn.txn_id))
                    .selectableEffect(
                        isSelected: selectedIds.contains(txn.txn_id),
                        highlightColor: appColors.secondary
                    )
                    .animation(
                        .spring(response: 0.38, dampingFraction: 0.82),
                        value: deletingIds.contains(txn.txn_id)
                    )
                    .onAppear {
                        guard !appearedIds.contains(txn.txn_id) else { return }

                        let index = filteredTransactions.firstIndex(where: {
                            $0.txn_id == txn.txn_id
                        }) ?? 0

                        withAnimation(
                            .spring(response: 0.42, dampingFraction: 0.78)
                            .delay(Double(index) * 0.07)
                        ) {
                            appearedIds.insert(txn.txn_id)
                        }
                    }
                )
            },

            // MARK: - SEARCH
            searchMatcher: { txn, query in
                let drugName = txn.drug?.drug_name ?? ""
                return drugName.localizedCaseInsensitiveContains(query)
            },

            // MARK: - ROW TAP
            onRowTap: { txn in
                selectedTransasctionId = txn.txn_id
                userViewModel.currentTransactionTxnId = txn.txn_id
                handleResume()
            },

            // MARK: - MENU LONG PRESS
            onMenuTap: { txn in
                
            },

            // MARK: - DELETE
            onDelete: { ids in
                pendingAction = .multiDelete(ids)
            },

            // MARK: - MENU OPTION SELECTED
            onSelectOption: { option, _ in
                
            },

            menuOptions: TransactionDetailOption.allCases,
            optionLabel: { $0.rawValue },
//            filterView: {
//                AnyView(pmsFilterChips)
//            }
            filterView: nil
        )
        .onAppear {
            reloadTransactions()
        }
        .onReceive(TransactionDAO.shared.transactionsDidChange.receive(on: DispatchQueue.main)) {
            reloadTransactions()
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

    // MARK: - Reload
    private func reloadTransactions() {
        let countType: CountType = router.selectedPillScanningType ?? .FIXED
        Task {
            await userViewModel.getAllPartialTransactions(countType: countType)
            await MainActor.run {
                let fresh = userViewModel.historyCountTransactions.sorted { $0.created_at > $1.created_at }
                let freshIds = Set(fresh.map { $0.txn_id })
                let removedIds = Set(transactions.map { $0.txn_id }).subtracting(freshIds)

                if !removedIds.isEmpty {
                    deletingIds.formUnion(removedIds)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            transactions.removeAll { removedIds.contains($0.txn_id) }
                        }
                        deletingIds.subtract(removedIds)
                        resetList.toggle()
                    }
                }

                let added = fresh.filter { !Set(transactions.map { $0.txn_id }).contains($0.txn_id) }
                if !added.isEmpty {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                        transactions = fresh
                    }
                    resetList.toggle()
                }

                pillCounts = Dictionary(
                    uniqueKeysWithValues: fresh.map { txn in
                        let counted = TransactionDetailDAO.shared.totalCountForStep(
                            txnId: txn.txn_id,
                            step: .targetVerification
                        )
                        return (key: txn.txn_id, value: Int(counted))
                    }
                )
            }
        }
    }
}

// MARK: - Menu Action Handler
extension DispenseCountPartialTxnList {
    
    private func handleResume() {
        guard let txnId = selectedTransasctionId,
              let txn = userViewModel.getTransactionEntity(by: txnId)
        else { return }

        userViewModel.currentTransactionTxnId = txnId
        pillScanViewmodel.selectedTransaction = txn


        let scanType: ScanType = txn.is_ndc_verfied == true ? .resumeCount : .barcode
        
        router.navigate(
            to: .authentication(
                .login(.dashboard(.pillCount(.scan(scanType))))
            )
        )
    }
}

// MARK: - Popups
extension DispenseCountPartialTxnList {

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

        let countType: CountType = router.selectedPillScanningType ?? .FIXED

        switch action {
        case .delete(let id):
            deletingIds.insert(id)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Task {
                    await userViewModel.softDeleteTheSelectedTransaction(
                        transactionId: id,
                        countType: countType
                    )

                    await MainActor.run {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            transactions.removeAll { $0.txn_id == id }
                        }

                        deletingIds.remove(id)
                        resetList.toggle()
                    }
                }
            }

        case .multiDelete(let ids):
            deletingIds.formUnion(ids)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Task {
                    await userViewModel.softDeleteMultipleTransactions(
                        txnIds: ids,
                        countType: countType
                    )

                    await MainActor.run {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            transactions.removeAll { ids.contains($0.txn_id) }
                        }

                        deletingIds.subtract(ids)
                        resetList.toggle()
                    }
                }
            }
        }
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .delete:
            return L10n.DispensePartial.Dialog.confirmDeleteTitle

        case .multiDelete:
            return L10n.DispensePartial.Dialog.deleteSelectedTitle

        case .none:
            return ""
        }
    }


    private var dialogMessage: String {
        switch pendingAction {
        case .delete:
            return L10n.DispensePartial.Dialog.deleteTransactionMessage

        case .multiDelete:
            return L10n.DispensePartial.Dialog.deleteSelectedTransactionsMessage

        case .none:
            return ""
        }
    }

    private var confirmButtonTitle: String {
        switch pendingAction {
        case .delete, .multiDelete:
            return L10n.Common.delete

        case .none:
            return ""
        }
    }
}

extension PillCountTransactionEntity: ListItemIdentifiable {
    public var id: Int64 { txn_id }
}
