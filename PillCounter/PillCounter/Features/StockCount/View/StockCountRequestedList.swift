////
////  StockCountRequestedList.swift
////  PillCounter
////
////  Created by Bhushan Patil on 02/04/26.
////
////
////  StockCountPartialBatchList.swift
////  PillCounter
////
////  Created by Bhushan Patil on 01/04/26.
////
//
//import SwiftUI
//
//struct StockCountRequestedList: View {
//
//    @Environment(\.isLandscape) private var isLandscape
//    @EnvironmentObject private var appColors: AppColors
//    @EnvironmentObject private var router: Router
//
//    @EnvironmentObject private var stockViewModel: StockCountViewModel
//    @EnvironmentObject private var userViewModel: UserViewModel
//    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
//
//    @State private var selectedTxnId: Int64?
//
//    @State private var pendingAction: TransactionAction?
//    @State private var showMenuOptions: Bool = false
//    @State private var selectedTransactionDetailOption:
//        TransactionDetailOption = .resume
//    @State private var resetList: Bool = false
//
//
//    // MARK: - FILTER
//    enum BatchFilter: String, CaseIterable, Identifiable {
//        case all = "All"
//        case active = "Active"
//        case paused = "Paused"
//
//        var id: String { rawValue }
//    }
//
//    // MARK: - BODY
//
//    var body: some View {
//        
//        GenericListScreen<PillCountTransactionEntity, TransactionDetailOption>(
//            items: stockViewModel.regularCountTransactions,
//            title: "NDC REQUESTS",
//            resetTrigger: resetList,
//
//            // 🔹 ROW UI
//            rowView: { batch, isEditing, selectedIds in
//                AnyView(
//                    batchRow(
//                        batch,
//                        isEditing: isEditing,
//                        selectedIds: selectedIds
//                    )
//                )
//            },
//            
//            //  SEARCH
//            searchMatcher: { batch, query in
//                batch.drug?.drug_name?.localizedCaseInsensitiveContains(query) ?? false
//                || batch.drug?.ndc?.localizedCaseInsensitiveContains(query) ?? false
//            },
//            
//            //  ROW TAP
//            onRowTap: { batch in
//                selectedTxnId = batch.txn_id
//                stockViewModel.currentBatch = nil
//                handleResume()
//            },
//            
//            //  MENU TAP (IMPORTANT)
//            onMenuTap: { batch in
//                selectedTxnId = batch.txn_id
//                
//            },
//            
//            //  DELETE (MULTI)
//            onDelete: { ids in
//                pendingAction = .multiDelete(ids)
//            },
//            
//            //  MENU ACTIONS
//            onSelectOption: { option, item in
//            },
//            
//            menuOptions: TransactionDetailOption.allCases,
//            optionLabel: { $0.rawValue },
//            filterView: nil
//        )
//        .onAppear {
//            Task{
//                await stockViewModel.getAllPartialTransactions(countType: .REGULAR, userId: userViewModel.userID)
//            }
//        }
//        .customPopup(
//            isPresented: Binding(
//                get: { pendingAction != nil },
//                set: { if !$0 { pendingAction = nil } }
//            )
//        ) {
//            if pendingAction != nil {
//                commonConfirmationDialog
//            }
//        }
//        .customPopup(isPresented: $showMenuOptions) {
//            menuOptions
//        }
//    }
//    
//    private func batchRow(
//        _ txn: PillCountTransactionEntity,
//        isEditing: Bool,
//        selectedIds: Set<Int64>
//    ) -> some View {
//
//        HStack(spacing: 16) {
//            if isEditing {
//                PillCounterCheckbox(
//                    isChecked: Binding(
//                        get: { selectedIds.contains(txn.txn_id) },
//                        set: { _ in } // handled by GenericListScreen
//                    ),
//                    size: 20,
//                    tintColor: appColors.primary
//                )
//                .transition(.move(edge: .leading).combined(with: .opacity))
//            }
//
//            ThumbnailImageView(
//                imagePath: "",
//                placeholderImageName: "new_rx" ,
//                placeholderBackgroundColor: appColors.secondary,
//                isFromPms: false,
//                showImageBackground: appColors.primaryBackground
//            )
//
//            VStack(alignment: .leading, spacing: 6) {
//                Text("NDC \(txn.drug?.ndc ?? "123456789")")
//                    .font(.system(size: 14, weight: .bold))
//                    .foregroundColor(appColors.text)
//
//                Text(getCurrentFormattedDate())
//                    .font(.system(size: 12))
//                    .foregroundColor(appColors.text.opacity(0.7))
//            }
//
//            Spacer()
//            
//            Image(systemName: "partial")
//                .foregroundColor(appColors.text)
//
//            if !isEditing {
//                Button {
//                    selectedTxnId = txn.txn_id
//                    showMenuOptions = true
//                } label: {
//                    Image(systemName: "ellipsis")
//                        .rotationEffect(.degrees(90))
//                        .foregroundColor(appColors.primary)
//                }
//            }
//        }
//        .padding(12)
//        .background(appColors.secondaryBackground)
//        .cornerRadius(10)
//    }
//
//    
//    private func handleResume() {
//        guard let txnId = selectedTxnId,
//            let txn = userViewModel.getTransactionEntity(by: txnId)
//        else {
//            print("Resume failed")
//            return
//        }
//
//        userViewModel.currentTransactionTxnId = txnId
//        stockViewModel.selectedTransaction = txn.is_from_pms ? txn : nil
//        pillScanViewModel.selectedTransaction = txn
//
//        router.navigate(
//            to: .authentication(
//                .login(.dashboard(.pillCount(.barcodeScanning(.stockCount))))
//            )
//        )
//    }
//    
//    func getCurrentFormattedDate() -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "dd-MM-yyyy HH:mm a"
//        formatter.locale = Locale(identifier: "en_US_POSIX")
//        return formatter.string(from: Date())
//    }
//}
//
//
//// MARK: POPUP
//extension StockCountRequestedList {
//    
//    private var menuOptions: some View {
//        MenuOption(
//            options: TransactionDetailOption.allCases,
//            selectedOption: $selectedTransactionDetailOption,
//            isPresented: $showMenuOptions,
//            label: { $0.rawValue },
//            onSelect: { option in
//                switch option {
//                    case .resume:
//                        router.navigate(
//                            to: .authentication(
//                                .login(
//                                    .dashboard(
//                                        .pillCount(.barcodeScanning(ScanType.stockCount))
//                                    )
//                                )
//                            )
//                        )
//                    case .delete:
//                        if let id = selectedTxnId {
//                            showMenuOptions = false
//                            pendingAction = .delete(id)
//                        }
//                    case .forceComplete:
//                        if let id = selectedTxnId {
//                            showMenuOptions = false
//                            pendingAction = .delete(id)
//                        }
//                    
//                }
//            }
//        )
//    }
//
//    
//    
//    private var commonConfirmationDialog: some View {
//        ConfirmationDialogue(
//            title: dialogTitle,
//            message: dialogMessage,
//            cancelButtonText: "CANCEL",
//            confirmButtonText: confirmButtonTitle,
//            onCancel: {
//                pendingAction = nil
//            },
//            onConfirm: {
//                handleConfirmedAction()
//            }
//        )
//    }
//    
//    private func handleConfirmedAction() {
//        guard let action = pendingAction else { return }
//        
//        pendingAction = nil
//
//        switch action {
//            
//        case .delete(let id):
//            // TODO: Delete single batch API
//            print("Delete batch \(id)")
//            
//        case .multiDelete(let ids):
//            // TODO: Delete multiple batches API
//            print("Multi Delete \(ids)")
//        }
//    }
//
//    private var dialogTitle: String {
//        switch pendingAction {
//        case .delete:
//            return "Confirm Delete"
//        case .multiDelete:
//            return "Delete Selected"
//        case .none:
//            return ""
//        }
//    }
//
//    private var dialogMessage: String {
//        switch pendingAction {
//        case .delete:
//            return "Are you sure you want to delete this batch?"
//        case .multiDelete:
//            return "Are you sure you want to delete selected batches?"
//        case .none:
//            return ""
//        }
//    }
//
//    private var confirmButtonTitle: String {
//        switch pendingAction {
//        case .delete, .multiDelete:
//            return "DELETE"
//        case .none:
//            return ""
//        }
//    }
//}
