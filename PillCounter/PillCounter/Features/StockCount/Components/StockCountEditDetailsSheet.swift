//
//  StockCountEditDetailsSheet.swift
//  PillCounter
//

import SwiftUI

// MARK: - Editable Lot Row Model

struct EditableLotRow: Identifiable {
    let id = UUID()
    let txnId: Int64
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

    var body: some View {
        dialogPanel
            .onAppear { buildRows() }
    }

    // MARK: - Dialog Panel

    private var dialogPanel: some View {
        VStack(spacing: 0) {
            dialogHeader
            Divider()
            if isIPad && isLandscape {
                landscapeContent
            } else {
                portraitContent
            }
            Divider()
            dialogFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appColors.secondaryBackground)
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
                    .foregroundColor(appColors.text.opacity(0.5))
                    .frame(width: 32, height: 32)
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
                openPillsSection
            }
            .padding(20)
        }
    }

    private var portraitContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                drugInfoSection
                sealedBottlesSection
                openPillsSection
            }
            .padding(20)
        }
    }

    // MARK: - Drug Info Section

    private var drugInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.StockCountSheet.scannedDrugDetails)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(label: L10n.StockCountSheet.drugName, value: txn.drugName, valueColor: appColors.secondary)
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    infoCell(label: L10n.StockCountSheet.ndcNumber, value: txn.ndc, valueColor: appColors.secondary)
                    infoCell(label: L10n.StockCountSheet.bucket, value: (stockCountViewModel.currentBatch?.bucket_id ?? "NORMAL").uppercased(), valueColor: appColors.secondary)
                }
            }
            .padding(16)
            .background(appColors.primaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Sealed Bottles Section

    private var sealedBottlesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel(L10n.StockCountSheet.sealedBottles)
                Spacer()
                Text("\(lotRows.reduce(0) { $0 + $1.sealedBottles })")
                    .font(.system(size: 14, weight: .bold))
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
        HStack(spacing: 0) {
            Text(L10n.StockCountSheet.batchNo)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.StockCountSheet.expiryDate)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: 130)
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundColor(appColors.text.opacity(0.45))
        .padding(.horizontal, 4)
    }

    private func sealedLotRow(row: Binding<EditableLotRow>) -> some View {
        HStack(spacing: 0) {
            Text(row.wrappedValue.lot.isEmpty ? "—" : row.wrappedValue.lot)
                .font(.system(size: 14))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.wrappedValue.expiry.isEmpty ? "—" : row.wrappedValue.expiry)
                .font(.system(size: 14))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            inlineStepper(value: row.sealedBottles, minValue: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(appColors.primaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Open Pills Section

    private var openPillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel(L10n.StockCountSheet.openPills)
                Spacer()
                Text("\(lotRows.reduce(0) { $0 + $1.openPills })")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(appColors.secondary)
            }

            // Column header
            lotColumnHeader()

            // Rows
            ForEach($lotRows) { $row in
                openPillsLotRow(row: $row)
            }
        }
    }

    private func openPillsLotRow(row: Binding<EditableLotRow>) -> some View {
        HStack(spacing: 0) {
            Text(row.wrappedValue.lot.isEmpty ? "—" : row.wrappedValue.lot)
                .font(.system(size: 14))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.wrappedValue.expiry.isEmpty ? "—" : row.wrappedValue.expiry)
                .font(.system(size: 14))
                .foregroundColor(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            inlineStepper(value: row.openPills, minValue: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(appColors.primaryBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(value.wrappedValue > minValue ? appColors.primary : appColors.primary.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .background(appColors.primaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(appColors.secondary)
                .frame(width: 52, height: 36)
                .background(appColors.secondaryBackground)

            Button(action: {
                value.wrappedValue += 1
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(appColors.primary)
                    .frame(width: 36, height: 36)
                    .background(appColors.primaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: 130)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Helper Views

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(appColors.secondary)
    }

    private func infoRow(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(appColors.text.opacity(0.42))
            Text(value)
                .font(.system(size: 15, weight: .semibold))
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
