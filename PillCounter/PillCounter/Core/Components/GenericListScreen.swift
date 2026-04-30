//
//  GenericListScreen.swift
//  PillCounter
//
//  Created by Bhushan Patil on 01/04/26.
//

import SwiftUI

protocol ListItemIdentifiable {
    var id: Int64 { get }
}

struct GenericListScreen<Item: Identifiable, Option: Hashable>: View where Item.ID == Int64 {
    // data
    let items: [Item]
    let title: String
    let resetTrigger: Bool
    // UI
    let rowView: (Item, Bool, Set<Int64>) -> AnyView

    // SEARCH
    let searchMatcher: (Item, String) -> Bool

    // ACTIONS
    let onRowTap: (Item) -> Void
    let onMenuTap: (Item) -> Void
    let onDelete: (Set<Int64>) -> Void
    let onSelectOption: (Option, Item?) -> Void

    let menuOptions: [Option]
    let optionLabel: (Option) -> String
    let filterView: (() -> any View)?
    // environment variables
    @EnvironmentObject private var appColors: AppColors

    // MARK: STATES
    // search
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    // delete/edit
    @State private var isEditing: Bool = false
    @State private var selectedIds: Set<Int64> = []

    @State private var selectedItem: Item?
    


    // MARK: BODY
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: { contentView },
                bottomContent: { EmptyView() },
                headerActions: { header },
                showBackButton: !isSearching,
                showHamburgerMenu: false,
                title: isSearching
                    ? ""
                    : (isEditing ? "DELETE BATCHES" : title),
                headerActionsBackground: appColors.primaryBackground
            )
            
            if isEditing {
                VStack {
                    Spacer()

                    HStack(spacing: 12) {

                        // CANCEL
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isEditing = false
                                selectedIds.removeAll()
                            }
                        } label: {
                            Text("CANCEL")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(appColors.primary)
                                .frame(maxWidth: 140)
                                .padding(.vertical, 10)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(appColors.primary, lineWidth: 1)
                        )

                        // DELETE
                        Button {
                            onDelete(selectedIds)
                        } label: {
                            Text("DELETE")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: 140)
                                .padding(.vertical, 10)
                        }
                        .background(selectedIds.isEmpty ? Color.gray.opacity(0.4) : appColors.primary)
                        .cornerRadius(20)
                        .disabled(selectedIds.isEmpty)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(appColors.primaryBackground)
                    .padding(.bottom, 20)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.3), value: isEditing)
            }
        }
        .onChange(of: searchText) { _, new in
            debounce(new)
        }
        .onChange(of: resetTrigger) { _, _ in
            print("Reset Triggered")
            isEditing = false
            selectedIds.removeAll()
        }
    }
}

extension GenericListScreen {

    fileprivate var contentView: some View {
        VStack {
            if let filterView = filterView {
                AnyView(filterView())
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(filteredItems) { item in
                        row(item)
                    }
                    if filteredItems.isEmpty {
                        if debouncedSearchText.isEmpty {
                            // No data at all
                            EmptyStateView(
                                imageName: nil,
                                systemImageName: nil,
                                title:  "No partial counts available",
                                subtitle: nil
                            )
                            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.6)
                        } else {
                            // Search active but no match
                            EmptyStateView(
                                imageName: nil,
                                systemImageName: "magnifyingglass",
                                title: "No results found",
                                subtitle: nil
                            )
                            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.6)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, isEditing ? 100 : 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 90)
        .background(appColors.primaryBackground)

    }

    fileprivate var filteredItems: [Item] {
        if debouncedSearchText.isEmpty {
            return items
        }
        return items.filter {
            searchMatcher($0, debouncedSearchText)
        }
    }
}

extension GenericListScreen {

    fileprivate func row(_ item: Item) -> some View {
        rowView(item, isEditing, selectedIds)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isEditing)
            .onTapGesture {
                if isEditing {
                    toggle(item.id)
                } else {
                    onRowTap(item)
                }
         }
    }
}

extension GenericListScreen {
    private var isAllSelected: Bool {
        let allIds = Set(items.map { $0.id })
        return !allIds.isEmpty && selectedIds == allIds
    }
    
    fileprivate var header: some View {
        Group {
            if isEditing {
                HStack(spacing: 10) {

                    // CHECKBOX
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(appColors.primary, lineWidth: 1)
                            .frame(width: 18, height: 18)

                        if isAllSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(appColors.primary)
                        }
                    }

                    Text("Select All")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(appColors.primary)

                }
                .onTapGesture {
                    toggleAll()
                }
                .padding(.trailing, 16)
                .transition(.opacity)

            } else if isSearching {
                UnderlinedSearchBar(
                    text: $searchText,
                    isFocused: $isSearchFieldFocused,
                    appColors: appColors,
                    onExitSearch: {
                        withAnimation(.spring()) {
                            isSearching = false
                            searchText = ""
                            isSearchFieldFocused = false
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))

            } else {
                HStack(spacing: 16) {
                    
                    Button {
                        withAnimation(.spring()) {
                            isSearching = true
                            isSearchFieldFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(appColors.primary)
                    }

                    if !items.isEmpty {
                        Button {
                            withAnimation(.spring()) {
                                isEditing = true
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                                .foregroundColor(appColors.primary)
                        }
                    }
                }
                .padding(.trailing, 16)
                .transition(.opacity)
            }
        }
    }
}

extension GenericListScreen {

    fileprivate func debounce(_ text: String) {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    debouncedSearchText = text
                }
            }
        }
    }
}

extension GenericListScreen {

    fileprivate func toggle(_ id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    fileprivate func toggleAll() {
        let allIds = Set(items.map { $0.id })

        if selectedIds == allIds {
            selectedIds.removeAll()
        } else {
            selectedIds = allIds
        }
    }
}
