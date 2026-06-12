//
//  StockCountEditDetailsSheet.swift
//  PillCounter
//

import SwiftUI

// MARK: - Editable Lot Row Model

struct EditableLotRow: Identifiable {
    let id = UUID()
    let txnId: Int64
    let txnIds: [Int64]           // all transactions in this lot group
    var lot: String
    var expiry: String
    var sealedBottles: Int        // editable
    var openPills: Int            // editable
    let packageQty: Int32
}

// MARK: - Edit Details Sheet

struct StockCountEditDetailsSheet: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let txn: GroupedTransaction
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass)   private var vSizeClass

    private var isIPad: Bool { hSizeClass == .regular && vSizeClass == .regular }
    private var isLandscape: Bool { UIScreen.main.bounds.width > UIScreen.main.bounds.height }

    @State private var lotRows: [EditableLotRow] = []
    @State private var isInitialized = false

    // Shared layout metrics so headers and rows line up exactly.
    private let stepperWidth: CGFloat = 160
    private let deleteWidth: CGFloat = 44
    private let columnGap: CGFloat = 12

    var body: some View {
        dialogPanel
            .onAppear { buildRows() }
    }

    // MARK: - Dialog Panel

    private var dialogPanel: some View {
        VStack(spacing: 0) {
            dialogHeader
            if isIPad && isLandscape {
                landscapeContent
            } else {
                portraitContent
            }
            dialogFooter
                .background(appColors.secondaryBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.primaryBackground)
    }

    // MARK: - Header

    private var dialogHeader: some View {
        HStack {
            Text(L10n.StockCountSheet.editDetails)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appColors.text)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(appColors.primary)
                    .frame(width: 40, height: 40)
                    .background(appColors.primaryBackground)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Layouts
    private var landscapeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                drugInfoSection
                sealedBottlesSection
                Divider()
                openPillsSection
            }
            .padding(20)
        }
        .background(appColors.secondaryBackground)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 16,
            style: .continuous
        ))
        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: -4, y: -6)
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: -12)
    }

    private var portraitContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                drugInfoSection
                sealedBottlesSection
                openPillsSection
            }
            .padding(20)
        }
    }

    // MARK: - Drug Info Section
    private var drugInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel(L10n.StockCountSheet.scannedDrugDetails)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(label: L10n.StockCountSheet.drugName, value: txn.drugName, valueColor: appColors.secondary)
                Divider()
                HStack(alignment: .top) {
                    infoCell(label: L10n.StockCountSheet.ndcNumber, value: txn.ndc, valueColor: appColors.secondary)
                    Spacer()
                    infoCell(label: L10n.StockCountSheet.bucket, value: (stockCountViewModel.currentBatch?.bucket_id ?? "NORMAL").uppercased(), valueColor: appColors.secondary)
                }.frame(maxWidth: .infinity)
                Divider()
            }
        }
    }

    // MARK: - Sealed Bottles Section

    private var sealedBottlesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                sectionLabel(L10n.StockCountSheet.sealedBottles)
                Spacer()
                Text("\(lotRows.reduce(0) { $0 + $1.sealedBottles })")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appColors.secondary)
            }

            // Column header
            lotColumnHeader()

            // Rows
            ForEach($lotRows) { $row in
                sealedLotRow(row: $row)
            }
        }
    }

    private func lotColumnHeader() -> some View {
        HStack(spacing: columnGap) {
            Text(L10n.StockCountSheet.batchNo)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.StockCountSheet.expiryDate)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Reserve the exact trailing area used by the stepper + delete icon.
            Color.clear.frame(width: stepperWidth + columnGap + deleteWidth, height: 0)
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundColor(appColors.text.opacity(0.45))
    }

    private func sealedLotRow(row: Binding<EditableLotRow>) -> some View {
        lotRow(row: row, value: row.sealedBottles)
    }

    // Shared row used by both sections — keeps spacing/alignment identical.
    private func lotRow(row: Binding<EditableLotRow>, value: Binding<Int>) -> some View {
        HStack(spacing: columnGap) {
            Text(row.wrappedValue.lot.isEmpty ? "—" : row.wrappedValue.lot)
                .font(.system(size: 15))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.wrappedValue.expiry.isEmpty ? "—" : row.wrappedValue.expiry)
                .font(.system(size: 15))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            inlineStepper(value: value, minValue: 0)

            deleteButton(for: row.wrappedValue.id)
        }
    }

    private func deleteButton(for rowId: UUID) -> some View {
        Button(action: { deleteRow(rowId) }) {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(appColors.primary)
                .frame(width: deleteWidth, height: 36)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Open Pills Section

    private var openPillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel(L10n.StockCountSheet.openPills)
                Spacer()
                Text("\(lotRows.reduce(0) { $0 + $1.openPills })")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appColors.secondary)
            }

            // Column header
            lotColumnHeader()

            // Rows
            ForEach($lotRows) { $row in
                lotRow(row: $row, value: $row.openPills)
            }
        }
    }

    // MARK: - Inline Stepper

    private func inlineStepper(value: Binding<Int>, minValue: Int) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                if value.wrappedValue > minValue {
                    value.wrappedValue -= 1
                }
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(value.wrappedValue > minValue ? appColors.primary : appColors.primary.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .background(appColors.primaryBackground)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    ))
            }

            // Read-only count — value changes only via the stepper buttons.
            Text("\(value.wrappedValue)")
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .frame(width: 64, height: 48)
                .background(appColors.secondaryBackground)
                .overlay(
                    Rectangle()
                        .strokeBorder(appColors.primaryBackground, lineWidth: 1)
                )

            Button(action: {
                value.wrappedValue += 1
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appColors.primary)
                    .frame(width: 48, height: 48)
                    .background(appColors.primaryBackground)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 8,
                        style: .continuous
                    ))
            }
        }
        .frame(width: stepperWidth)
    }

    // MARK: - Footer

    private var dialogFooter: some View {
        HStack(spacing: 16) {
            PillCountingButton(
                iconName: nil, title: L10n.Common.cancel,
                textColor: appColors.primary, backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onDismiss
            )
            PillCountingButton(
                iconName: nil, title: L10n.Common.save,
                textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                font: .system(size: 14, weight: .bold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: saveChanges
            )
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 16)
    }

    // MARK: - Helper Views

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(appColors.secondary)
    }

    private func infoRow(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(appColors.text.opacity(0.42))
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(valueColor)
                .lineLimit(1)
        }
    }

    private func infoCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(appColors.text.opacity(0.42))
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Data

    private func buildRows() {
        guard !isInitialized else { return }
        isInitialized = true

        guard let batchId = stockCountViewModel.currentBatch?.batch_id else { return }

        let allTxns = stockCountViewModel.transactionDAO.fetchByBatch(batchId: batchId)
        let ndcTxns = allTxns.filter { $0.drug?.ndc == txn.ndc }

        // Group by lot|expiry key — same logic as the mapper
        let grouped = Dictionary(grouping: ndcTxns) { "\($0.lot_no ?? "")|\($0.expiry ?? "")" }

        var rows: [EditableLotRow] = []
        for (_, lotTxns) in grouped {
            guard let first = lotTxns.first else { continue }
            let pkgQty = first.drug?.package_qty ?? 0
            let sealedBottles = lotTxns.reduce(0) { $0 + Int($1.bottle_qty) }
            let openPills = lotTxns.reduce(0) { $0 + Int($1.loose_qty) }
            rows.append(EditableLotRow(
                txnId: first.txn_id,
                txnIds: lotTxns.map { $0.txn_id },
                lot: first.lot_no ?? "",
                expiry: first.expiry ?? "",
                sealedBottles: sealedBottles,
                openPills: openPills,
                packageQty: pkgQty
            ))
        }

        // Sort by lot for stable ordering
        lotRows = rows.sorted { $0.lot < $1.lot }
    }

    private func deleteRow(_ rowId: UUID) {
        guard let row = lotRows.first(where: { $0.id == rowId }) else { return }
        for txnId in row.txnIds {
            stockCountViewModel.transactionDAO.softDelete(txnId: txnId)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            lotRows.removeAll { $0.id == rowId }
        }
    }

    private func saveChanges() {
        for row in lotRows {
            stockCountViewModel.transactionDAO.setAbsoluteCounts(
                txnId: row.txnId,
                bottleQty: Int32(row.sealedBottles),
                looseQty: Int32(row.openPills)
            )
        }
        onDismiss()
    }
}
