//
//  CountHistoryView.swift
//  PillCounter
//
//  Created by HC on 13/11/25.
//

import SwiftUI

struct CountHistoryView: View {

    @Environment(\.isLandscape) private var isLandscape
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var pillScanViewmodel: PillScanViewModel
    @EnvironmentObject private var router: Router

    @State private var selectedTransactionDetailOption:
        TransactionDetailOption = .resume
    @State private var showMenuOptions: Bool = false
    @State private var selectedTransasctionId: Int64?

    // MARK: - SEARCH STATE
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - EDIT/DELETE STATE
    @State private var isEditing: Bool = false
    @State private var selectedTxnIds: Set<Int64> = []
    @State private var selectedFilter: TransactionFilter = .all

    @State private var pendingAction: TransactionAction?

    let title: String

    // Filter Logic
    var filteredTransactions: [PillCountTransactionEntity] {
        let baseList: [PillCountTransactionEntity]

        if searchText.isEmpty {
            baseList = userViewModel.historyCountTransactions
        } else {
            baseList = userViewModel.historyCountTransactions.filter { txn in
                let drugName = txn.drug?.drug_name ?? ""
                return drugName.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch selectedFilter {
        case .all:
            return baseList

        case .pms:
            return baseList.filter { $0.is_from_pms }

        case .nonPms:
            return baseList.filter { !$0.is_from_pms }
        }
    }

    // Helper to get the actual transaction objects for the selected IDs
    var selectedTransactionsList: [PillCountTransactionEntity] {
        // We look through fixedCountTransactions (or filteredTransactions) to find matches
        return userViewModel.historyCountTransactions.filter {
            selectedTxnIds.contains($0.txn_id)
        }
    }

    // Helper to check if all filtered items are selected
    var areAllSelected: Bool {
        guard !filteredTransactions.isEmpty else { return false }
        // Check if every visible item's ID is in the selected set
        return filteredTransactions.allSatisfy {
            selectedTxnIds.contains($0.txn_id)
        }
    }

    enum TransactionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case pms = "PMS"
        case nonPms = "Non PMS"

        var id: String { rawValue }
    }

    private var filterTabs: some View {
        HStack {
            Spacer()

            HStack(spacing: 12) {
                ForEach(TransactionFilter.allCases) { filter in
                    FilterTabButton(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                            selectedTxnIds.removeAll()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)

    }

    struct FilterTabButton: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        isSelected
                            ? AppColors.shared.primary
                            : AppColors.shared.text
                    )
                    .frame(width: 90, height: 36)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected
                                    ? AppColors.shared.primary
                                    : AppColors.shared.text,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

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
                // MARK: - HEADER ACTIONS
                headerActions: {
                    if isEditing {
                        // --- EDIT MODE HEADER ---
                        HStack {
                            // Left: Select All Button
                            Button {
                                toggleSelectAll()
                            } label: {
                                HStack(spacing: 12) {
                                    // Visual representation of Select All state
                                    Image(
                                        systemName: areAllSelected
                                            ? "checkmark.square.fill" : "square"
                                    )
                                    .foregroundColor(
                                        areAllSelected
                                            ? appColors.secondary : .gray
                                    )

                                    Text(
                                        areAllSelected
                                            ? "Deselect All" : "Select All"
                                    )
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(appColors.text)
                                }
                                .padding(.leading)
                            }

                            Spacer()

                            // Right: Delete Action or Cancel
                            HStack(spacing: 20) {
                                // Delete Button (Only active if items are selected)
                                Button {
                                    pendingAction = .multiDelete(selectedTxnIds)
                                } label: {
                                    Text("Delete")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(
                                            selectedTxnIds.isEmpty
                                                ? .gray : appColors.secondary
                                        )
                                }
                                .disabled(selectedTxnIds.isEmpty)

                                // Cancel (Exit Edit Mode)
                                Button {
                                    withAnimation {
                                        isEditing = false
                                        selectedTxnIds.removeAll()
                                    }
                                } label: {
                                    Text("Cancel")
                                        .font(
                                            .system(size: 16, weight: .regular)
                                        )
                                        .foregroundColor(appColors.text)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)  // Span full width
                        .padding(.horizontal, 10)
                        .transition(.opacity)

                    } else if isSearching {
                        // --- SEARCH MODE HEADER (From previous logic) ---
                        // ... (Keep your existing Search Bar logic here) ...
                        UnderlinedSearchBar(
                            text: $searchText,
                            isFocused: $isSearchFieldFocused,
                            appColors: appColors,
                            onExitSearch: {
                                // Logic to close search mode
                                withAnimation(.spring()) {
                                    isSearching = false
                                    searchText = ""
                                    isSearchFieldFocused = false
                                }
                            }
                        )
                        .transition(
                            .move(edge: .trailing).combined(with: .opacity)
                        )

                    } else {
                        // --- STANDARD MODE HEADER ---
                        HStack(spacing: 16) {
                            Button {
                                withAnimation(.spring()) {
                                    isSearching = true
                                    isSearchFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appColors.secondary)
                            }

                            // Trash Button -> Enters Edit Mode
                            Button {
                                withAnimation {
                                    isEditing = true
                                    selectedTxnIds.removeAll()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 20))
                                    .foregroundStyle(appColors.secondary)
                            }
                        }
                        .padding(.trailing, 16)
                        .transition(.opacity)
                    }
                },
                // Hide back button if Searching OR Editing to use full header space
                showBackButton: !isSearching && !isEditing,
                showHamburgerMenu: false,
                // Hide title if Searching OR Editing
                title: (isSearching || isEditing) ? "" : title
            )
            .onAppear {
                if router.selectedPillScanningType == .FIXED {
                    Task {
                        await userViewModel.getAllPartialTransactions(
                            countType: .FIXED
                        )

                        //                        if userViewModel.fixedCountTransactions.isEmpty {
                        //                            userViewModel.generateDummyData()
                        //                        }
                    }
                } else {
                    Task {
                        await userViewModel.getAllPartialTransactions(
                            countType: .REGULAR
                        )
                    }
                }
            }
            .customPopup(isPresented: $showMenuOptions) {
                menuOptions
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
    }

    // MARK: - CONTENT VIEW
    private var contentView: some View {
        VStack {

            filterTabs
                .padding(.vertical, 5)

            if isEditing {
                HStack {
                    Text("\(selectedTxnIds.count) Selected")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(appColors.text.opacity(0.6))

                    Spacer()

                    Text("Tap item(s) to delete.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(appColors.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    ForEach(filteredTransactions, id: \.txn_id) {
                        (txn: PillCountTransactionEntity) in

                        let counted = PillsDataLocalStorage.shared
                            .getTotalCountForStep(
                                txnId: txn.txn_id,
                                step: .targetVerification
                            )

                        listItem(
                            txnId: txn.txn_id,
                            name: txn.drug?.drug_name ?? "N/A",
                            date:
                                "\(Formatter.getDateString(from: txn.created_at)) • "
                                + "\(Formatter.getTimeString(from: txn.created_at))",
                            trailingText: "\(counted)"
                                + (router.selectedPillScanningType == .FIXED
                                    ? " / \(txn.target_count)" : ""),
                            icon: "ellipsis",
                            barcodeImagePath: txn.barcode_image,
                            isFromPms: txn.is_from_pms,
                            onIconTap: {
                                if !isEditing {
                                    showMenuOptions = true
                                    selectedTransasctionId = txn.txn_id
                                    userViewModel.currentTransactionTxnId =
                                        txn.txn_id
                                }
                            }
                        )
                    }

                    if filteredTransactions.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("No transactions found")
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 90)
        .padding(.horizontal, isLandscape ? SafeAreaInsets.leading + 5 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }

    //    private var contentView: some View {
    //        VStack {
    //            filterTabs
    //                .padding(.vertical, 5)
    //            ScrollView(showsIndicators: false) {
    //                transactionsList
    //                    .padding(.horizontal, 16)
    //                    .padding(.bottom, 20)
    //            }
    //        }
    //        .padding(.top, 90)
    //        .padding(.horizontal, isLandscape ? SafeAreaInsets.leading + 5 : 0)
    //        .frame(maxWidth: .infinity, maxHeight: .infinity)
    //        .background(appColors.primaryBackground)
    //    }

    private var transactionsList: some View {
        VStack(spacing: 16) {
            ForEach(filteredTransactions, id: \.txn_id) { txn in
                transactionRow(txn)
            }

            if filteredTransactions.isEmpty {
                emptyStateView
            }
        }
    }

    @ViewBuilder
    private func transactionRow(_ txn: PillCountTransactionEntity) -> some View
    {

        listItem(
            txnId: txn.txn_id,
            name: txn.drug?.drug_name ?? "N/A",
            date:
                "\(Formatter.getDateString(from: txn.created_at)) • \(Formatter.getTimeString(from: txn.created_at))",
            trailingText: "\(0)"
                + (router.selectedPillScanningType == .FIXED
                    ? " / \(txn.target_count)" : ""),
            icon: "ellipsis",
            barcodeImagePath: txn.barcode_image,
            isFromPms: txn.is_from_pms,
            onIconTap: {
                if !isEditing {
                    showMenuOptions = true
                    selectedTransasctionId = txn.txn_id
                    userViewModel.currentTransactionTxnId = txn.txn_id
                }
            }
        )
        .onTapGesture {
            if isEditing {
                toggleSelection(for: txn.txn_id)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))

            Text("No transactions found")
                .foregroundColor(.gray)
        }
        .padding(.top, 60)
    }

    // MARK: - LIST ITEM
    private func listItem(
        txnId: Int64,
        name: String,
        date: String,
        trailingText: String,
        icon: String,
        barcodeImagePath: String?,
        isFromPms: Bool = false,
        onIconTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {

            // 1. CHECKBOX
            if isEditing {
                PillCounterCheckbox(
                    isChecked: Binding(
                        get: { selectedTxnIds.contains(txnId) },
                        set: { _ in toggleSelection(for: txnId) }
                    ),
                    size: 20,
                    tintColor: appColors.primary,
                )
                .padding(.trailing, 4)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // 2. IMAGE LOGIC
            ThumbnailImageView(
                imagePath: barcodeImagePath,
                isFromPms: isFromPms
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(date)
                        .font(.system(size: 12))
                        .foregroundColor(appColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(1)
                        .layoutPriority(1)

                    if isFromPms {
                        Text("PMS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appColors.primary)
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 4. TRAILING INFO & ACTION
            Text(trailingText)
                .font(.subheadline)
                .foregroundColor(appColors.text)

            if !isEditing {
                Button(action: onIconTap) {
                    Image(systemName: icon)
                        .foregroundColor(appColors.primary)
                        .font(.system(size: 20))
                        .rotationEffect(.degrees(90))
                        .frame(width: 20, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            colorScheme == .dark ? Color.black.opacity(0.8) : Color.white
        )
        .cornerRadius(10)
        .animation(.spring(), value: isEditing)
    }

    // MARK: - LOGIC HELPERS
    // Toggle single selection
    private func toggleSelection(for id: Int64) {
        if selectedTxnIds.contains(id) {
            selectedTxnIds.remove(id)
        } else {
            selectedTxnIds.insert(id)
        }
    }

    // Toggle Select All / Deselect All
    private func toggleSelectAll() {
        if areAllSelected {
            // Deselect all visible
            selectedTxnIds.removeAll()
        } else {
            // Select all visible
            let allIds = filteredTransactions.map { $0.txn_id }
            selectedTxnIds.formUnion(allIds)
        }
    }

    // Perform Delete
    private func performBatchDelete() {
        Task {
            // Call ViewModel to delete
            await userViewModel.softDeleteMultipleTransactions(
                txnIds: selectedTxnIds,
                countType: router.selectedPillScanningType ?? .FIXED
            )

            await MainActor.run {
                // Reset State
                isEditing = false
                selectedTxnIds.removeAll()
            }
        }
    }

    // MARK: - MENU OPTIONS
    private var menuOptions: some View {
        MenuOption(
            options: TransactionDetailOption.allCases,
            selectedOption: $selectedTransactionDetailOption,
            isPresented: $showMenuOptions,
            label: { $0.rawValue },
            onSelect: { option in

                switch option {
                case .resume:
                    handleResume()

                case .delete:
                    if let txnId = selectedTransasctionId {
                        pendingAction = .delete(txnId)
                    }

                case .forceComplete:
                    if let txnId = selectedTransasctionId {
                        pendingAction = .forceComplete(txnId)
                    }
                }
            }
        )
    }

    private func handleResume() {
        guard let txnId = selectedTransasctionId,
            let txn = userViewModel.getTransactionEntity(by: txnId)
        else {
            return
        }

        userViewModel.currentTransactionTxnId = txnId
        pillScanViewmodel.selectedTransaction = txn 

        // TODO: Simplify this branching later
        let lastStep = pillScanViewmodel.getLastSavedControlledStep()

        if lastStep == nil && txn.is_ndc_verfied == false {
            router.navigate(
                to: .authentication(
                    .login(.dashboard(.pillCount(.barcodeScanning(.barcode))))
                )
            )
        } else {
            router.navigate(
                to: .authentication(
                    .login(.dashboard(.pillCount(.pillCountView)))
                )
            )
        }
    }

    // Confirmation Dialogs
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
            return "Are you sure you want to delete this transaction?"
        case .forceComplete:
            return "Are you sure you want to force complete this transaction?"
        case .multiDelete:
            return "Are you sure you want to delete selected transactions?"
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

    //Handle Action
    private func handleConfirmedAction() {
        guard let action = pendingAction else { return }

        pendingAction = nil

        switch action {

        case .delete(let id):
            Task {
                await userViewModel.softDeleteTheSelectedTransaction(
                    transactionId: id,
                    countType: router.selectedPillScanningType ?? .FIXED
                )
            }

        case .forceComplete(let id):
            Task {
                await userViewModel.forceCompleteTheSelectedTransaction(
                    txnId: id,
                    countType: router.selectedPillScanningType ?? .FIXED
                )
            }

        case .multiDelete(let ids):
            Task {
                await userViewModel.softDeleteMultipleTransactions(
                    txnIds: ids,
                    countType: router.selectedPillScanningType ?? .FIXED
                )

                await MainActor.run {
                    isEditing = false
                    selectedTxnIds.removeAll()
                }
            }
        }
    }
}

enum TransactionAction {
    case delete(Int64)
    case forceComplete(Int64)
    case multiDelete(Set<Int64>)
}
