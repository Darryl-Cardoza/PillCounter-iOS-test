//
//  FaceRegisteredUsersView.swift
//  PillCounter
//
//  Diagnostic list of enrolled face users — name, id, embedding count, avg
//  quality score, enrollment date. NEVER shows embedding vector values
//  (biometric PII) — only counts/metadata, matching the same restriction
//  enforced everywhere else in FaceAuth (spec: "Do not expose embedding
//  values").
//

import SwiftUI

struct FaceRegisteredUsersView: View {

    @EnvironmentObject private var appColors: AppColors
    @State private var rows: [Row] = []
    @State private var pendingDelete: Row?

    private struct Row: Identifiable {
        let id: String
        let name: String
        let embeddingCount: Int
        let averageQuality: Float
        let createdAt: Date?
        let isActive: Bool
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Text(L10n.FaceAuth.registeredUsersEmpty)
                    .foregroundStyle(appColors.text.opacity(0.6))
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.name)
                                .font(.headline)
                                .foregroundStyle(appColors.text)
                            if !row.isActive {
                                Text(L10n.FaceAuth.registeredUsersInactive)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(String(format: L10n.FaceAuth.registeredUsersEmbeddingCount, row.embeddingCount))
                            .font(.caption)
                            .foregroundStyle(appColors.text.opacity(0.7))
                        Text(String(format: L10n.FaceAuth.registeredUsersAvgQuality, row.averageQuality))
                            .font(.caption)
                            .foregroundStyle(appColors.text.opacity(0.7))
                        if let createdAt = row.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(appColors.text.opacity(0.5))
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = row
                        } label: {
                            Label(L10n.FaceAuth.registeredUsersDelete, systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.FaceAuth.registeredUsersTitle)
        .onAppear(perform: reload)
        .alert(
            L10n.FaceAuth.registeredUsersDeleteConfirmTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { row in
            Button(L10n.FaceAuth.registeredUsersDelete, role: .destructive) {
                FaceRecognitionRepository.shared.deleteUser(id: row.id)
                reload()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: { _ in
            Text(L10n.FaceAuth.registeredUsersDeleteConfirmMessage)
        }
    }

    private func reload() {
        let users = FaceUserStore.shared.getAllUsers(activeOnly: false)
        rows = users.compactMap { user -> Row? in
            guard let id = user.id, let name = user.name else { return nil }
            let embeddings = FaceEmbeddingStore.shared.getEmbeddingsForUser(userId: id)
            let avgQuality = embeddings.isEmpty
                ? 0
                : embeddings.reduce(Float(0)) { $0 + $1.quality_score } / Float(embeddings.count)
            return Row(
                id: id, name: name, embeddingCount: embeddings.count,
                averageQuality: avgQuality, createdAt: user.created_at, isActive: user.is_active
            )
        }
        Log("RegisteredUsers: loaded \(rows.count) user(s), total embeddings: \(rows.reduce(0) { $0 + $1.embeddingCount })")
    }
}
