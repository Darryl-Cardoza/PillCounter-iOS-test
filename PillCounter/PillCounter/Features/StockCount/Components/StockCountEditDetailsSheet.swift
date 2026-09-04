//
//  StockCountEditDetailsSheet.swift
//  PillCounter
//

import SwiftUI

// MARK: - Editable Lot Row Model

/// Which section a lot-row delete (trash) action targets.
enum LotField {
    case sealed   // bottle_qty
    case open     // loose_qty
}

struct EditableLotRow: Identifiable {
    let id = UUID()
    let bottleIds: [Int64]        // all BottleInfoEntity rows in this lot group (sealed row is alone; opened rows share a lot)
    var lot: String
    var expiry: String
    var sealedBottles: Int        // editable
    var openPills: Int            // editable
    let packageQty: Int32
    let field: LotField           // which section this row belongs to — sealed and open never share a row
}

// MARK: - Edit Details Sheet

struct StockCountEditDetailsSheet: View {

    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var stockCountViewModel: StockCountViewModel

    let txn: GroupedTransaction
    let onDismiss: () -> Void
    /// When true the panel hugs its content height (used as a docked
    /// full-width bottom card on iPad portrait) instead of filling.
    var hugContentHeight: Bool = false

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
                dialogFooter
                    .background(appColors.secondaryBackground)
            } else {
                portraitContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: hugContentHeight ? nil : .infinity, alignment: .top)
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
        .padding(.vertical, isLandscape ? 16 : 0 )
        .padding(.leading, isLandscape ? 0: 16)
        .padding(.top, isLandscape ? nil : 16)

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
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    portraitDrugInfoSection
                    sealedBottlesSection
                    openPillsSection
                }
                .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
            }
            // When hugging (iPad-portrait docked card), let the ScrollView size to
            // its content so a short list yields a short card. The parent caps the
            // overall height (maxHeight 85%), so a long list is clipped here and
            // scrolls internally instead of pushing the card off-screen.
            // When filling (iPhone / landscape), expand to claim all space.
            .frame(maxHeight: hugContentHeight ? nil : .infinity)

            // Sticky footer: sits inside the card, pinned to the bottom, and
            // does not scroll with the lot list above.
            HStack {
                Spacer()
                dialogFooter
                Spacer()
            }
        }
        .background(appColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
    }

    // MARK: - Drug Info Section
    private var drugInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel(L10n.StockCountSheet.scannedDrugDetails, appColors.text)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(label: L10n.StockCountSheet.drugName, value: txn.drugName, valueColor: appColors.secondary)
                Divider()
                HStack(alignment: .top) {
                    infoCell(label: L10n.StockCountSheet.ndcNumber, value: txn.ndc, valueColor: appColors.secondary)
                    infoCell(label: L10n.StockCountSheet.bucket, value: (stockCountViewModel.currentBatch?.bucket_id ?? "NORMAL").uppercased(), valueColor: appColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
                Divider()
            }
        }
    }

    // MARK: - Drug Info Section (Portrait)
    /// iPad-portrait variant: Drug Name / NDC / Bucket laid out as a single
    /// horizontal 3-column row beneath the section label, matching the mockup.
    private var portraitDrugInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.StockCountSheet.scannedDrugDetails)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: columnGap) {
                infoCell(label: L10n.StockCountSheet.drugName, value: txn.drugName, valueColor: appColors.secondary)
                infoCell(label: L10n.StockCountSheet.ndcNumber, value: txn.ndc, valueColor: appColors.secondary)
                infoCell(label: L10n.StockCountSheet.bucket, value: (stockCountViewModel.currentBatch?.bucket_id ?? "NORMAL").uppercased(), valueColor: appColors.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()
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

            // Rows — sealed rows only, and only while the count is still > 0
            // (a zeroed row is dropped from view entirely, not shown as an editable 0).
            ForEach($lotRows) { $row in
                if row.field == .sealed && row.sealedBottles > 0 {
                    sealedLotRow(row: $row)
                }
            }
        }
    }

    private func lotColumnHeader() -> some View {
        HStack(spacing: columnGap) {
            Text(L10n.StockCountSheet.batchNo)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.StockCountSheet.expiryDate)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Mirror the row layout: reserve the stepper width, then a spacer
            // pushes the delete column to the trailing edge.
            Color.clear.frame(width: stepperWidth, height: 0)
            Spacer(minLength: columnGap)
            Color.clear.frame(width: deleteWidth, height: 0)
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundColor(appColors.text.opacity(0.45))
    }

    private func sealedLotRow(row: Binding<EditableLotRow>) -> some View {
        lotRow(row: row, value: row.sealedBottles, field: .sealed)
    }

    // Shared row used by both sections — keeps spacing/alignment identical.
    private func lotRow(row: Binding<EditableLotRow>, value: Binding<Int>, field: LotField) -> some View {
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

            Spacer()

            deleteButton(for: row.wrappedValue.id, field: field)
        }
    }

    private func deleteButton(for rowId: UUID, field: LotField) -> some View {
        Button(action: { deleteRow(rowId, field: field) }) {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(appColors.primary)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Open Pills Section

    private var openPillsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                sectionLabel(L10n.StockCountSheet.openPills)
                Spacer()
                Text("\(lotRows.reduce(0) { $0 + $1.openPills })")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appColors.secondary)
            }

            // Column header
            lotColumnHeader()

            // Rows — open rows only, and only while the count is still > 0
            // (a zeroed row is dropped from view entirely, not shown as an editable 0).
            ForEach($lotRows) { $row in
                if row.field == .open && row.openPills > 0 {
                    lotRow(row: $row, value: $row.openPills, field: .open)
                }
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
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 10,
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
                        bottomTrailingRadius: 10,
                        topTrailingRadius: 10,
                        style: .continuous
                    ))
            }
        }
        .frame(width: stepperWidth)
    }

    // MARK: - Footer
    private var dialogFooter: some View {
        EqualWidthHStackButtons(spacing: 16) {
            PillCountingButton(
                iconName: nil, title: L10n.Common.cancel,
                textColor: appColors.primary, backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: onDismiss
            )
            PillCountingButton(
                iconName: nil, title: L10n.Common.save,
                textColor: .white, backgroundColor: appColors.primary, borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30, horizontalPadding: 32, verticalPadding: 14, iconSize: 0,
                action: saveChanges
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Helper Views

    private func sectionLabel(_ text: String, _ color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color ?? appColors.secondary)
    }
    
    private func infoRow(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(appColors.text)
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

        guard let batchId = stockCountViewModel.currentBatch?.batch_id,
              let stockTxn = stockCountViewModel.stockTxnDAO.fetchByBatchAndNdc(batchId: batchId, ndc: txn.ndc) else { return }

        let bottles = stockCountViewModel.bottleInfoDAO.fetchByStockTxn(stockTxnId: stockTxn.stock_txn_id)
        let pkgQty = stockTxn.drug?.package_qty ?? 0

        var rows: [EditableLotRow] = []

        // Sealed rows group by lot|expiry, same as opened rows — a StockTxn can now have
        // multiple sealed rows (one per distinct lot/exp), not just one.
        let sealedBottleRows = bottles.filter { $0.isSealed }
        let sealedGrouped = Dictionary(grouping: sealedBottleRows) { $0.sealedLotKey }
        for (_, lotBottles) in sealedGrouped {
            guard let first = lotBottles.first else { continue }
            let sealedQty = lotBottles.reduce(0) { $0 + Int($1.bottle_qty) }
            guard sealedQty > 0 else { continue }
            rows.append(EditableLotRow(
                bottleIds: lotBottles.map { $0.bottle_id },
                lot: first.lot_no ?? "",
                expiry: first.exp_no ?? "",
                sealedBottles: sealedQty,
                openPills: 0,
                packageQty: pkgQty,
                field: .sealed
            ))
        }

        // Opened rows group by lot|expiry — never merged with sealed rows even when the
        // lot/exp matches (each scan stays its own DB row; only the display is combined).
        let openedRows = bottles.filter { !$0.isSealed }
        let openedGrouped = Dictionary(grouping: openedRows) { $0.sealedLotKey }
        for (_, lotBottles) in openedGrouped {
            guard let first = lotBottles.first else { continue }
            let openPills = lotBottles.reduce(0) { $0 + Int($1.loose_qty) }
            guard openPills > 0 else { continue }
            rows.append(EditableLotRow(
                bottleIds: lotBottles.map { $0.bottle_id },
                lot: first.lot_no ?? "",
                expiry: first.exp_no ?? "",
                sealedBottles: 0,
                openPills: openPills,
                packageQty: pkgQty,
                field: .open
            ))
        }

        // Sort by lot for stable ordering
        lotRows = rows.sorted { $0.lot < $1.lot }
    }

    private func deleteRow(_ rowId: UUID, field: LotField) {
        guard let idx = lotRows.firstIndex(where: { $0.id == rowId }) else { return }
        let row = lotRows[idx]
        // Don't delete the rows — just zero out the tapped section's count.
        // Sealed trash zeroes only bottle_qty; open-pills trash zeroes only loose_qty.
        for bottleId in row.bottleIds {
            stockCountViewModel.bottleInfoDAO.setAbsolute(
                bottleId: bottleId,
                bottleQty: field == .sealed ? 0 : nil,
                looseQty:  field == .open   ? 0 : nil
            )
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            switch field {
            case .sealed: lotRows[idx].sealedBottles = 0
            case .open:   lotRows[idx].openPills = 0
            }
        }
    }

    private func saveChanges() {
        for row in lotRows {
            // A lot row aggregates the counts of every bottle row in the group (see
            // buildRows — both sealed and opened rows are now grouped by lot|expiry and
            // summed across bottleIds). Writing that summed value onto only the first row
            // while leaving siblings at their original counts would inflate the NDC-wide
            // total on the next reload. Collapse the group: put the edited totals on the
            // primary row and zero the rest, so the saved group total equals exactly what
            // the user sees.
            let primaryBottleId = row.bottleIds.first
            for bottleId in row.bottleIds {
                let isPrimary = bottleId == primaryBottleId
                stockCountViewModel.bottleInfoDAO.setAbsolute(
                    bottleId: bottleId,
                    bottleQty: isPrimary ? Int32(row.sealedBottles) : 0,
                    looseQty:  isPrimary ? Int32(row.openPills)     : 0
                )
            }
        }
        // Counts were written straight to the DAO — pull them back into the detail
        // card's stepper state so it reflects the edit instead of the stale scan value.
        stockCountViewModel.resyncScannedDrugCounts()
        onDismiss()
    }
}
