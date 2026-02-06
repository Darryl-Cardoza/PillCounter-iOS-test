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

    let title: String

    // Filter Logic
    var filteredTransactions: [PillCountTransactionEntity] {
        if searchText.isEmpty {
            return userViewModel.historyCountTransactions
        } else {
            return userViewModel.historyCountTransactions.filter { txn in
                let drugName = txn.drug?.drug_name ?? ""
                return drugName.localizedCaseInsensitiveContains(searchText)
            }
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
                                HStack(spacing: 8) {
                                    // Visual representation of Select All state
                                    Image(
                                        systemName: areAllSelected
                                            ? "checkmark.square.fill" : "square"
                                    )
                                    .foregroundColor(
                                        areAllSelected
                                            ? appColors.secondary : .gray)

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
                                    performBatchDelete()
                                } label: {
                                    Text("Delete")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(
                                            selectedTxnIds.isEmpty
                                                ? .gray : appColors.secondary)
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
                            .move(edge: .trailing).combined(with: .opacity))

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
                            countType: .FIXED)

                        //                        if userViewModel.fixedCountTransactions.isEmpty {
                        //                            userViewModel.generateDummyData()
                        //                        }
                    }
                } else {
                    Task {
                        await userViewModel.getAllPartialTransactions(
                            countType: .REGULAR)
                    }
                }
            }
            .customPopup(isPresented: $showMenuOptions) {
                menuOptions
            }
        }
    }

    // MARK: - CONTENT VIEW
    private var contentView: some View {
        VStack {
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

                    ForEach(filteredTransactions, id: \.txn_id) { txn in
                        let counted =
                            userViewModel.actualCountedPillsForTheTransactions[
                                txn.txn_id] ?? 0

                        listItem(
                            txnId: txn.txn_id,  // Pass ID for selection logic
                            name: txn.drug?.drug_name ?? "N/A",
                            date:  "\(Formatter.getDateString(from: txn.created_at)) • " +
                            "\(Formatter.getTimeString(from: txn.created_at))",
                            trailingText: "\(counted)"
                                + (router.selectedPillScanningType == .FIXED
                                    ? " / \(txn.target_count)" : ""),
                            icon: "ellipsis",
                            barcodeImagePath: txn.barcode_image,
                            onIconTap: {
                                // Only allow menu options if NOT editing
                                if !isEditing {
                                    showMenuOptions = true
                                    selectedTransasctionId = txn.txn_id
                                    userViewModel.currentTransactionTxnId =
                                        txn.txn_id
                                }
                            }
                        )
                        // Add tap gesture to the whole row to toggle selection in Edit Mode
                        .onTapGesture {
                            if isEditing {
                                toggleSelection(for: txn.txn_id)
                            }
                        }
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

    // MARK: - LIST ITEM
    private func listItem(
        txnId: Int64,
        name: String,
        date: String,
        trailingText: String,
        icon: String,
        barcodeImagePath: String?, // 1. Add this parameter
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
                    tintColor: appColors.primary
                )
                .padding(.trailing, 4)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            // 2. IMAGE LOGIC
            ThumbnailImageView(
                imagePath: barcodeImagePath
            )
            
            // 3. TEXT INFO
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)
                
                Text(date)
                    .font(.system(size: 12))
                    .foregroundColor(appColors.text)
                    .lineLimit(1)
            }
            
            Spacer()
            
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
        .cornerRadius(14)
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

    // MARK: - MENU OPTIONS (Existing)
    private var menuOptions: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("SELECT OPTIONS")
                .foregroundStyle(appColors.text)
                .font(.system(size: 18, weight: .bold))

            ForEach(TransactionDetailOption.allCases) { option in
                PillCountingRadioButton(
                    option: option,
                    selectedOption: $selectedTransactionDetailOption,
                    label: option.rawValue,
                    selectedColor: appColors.primary,
                    unselectedColor: .gray.opacity(0.5),
                    size: 20,
                    lineWidth: 2,
                    textColor: appColors.text
                )
                .padding(.vertical)
            }
            .padding(.horizontal)

            HStack {
                PillCountingButton(
                    iconName: nil,
                    title: "CANCEL",
                    textColor: appColors.text,
                    backgroundColor: appColors.primaryBackground,
                    borderColor: appColors.primary,
                    font: .system(size: 12, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: { showMenuOptions = false }
                )

                PillCountingButton(
                    iconName: nil,
                    title: "OK",
                    textColor: Color.white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 12, weight: .regular),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: {
                        showMenuOptions = false
                        switch selectedTransactionDetailOption {
                        case .resume:
                            if let txnId = selectedTransasctionId,
                               let txn = userViewModel.getTransactionEntity(by: txnId) {

                                userViewModel.currentTransactionTxnId = txnId
                                pillScanViewmodel.selectedTransaction = txn.isComingFromPms ? txn : nil

                                if txn.isComingFromPms && (txn.barcode_image?.isEmpty ?? true) {
                                    router.navigate(
                                        to: .authentication(
                                            .login(
                                                .dashboard(.pillCount(.barcodeScanning))
                                            )
                                        )
                                    )
                                    Hl7ServiceController.shared.startClient()
                                } else {
                                    router.navigate(
                                        to: .authentication(
                                            .login(
                                                .dashboard(.pillCount(.pillCountView))
                                            )
                                        )
                                    )
                                }

                            } else {
                                print("Resume failed: transaction ID or entity missing")
                            }
                        case .delete:
                            Task {
                                await userViewModel
                                    .softDeleteTheSelectedTransaction(
                                        transactionId: selectedTransasctionId
                                            ?? 0,
                                        countType: router
                                            .selectedPillScanningType ?? .FIXED
                                    )
                            }
                        case .forceComplete:
                            Task {
                                await userViewModel.forceCompleteTheSelectedTransaction(
                                    txnId: selectedTransasctionId ?? 0,
                                    countType: router
                                        .selectedPillScanningType ?? .FIXED
                                )
                            }
                        }
                    }
                )
            }
        }
        .frame(width: 250)
    }
}
