//
//  PillScanDetailGridScreen.swift
//  PillCounter
//

import SwiftUI

// MARK: - PillScanDetailGridScreen
// Replaces BottonControlsViewForTransactionList with a full-screen grid view.
// Portrait: 2-column grid with image cards. Landscape: horizontal scroll row.
struct PillScanDetailGridScreen: View {

    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel

    // MARK: - State
    @State private var isEditing: Bool = false
    @State private var selectedIds: Set<Int64> = []
    @State private var showDeleteConfirm: Bool = false
    @State private var selectedUIImage: Image? = nil
    @State private var showImageViewer = false

    
    // MARK: - Derived data from ViewModel
    private var details: [PillCountTransactionDetailsEntity] {
        (pillScanViewModel.currentTransactionTransactionDetails ?? [])
            .filter { !$0.is_deleted }
    }

    private var drugName: String {
        pillScanViewModel.currentTransaction?.drug?.drug_name ?? ""
    }

    private var pillCount: Int {
        details.reduce(0) { $0 + Int($1.pill_count) }
    }

    private var targetCount: Int {
        Int(pillScanViewModel.currentTransaction?.target_count ?? 0)
    }

    private var countType: CountType {
        CountType(rawValue: pillScanViewModel.currentTransaction?.count_type ?? "") ?? .FIXED
    }
//
//     var isFixed: Bool {
//        if countType == .FIXED { return true }
//        // REGULAR count with a container-initiate detail also shows target count
//        return details.first?.type == ControlledStep.containerInitiate.rawValue
//    }
//    
    @State private var isFixed: Bool = false


    // MARK: - Body
    var body: some View {
        
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: { contentView },
                bottomContent: { EmptyView() },
                headerActions: { headerActions },
                showBackButton: true,
                showHamburgerMenu: false,
                title: isEditing ? "DELETE TRANSACTION" : "TOTAL COUNT",
                headerActionsBackground: appColors.primaryBackground,
                backgroundColor: appColors.secondaryBackground
            )
            .onAppear {
                if countType == .FIXED { return }
                isFixed = details.first?.type == ControlledStep.containerInitiate.rawValue
            }
            // MARK: - Edit mode bottom bar
            if isEditing {
                VStack {
                    Spacer()

                    EqualWidthHStackButtons(spacing: 16) {
                        PillCountingButton(
                            title: "CANCEL",
                            textColor: appColors.primary,
                            backgroundColor: .clear,
                            borderColor: appColors.primary,
                            font: .system(size: 14, weight: .semibold),
                            cornerRadius: 30,
                            horizontalPadding: 32,
                            verticalPadding: 14,
                            iconSize: 0,
                            action: {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isEditing = false
                                    selectedIds.removeAll()
                                }
                            }
                        )

                        PillCountingButton(
                            title: "DELETE",
                            textColor: selectedIds.isEmpty ? .white.opacity(0.6) : .white,
                            backgroundColor: selectedIds.isEmpty ? Color.gray.opacity(0.4) : appColors.primary,
                            borderColor: .clear,
                            font: .system(size: 14, weight: .semibold),
                            cornerRadius: 30,
                            horizontalPadding: 32,
                            verticalPadding: 14,
                            iconSize: 0,
                            action: {
                                showDeleteConfirm = true
                            }
                        )
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
        .fullScreenCover(
            isPresented: Binding(
                get: { selectedUIImage != nil },
                set: { if !$0 { selectedUIImage = nil } }
            )
        ) {
            if let image = selectedUIImage {
                FullScreenImageView(image: image) {
                    selectedUIImage = nil
                }
            }
        }

        .customPopup(isPresented: $showDeleteConfirm) {
            deleteConfirmationDialog
        }
    }

    // MARK: - Header Actions
    @ViewBuilder
    private var headerActions: some View {
        if isEditing {
            let allIds = Set(details.map { $0.txn_details_id })
            let allSelected = !allIds.isEmpty && selectedIds == allIds

            HStack(spacing: 10) {
                Image(allSelected ? "icon_unselected" : "icon_selected")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(appColors.primary)

                Text(allSelected ? "Unselect All" : "Select All")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(appColors.primary)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleAll() }
            .padding(.trailing, 16)
            .transition(.opacity)

        } else {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring()) {
                        isEditing = true
                        selectedIds.removeAll()
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

    // MARK: - Main Content
    private var contentView: some View {
        VStack(spacing: 0) {
            // Drug name + count strip
            if !isEditing{
                infoStrip
            }

            if isLandscape {
                landscapeContent
            } else {
                portraitContent
            }
        }
        .padding(.top, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appColors.primaryBackground)
    }

    // MARK: - Drug name + pill count header strip
    private var infoStrip: some View {
        Group {
            if isLandscape {
                HStack(spacing: 8) {
                    Text(drugName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(appColors.text)
                        .lineLimit(1)

                    Spacer()

                    countView
                }
            } else {
                VStack(alignment: .center, spacing: 8) {
                    Text(drugName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(appColors.text)
                        .lineLimit(1)

                    countView
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private var countView: some View {
        Text(!isFixed ? "\(pillCount)/\(targetCount)" : "\(pillCount)")
            .font(.system(size: 25, weight: .bold))
            .foregroundColor(appColors.secondary)
    }

    // MARK: - Portrait: 2-column grid
    private var portraitContent: some View {
        ScrollView(showsIndicators: false) {
            if details.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: gridColumns,
                    spacing: 10
                ) {
                    ForEach(details, id: \.txn_details_id) { detail in
                        PillScanDetailCard(
                            detail: detail,
                            isEditing: isEditing,
                            isSelected: selectedIds.contains(detail.txn_details_id)
                        )
                        .onTapGesture {
                            if isEditing {
                                toggleSelection(detail.txn_details_id)
                            } else {
                                if let path = detail.image_path,
                                   let uiImage = PhotoFileManager.shared.loadImage(from: path) {
                                    selectedUIImage = uiImage
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, isEditing ? 100 : 20)
            }
        }
    }
    
    private var gridColumns: [GridItem] {
        let columnCount: Int
        if UIDevice.current.userInterfaceIdiom == .pad {
            columnCount = 4
        } else {
            columnCount = 2
        }
        return Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: columnCount
        )
    }

    // MARK: - Landscape: horizontal scroll
    private var landscapeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(details, id: \.txn_details_id) { detail in
                        PillScanDetailCard(
                              detail: detail,
                              isEditing: isEditing,
                              isSelected: selectedIds.contains(detail.txn_details_id)
                        )
                        .onTapGesture {
                            if isEditing {
                                toggleSelection(detail.txn_details_id)
                            }else{
                                if let path = detail.image_path,
                                  let uiImage = PhotoFileManager.shared.loadImage(from: path)
                               {
                                   selectedUIImage = uiImage
                               }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            Spacer()
        }
    }

    // MARK: - Portrait Card (square image + gradient overlay)
    private func portraitCard(_ detail: PillCountTransactionDetailsEntity) -> some View {
        let isSelected = selectedIds.contains(detail.txn_details_id)

        return ZStack(alignment: .bottomLeading) {
            // Image
            imageView(path: detail.image_path)
                .aspectRatio(1, contentMode: .fit)
                .clipped()

            // Gradient overlay with count + date
            VStack(alignment: .leading, spacing: 2) {
                Text("\(detail.pill_count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(appColors.secondary)

                Text(DateUtils.formatToUSDateTime(detail.created_at))
                    .font(.system(size: 11))
                    .foregroundColor(appColors.text.opacity(0.9))
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.65), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )

            // Selection checkbox (top-left)
            if isEditing {
                VStack {
                    HStack {
                        selectionCircle(isSelected: isSelected)
                            .padding(8)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? appColors.secondary : Color.clear,
                    lineWidth: 3
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Landscape Card (fixed size, count + date below)
    private func landscapeCard(_ detail: PillCountTransactionDetailsEntity) -> some View {
        let isSelected = selectedIds.contains(detail.txn_details_id)

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                imageView(path: detail.image_path)
                    .frame(width: 140, height: 105)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isEditing {
                    selectionCircle(isSelected: isSelected)
                        .padding(6)
                }
            }
            .frame(width: 140, height: 105)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? appColors.secondary : Color.clear,
                        lineWidth: 3
                    )
            )

            Text("\(detail.pill_count)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(appColors.secondary)

            Text(DateUtils.formatToUSDateTime(detail.created_at))
                .font(.system(size: 11))
                .foregroundColor(appColors.text.opacity(0.7))
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Shared image view
    @ViewBuilder
    private func imageView(path: String?) -> some View {
        if let path,
           let image = PhotoFileManager.shared.loadImage(from: path)
        {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 120)
                .clipped()
                .cornerRadius(12)
                .onTapGesture {
                    // handle tap if needed
                }
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColors.text.opacity(0.5), lineWidth: 1)
                .frame(width: 140, height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray.opacity(0.4))
                )
        }
    }

    // MARK: - Selection circle indicator
    private func selectionCircle(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? appColors.secondary : Color.black.opacity(0.4))
                .frame(width: 22, height: 22)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.4))

            Text( "No scans yet")
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.5)
    }

    // MARK: - Delete Confirmation
    private var deleteConfirmationDialog: some View {
        ConfirmationDialogue(
            title: "Delete Scans",
            message: "Are you sure you want to delete the selected scans?",
            cancelButtonText: "CANCEL",
            confirmButtonText: "DELETE",
            onCancel: {
                showDeleteConfirm = false
            },
            onConfirm: {
                performDelete()
            }
        )
    }

    // MARK: - Logic
    private func toggleSelection(_ id: Int64) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func toggleAll() {
        let allIds = Set(details.map { $0.txn_details_id })
        if selectedIds == allIds {
            selectedIds.removeAll()
        } else {
            selectedIds = allIds
        }
    }

    private func performDelete() {
        for id in selectedIds {
            pillScanViewModel
                .softDeleteCurrentTransactionSelectedTransactionDetail(
                    txnDetailId: id
                )
        }
        withAnimation {
            isEditing = false
            selectedIds.removeAll()
            showDeleteConfirm = false
        }
    }
}




extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
