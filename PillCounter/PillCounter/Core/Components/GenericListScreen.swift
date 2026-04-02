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

struct GenericListScreen<Item: Identifiable, Option: Hashable>: View {

    // data
    let items: [Item]
    let title: String

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

    // other
    @State private var selectedItem: Item?
    @State private var showMenu: Bool = false

    // MARK: BODY
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: { contentView },
                bottomContent: { EmptyView() },
                headerActions: {
                    header
                },
                showBackButton: !isSearching && !isEditing,
                showHamburgerMenu: false,
                title: (isSearching || isEditing) ? "" : title,
                headerActionsBackground: appColors.primaryBackground
            )
            .customPopup(isPresented: $showMenu) {
                MenuOption(
                    options: menuOptions,
                    selectedOption: .constant(menuOptions.first!),
                    isPresented: $showMenu,
                    label: optionLabel
                ) { option in
                    onSelectOption(option, selectedItem)
                }
            }
        }
        .onChange(of: searchText) { _, new in
            debounce(new)
        }
    }
}

extension GenericListScreen {

    fileprivate var contentView: some View {
        VStack {
            if isEditing {
                HStack {
                    Text("\(selectedIds.count) Selected")
                    Spacer()
                    Text("Tap item(s) to delete.")
                        .foregroundStyle(appColors.secondary)
                }
                .padding(.horizontal)
            }

            ScrollView {
                VStack(spacing: 16) {

                    ForEach(filteredItems) { item in
                        row(item)
                    }

                    if filteredItems.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal)
            }
        }
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
                    toggle(item.id as! Int64)
                } else {
                    onRowTap(item)
                }
            }
            .onLongPressGesture {
                selectedItem = item
                showMenu = true
            }
    }
}

extension GenericListScreen {

    fileprivate var header: some View {
        Group {
            if isEditing {
                HStack {
                    Button("Select All") {
                        toggleAll()
                    }
                    .foregroundColor(appColors.primary)

                    Spacer()

                    Button("Delete") {
                        onDelete(selectedIds)
                    }
                    .foregroundColor(appColors.primary)

                    Button("Cancel") {
                        withAnimation(.spring()) {
                            isEditing = false
                            selectedIds.removeAll()
                        }
                    }
                    .foregroundColor(appColors.primary)
                }
                .padding(.horizontal, 10)
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
        let allIds = Set(items.map { $0.id as! Int64 })

        if selectedIds == allIds {
            selectedIds.removeAll()
        } else {
            selectedIds = allIds
        }
    }
}

extension GenericListScreen {

    fileprivate var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))

            Text("No results found")
                .foregroundColor(.gray)
        }
        .padding(.top, 60)
    }
}
