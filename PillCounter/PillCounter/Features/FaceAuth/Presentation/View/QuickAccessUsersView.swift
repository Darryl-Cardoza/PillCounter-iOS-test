//
//  QuickAccessUsersView.swift
//  PillCounter
//
//  Hamburger-menu screen listing enrolled face-recognition ("Quick Access")
//  users — name, last-used timestamp, active/inactive toggle, and delete.
//  Pushed via Router like UserHistoryView. This is the single entry point for
//  face-user management — Settings now exposes only the session time limit.
//
//  Delete follows the same edit-mode flow as PillScanDetailGridScreen rather
//  than select-then-trash: the trash icon ENTERS edit mode, the header swaps
//  to a select-all control, checkboxes appear on each row, and Cancel/Delete
//  are pill buttons in a bottom bar with one confirmation for the whole
//  selection. Tapping a row does nothing outside edit mode, so a stray tap
//  can no longer arm a destructive action.
//

import SwiftUI

struct QuickAccessUsersView: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router

    @State private var rows: [Row] = []
    @State private var isEditing: Bool = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm: Bool = false
    @State private var showAddUser: Bool = false

    private struct Row: Identifiable {
        let id: String
        let name: String
        let lastUsed: Date?
        var isActive: Bool
        /// Enrollment thumbnail, nil for users enrolled before avatars existed
        /// or whose capture failed — those rows show a placeholder.
        let avatar: UIImage?
    }

    private static let lastUsedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy HH:mm a"
        return formatter
    }()

    private var areAllSelected: Bool {
        !rows.isEmpty && selectedIds.count == rows.count
    }

    var body: some View {
        // The "Setup Quick Access" pitch is first-run dashboard onboarding
        // only (see UserProfileScreen) — reaching this screen from the
        // hamburger menu always gets the plain list, empty or not.
        userListScreen
            .onAppear(perform: reload)
    }

    private var userListScreen: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: { content },
                bottomContent: { EmptyView() },
                headerActions: { headerActions },
                showBackButton: true,
                showHamburgerMenu: false,
                title: isEditing
                    ? L10n.FaceAuth.quickAccessUsersDeleteTitle
                    : L10n.FaceAuth.quickAccessUsersTitle,
                headerActionsBackground: appColors.primaryBackground,
                backgroundColor: appColors.primaryBackground
            )

            // Add User owns the bottom slot normally; in edit mode the
            // Cancel/Delete pair takes it over.
            if isEditing {
                editModeBottomBar
            } else {
                VStack {
                    Spacer()
                    FaceAuthActionButton(
                        title: L10n.FaceAuth.quickAccessUsersAddUser,
                        isPrimary: true
                    ) {
                        showAddUser = true
                    }
                    .padding(.bottom, 30)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .customPopup(isPresented: $showDeleteConfirm) {
            ConfirmationDialogue(
                title: L10n.FaceAuth.quickAccessUsersDeleteTitle,
                message: L10n.FaceAuth.quickAccessUsersDeleteMessage,
                cancelButtonText: L10n.Common.cancel,
                confirmButtonText: L10n.Common.delete
            ) {
                showDeleteConfirm = false
            } onConfirm: {
                deleteSelected()
                showDeleteConfirm = false
            }
        }
        .fullScreenCover(isPresented: $showAddUser) {
            // Reached only from the populated list, so the setup pitch is
            // always skipped here — the flow opens on the name form. The
            // enrollment view shows its own "Face enrolled" screen (with
            // Add User / Done); this presenter just refreshes behind it.
            FaceEnrollmentView(showsIntro: false, onEnrolled: { _ in
                reload()
            })
            .environmentObject(appColors)
        }
    }

    // MARK: - HEADER

    @ViewBuilder
    private var headerActions: some View {
        if isEditing {
            editModeHeader
        } else if !rows.isEmpty {
            Button {
                withAnimation {
                    isEditing = true
                    selectedIds.removeAll()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundColor(appColors.primary)
            }
            .padding(.trailing, 16)
            .transition(.opacity)
        }
    }

    /// Select-all control, same asset pair and placement the scan-detail grid
    /// uses in edit mode.
    private var editModeHeader: some View {
        HStack(spacing: 10) {
            Image(areAllSelected ? "icon_selected" : "icon_unselected")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(appColors.primary)

            Text(areAllSelected ? L10n.Common.unselectAll : L10n.Common.selectAll)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(appColors.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleSelectAll() }
        .padding(.trailing, 16)
        .transition(.opacity)
    }

    // MARK: - EDIT MODE BOTTOM BAR

    private var editModeBottomBar: some View {
        VStack {
            Spacer()

            EqualWidthHStackButtons(spacing: 16) {
                PillCountingButton(
                    title: L10n.Common.cancel,
                    textColor: appColors.primary,
                    backgroundColor: .clear,
                    borderColor: appColors.primary,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: exitEditMode
                )

                PillCountingButton(
                    title: L10n.Common.delete,
                    textColor: selectedIds.isEmpty ? .white.opacity(0.6) : .white,
                    backgroundColor: selectedIds.isEmpty ? Color.gray.opacity(0.4) : appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 14, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 32,
                    verticalPadding: 14,
                    iconSize: 0,
                    action: { showDeleteConfirm = true }
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

    // MARK: - CONTENT

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack {
                Spacer()
                Text(L10n.FaceAuth.quickAccessUsersEmpty)
                    .foregroundStyle(appColors.text.opacity(0.6))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 65)
            .background(appColors.primaryBackground)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(rows) { row in
                        userRow(row)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                // Clears whichever control owns the bottom slot.
                .padding(.bottom, isEditing ? 100 : 90)
            }
            .padding(.top, 65)
            .background(appColors.primaryBackground)
            .animation(.spring(), value: isEditing)
        }
    }

    /// Display edge of the enrollment thumbnail. Kept at 64 so the row holds
    /// its existing 84pt height and the toggle stays where it is.
    private static let avatarSize: CGFloat = 64

    @ViewBuilder
    private func avatarView(_ row: Row) -> some View {
        if let avatar = row.avatar {
            Image(uiImage: avatar)
                .resizable()
                // Fill then clip, so a crop that isn't perfectly square is
                // cropped rather than squashed.
                .scaledToFill()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .clipped()
                .cornerRadius(8)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .foregroundStyle(appColors.text.opacity(0.3))
        }
    }

    private func userRow(_ row: Row) -> some View {
        HStack(spacing: 16) {
            avatarView(row)

            // Equal spacing above/below the divide between the two lines, so
            // the block reads as one centred pair rather than a name with a
            // caption hung off it.
            VStack(alignment: .leading, spacing: 8) {
                Text(row.name)
                    .foregroundColor(appColors.text)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if let lastUsed = row.lastUsed {
                    Text(String(format: L10n.FaceAuth.quickAccessUsersLastUsed, Self.lastUsedFormatter.string(from: lastUsed)))
                        .foregroundColor(appColors.text.opacity(0.6))
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Same control and sizing as the Settings rows, so the toggle
            // looks identical everywhere it appears.
            PillCountingToggleButton(
                isOn: Binding(
                    get: { row.isActive },
                    set: { toggleActive(row.id, isActive: $0) }
                ),
                onColor: appColors.primary
            )
            .scaleEffect(0.8)
            // In edit mode the row belongs to selection, not to toggling.
            .allowsHitTesting(!isEditing)
            .opacity(isEditing ? 0.5 : 1)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(minHeight: 84)
        .background(appColors.secondaryBackground)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        // Same selection affordance as the scan-detail grid cards — a glow
        // and slight inset, no checkbox.
        .selectableEffect(isSelected: selectedIds.contains(row.id), highlightColor: appColors.secondary)
        .animation(.easeInOut(duration: 0.15), value: selectedIds.contains(row.id))
        .contentShape(Rectangle())
        .onTapGesture {
            // Outside edit mode a row tap is inert — nothing here is worth
            // arming by accident.
            if isEditing {
                toggleSelection(row.id)
            }
        }
    }

    // MARK: - ACTIONS

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func toggleSelectAll() {
        if areAllSelected {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(rows.map(\.id))
        }
    }

    private func exitEditMode() {
        withAnimation {
            isEditing = false
            selectedIds.removeAll()
        }
    }

    private func toggleActive(_ id: String, isActive: Bool) {
        if isActive {
            FaceUserStore.shared.activateUser(id: id)
        } else {
            FaceUserStore.shared.deactivateUser(id: id)
        }
        reload()
        // Deactivating everyone leaves nothing for a scan to match, same dead
        // end as deleting everyone.
        FaceSessionManager.shared.releaseLockIfNoUsersEnrolled()
    }

    private func deleteSelected() {
        for id in selectedIds {
            // Through the repository rather than the two stores directly, so
            // embeddings AND the avatar file are cleaned up in one place
            // instead of every caller having to remember the full set.
            FaceRecognitionRepository.shared.deleteUser(id: id)
        }
        exitEditMode()
        reload()
        // Deleting the last enrolled user would otherwise leave the session
        // lock armed with nothing that could ever satisfy it.
        FaceSessionManager.shared.releaseLockIfNoUsersEnrolled()
    }

    private func reload() {
        let users = FaceUserStore.shared.getAllUsers(activeOnly: false)
        rows = users.compactMap { user -> Row? in
            guard let id = user.id, let name = user.name else { return nil }
            return Row(
                id: id,
                name: name,
                lastUsed: user.last_authenticated_at,
                isActive: user.is_active,
                avatar: FaceAvatarStore.shared.loadImage(filename: user.photo_path)
            )
        }
        // Nothing left to edit — don't strand the header in edit mode.
        if rows.isEmpty && isEditing {
            isEditing = false
            selectedIds.removeAll()
        }
    }
}

#Preview {
    QuickAccessUsersView()
        .environmentObject(AppColors.shared)
        .environmentObject(Router())
}
