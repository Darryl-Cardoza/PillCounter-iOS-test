//
//  QuickAccessUsersView.swift
//  PillCounter
//
//  Hamburger-menu screen listing enrolled face-recognition ("Quick Access")
//  users — name, last-used timestamp, active/inactive toggle, and delete.
//  Pushed via Router like UserHistoryView; does not touch the existing
//  FaceAuthenticationView/FaceEnrollmentView/FaceRegisteredUsersView flows,
//  which remain wired up as-is.
//

import SwiftUI

struct QuickAccessUsersView: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router

    @State private var rows: [Row] = []
    @State private var selectedId: String?
    @State private var showDeleteConfirm: Bool = false
    @State private var showAddUser: Bool = false
    @State private var enrolledUserName: String?

    private struct Row: Identifiable {
        let id: String
        let name: String
        let lastUsed: Date?
        var isActive: Bool
    }

    private static let lastUsedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy HH:mm a"
        return formatter
    }()

    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: { content },
                bottomContent: { EmptyView() },
                headerActions: { headerActions },
                showBackButton: true,
                showHamburgerMenu: false,
                title: L10n.FaceAuth.quickAccessUsersTitle,
                backgroundColor: appColors.primaryBackground
            )

            VStack {
                Spacer()
                PillCountingButton(
                    iconName: nil,
                    title: L10n.FaceAuth.quickAccessUsersAddUser,
                    textColor: .white,
                    backgroundColor: appColors.primary,
                    borderColor: .clear,
                    font: .system(size: 15, weight: .semibold),
                    cornerRadius: 30,
                    horizontalPadding: 36,
                    verticalPadding: 16,
                    iconSize: 0,
                    action: { showAddUser = true }
                )
                .fixedSize()
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: .bottom)

            if let enrolledUserName {
                enrollmentSuccessOverlay(userName: enrolledUserName)
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
            FaceEnrollmentView(onEnrolled: { name in
                reload()
                withAnimation(.easeInOut(duration: 0.25)) {
                    enrolledUserName = name
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        enrolledUserName = nil
                    }
                }
            })
            .environmentObject(appColors)
        }
        .onAppear(perform: reload)
    }

    // MARK: - SUCCESS OVERLAY

    private func enrollmentSuccessOverlay(userName: String) -> some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.green)

                Text(String(format: L10n.FaceAuth.enrollmentSuccessTitle, userName))
                    .font(.title3.bold())
                    .foregroundStyle(appColors.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(30)
            .background(appColors.secondaryBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 10)
        }
        .transition(.opacity)
    }

    // MARK: - HEADER

    @ViewBuilder
    private var headerActions: some View {
        if !rows.isEmpty {
            Button {
                if selectedId != nil {
                    showDeleteConfirm = true
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundColor(selectedId == nil ? appColors.primary.opacity(0.4) : appColors.primary)
            }
            .disabled(selectedId == nil)
        }
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
                .padding(.bottom, 90)
            }
            .padding(.top, 65)
            .background(appColors.primaryBackground)
        }
    }

    private func userRow(_ row: Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
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

            PillCountingToggleButton(
                isOn: Binding(
                    get: { row.isActive },
                    set: { toggleActive(row.id, isActive: $0) }
                ),
                onColor: appColors.primary
            )
            .scaleEffect(0.7)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 12)
        .background(appColors.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
        .selectableEffect(isSelected: selectedId == row.id, highlightColor: appColors.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedId = selectedId == row.id ? nil : row.id
        }
    }

    // MARK: - ACTIONS

    private func toggleActive(_ id: String, isActive: Bool) {
        if isActive {
            FaceUserStore.shared.activateUser(id: id)
        } else {
            FaceUserStore.shared.deactivateUser(id: id)
        }
        reload()
    }

    private func deleteSelected() {
        guard let id = selectedId else { return }
        FaceEmbeddingStore.shared.deleteEmbeddingsForUser(userId: id)
        FaceUserStore.shared.deleteUser(id: id)
        selectedId = nil
        reload()
    }

    private func reload() {
        let users = FaceUserStore.shared.getAllUsers(activeOnly: false)
        rows = users.compactMap { user -> Row? in
            guard let id = user.id, let name = user.name else { return nil }
            return Row(id: id, name: name, lastUsed: user.last_authenticated_at, isActive: user.is_active)
        }
    }
}

#Preview {
    QuickAccessUsersView()
        .environmentObject(AppColors.shared)
        .environmentObject(Router())
}
