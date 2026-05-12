//
//  HistoryTransactionDetailView.swift
//  PillCounter
//
//  Created by HC on 18/11/25.
//

//
//  HistoryTransactionDetailView.swift
//  PillCounter
//
//  Features/History/Presentation/View/HistoryTransactionDetailView.swift
//

import CoreData
import SwiftUI

struct HistoryTransactionDetailView: View {

    // MARK: - Environment
    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var historyViewModel: HistoryViewModel

    // MARK: - Local State
    @StateObject private var pdfService = PDFShareService.shared
    @State private var fullScreenImage: Image?

    /// Resolved once in .onAppear, kept locally so the view doesn't re-resolve on every render.
    @State private var transaction: PillCountTransactionEntity? = nil

    // MARK: - Body
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    GeometryReader { _ in
                        maintContent
                    }
                },
                bottomContent: { EmptyView() },
                headerActions: {
                    Button { generateAndSharePDF() } label: {
                        Image("pdf")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .overlay { appColors.primary }
                            .mask(Image("pdf").resizable().scaledToFit())
                            .padding(.trailing)
                    }
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: transaction?.drug?.drug_name ?? "Unknown Drug"
            )

            if pdfService.isLoading {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    PillCountingLoader()
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { fullScreenImage != nil },
                set: { if !$0 { fullScreenImage = nil } }
            )
        ) {
            if let image = fullScreenImage {
                FullScreenImageView(image: image) {
                    fullScreenImage = nil
                }
            }
        }
        .onAppear {
            guard let id = historyViewModel.selectedTransactionId else { return }

            // Resolve the entity and immediately prepare step details
            if let txn = historyViewModel.filteredTransactionsOfUserByDate
                .first(where: { $0.txn_id == id })
            {
                transaction = txn
                historyViewModel.prepareDetails(for: txn)
            }
        }
        .onDisappear {
            transaction = nil
            historyViewModel.clearSelectedTransaction()
        }
    }

   

    // MARK: - Portrait Layout
    private var maintContent: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    VStack(spacing: 24) {
                        collapsibleSections
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 80)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)

                    HStack {
                        Spacer()
                        DeleteOkButtons(
                            appColors: appColors,
                            onDelete: {
                                Task {
                                    await historyViewModel.softDeleteTransaction(
                                        txnId: transaction?.txn_id ?? 0
                                    )
                                    router.navigateBack()
                                }
                            },
                            onOk: {
                                router.navigateBack()
                            }
                        )
                        Spacer()
                    }
                    .padding(.top, -60)
                }
                .padding(.top, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appColors.secondaryBackground)
            }
        }
    }

    // MARK: - PDF
    private func generateAndSharePDF() {
        guard let txn = transaction,
              let vc = UIApplication.shared.topMostViewController()
        else { return }

        PDFShareService.shared.generateAndShareDrugHistoryPDF(
            drugName: txn.drug?.drug_name ?? "",
            totalCount: historyViewModel.getTotalPillCount(for: txn, step: .targetVerification),
            ndc: txn.drug?.ndc ?? "N/A",
            expiry: txn.expiry ?? "N/A",
            lotNo: txn.lot_no ?? "N/A",
            date: Formatter.getDateString(from: txn.created_at),
            time: Formatter.getTimeString(from: txn.created_at),
            note: txn.note,
            presentingVC: vc
        )
    }
}


extension HistoryTransactionDetailView {
    
    // MARK: - Collapsible Sections
    private var collapsibleSections: some View {
        VStack(spacing: 10) {

//            if let details = historyViewModel.detailsByStep[.targetVerification],
//               !details.isEmpty,
//               transaction?.is_from_pms == false
//            {
//                CollapsibleBox(
//                    title: NSLocalizedString("PILL COUNT", comment: ""),
//                    allowCollapse: false,
//                    defaultExpanded: true
//                ) {
//                    collapsableBoxContent(step: .targetVerification)
//                }
//            }

            if let details = historyViewModel.detailsByStep[.containerInitiate],
               !details.isEmpty
            {
                CollapsibleBox(
                    title: NSLocalizedString("INITIAL CONTAINER COUNT", comment: ""),
                    allowCollapse: false,
                    defaultExpanded: true
                ) {
                    collapsableBoxContent(step: .containerInitiate, showTargetCount: false)
                }
            }

            CollapsibleBox(title: NSLocalizedString("SUBSTITUTED DRUG DETAILS", comment: "")) {
                detailsInfoList
            }

            if let details = historyViewModel.detailsByStep[.targetVerification],
               !details.isEmpty
            {
                CollapsibleBox(title: NSLocalizedString("PILL COUNT", comment: "")) {
                    collapsableBoxContent(step: .targetVerification)
                }
            }

            if let details = historyViewModel.detailsByStep[.targetReverification],
               !details.isEmpty
            {
                CollapsibleBox(title: NSLocalizedString("PILL RECOUNT", comment: "")) {
                    collapsableBoxContent(step: .targetReverification)
                }
            }

            if let details = historyViewModel.detailsByStep[.vial],
               !details.isEmpty
            {
                CollapsibleBox(title: NSLocalizedString("DISPENSED VIAL", comment: "")) {
                    collapsableBoxContent(step: .vial, showVialInfo: true)
                }
            }

            if let details = historyViewModel.detailsByStep[.containerPending],
               !details.isEmpty
            {
                CollapsibleBox(title: NSLocalizedString("REMAINING_CONTAINER_COUNT", comment: "")) {
                    collapsableBoxContent(step: .containerPending, showTargetCount: false)
                }
            }

            CollapsibleBox(title: NSLocalizedString("NOTE", comment: "")) {
                notesContent
            }
        }
    }

    // MARK: - Collapsible Box Content
    private func collapsableBoxContent(
        step: ControlledStep,
        showTargetCount: Bool = true,
        showVialInfo: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            if !showVialInfo {
                HStack(spacing: 20) {
                    ThumbnailImageView(
                        imagePath: transaction?.barcode_image,
                        width: 140,
                        height: 100,
                        cornerRadius: 12,
                        placeholderImageName: "placeholder_history",
                        placeholderSize: CGSize(width: 20, height: 20)
                    )
                    .onTapGesture {
                        if let path = transaction?.barcode_image,
                           let loaded = PhotoFileManager.shared.loadImage(from: path) {
                            fullScreenImage = loaded
                        }
                    }
                    .environmentObject(appColors)

                    Spacer()

                    VStack {
                        if showTargetCount {
                            // Counted / Target
                            Text("\(historyViewModel.getTotalCount(step: step))")
                                .foregroundStyle(appColors.secondary)
                                .font(.system(size: 25, weight: .bold))
                                .padding(.bottom, -6)

                            Rectangle()
                                .fill(appColors.secondary)
                                .frame(width: 50, height: 2)

                            Text("\(transaction?.target_count ?? 0)")
                                .foregroundStyle(appColors.secondary)
                                .font(.system(size: 25, weight: .bold))
                                .padding(.top, -6)
                                .padding(.bottom, 3)
                        } else {
                            // Container steps — just total, no fraction
                            if let txn = transaction {
                                Text("\(historyViewModel.getTotalPillCount(for: txn, step: step))")
                                    .foregroundStyle(appColors.secondary)
                                    .font(.system(size: 25, weight: .bold))
                                    .padding(.bottom, 3)
                            }
                        }

                        Text(NSLocalizedString("TOTAL_COUNT", comment: ""))
                            .foregroundStyle(appColors.text)
                            .font(.system(size: 14))
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                }
            }

            // Images grid — reads from historyViewModel.detailsByStep
            ScrollView(.horizontal, showsIndicators: false) {
                batchesGrid(step: step)
            }
        }
    }

    // MARK: - Batches Grid
    // Source of truth: historyViewModel.detailsByStep
    private func batchesGrid(step: ControlledStep) -> some View {
        let details = historyViewModel.detailsByStep[step] ?? []

        return LazyHGrid(rows: [GridItem(.flexible())], spacing: 10) {
            ForEach(details, id: \.txn_details_id) { detail in
                batchItem(detail: detail, step: step)
            }
        }
    }

    // MARK: - Batch Item (single image card)
    private func batchItem(
        detail: PillCountTransactionDetailsEntity,
        step: ControlledStep
    ) -> some View {
        ZStack {
            Group {
                if let path = detail.image_path,
                   let image = PhotoFileManager.shared.loadImage(from: path)
                {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(Color.gray)
                        )
                }
            }
            .onTapGesture {
                if let path = detail.image_path,
                   let loaded = PhotoFileManager.shared.loadImage(from: path) {
                    fullScreenImage = loaded
                }
            }
            if step != .vial {
                Text("\(detail.pill_count)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(appColors.secondary)
                    .clipShape(Circle())
            }
        }
        .frame(width: 120, height: 80)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(appColors.text.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Details Info List
    private var detailsInfoList: some View {
        VStack(spacing: 0) {
            detailRow(
                label: NSLocalizedString("SUBSTITUED_DRUG", comment: ""),
                value: transaction?.drug?.drug_name ?? "N/A"
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: NSLocalizedString("NDC", comment: ""),
                value: transaction?.drug?.ndc ?? "N/A"
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: NSLocalizedString("EXPIRY_NO", comment: ""),
                value: transaction?.expiry ?? "N/A"
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: NSLocalizedString("LOT_NO", comment: ""),
                value: transaction?.lot_no ?? "N/A"
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: NSLocalizedString("DATE", comment: ""),
                value: Formatter.getDateString(from: transaction?.created_at ?? 0)
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: NSLocalizedString("TIME", comment: ""),
                value: Formatter.getTimeString(from: transaction?.created_at ?? 0)
            )
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(appColors.text.opacity(0.6))
                .frame(width: 120, alignment: .leading)
                .padding(.trailing, 20)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(appColors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
    }

    // MARK: - Notes
    private var notesContent: some View {
        Text(transaction?.note ?? "-")
            .font(.system(size: 14))
            .foregroundStyle(appColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeleteOkButtons: View {
    // MARK: - Inputs
    let appColors: AppColors
    let onDelete: () -> Void
    let onOk: () -> Void

    var body: some View {
        EqualWidthHStackButtons(spacing: 16) {

            // DELETE
            PillCountingButton(
                iconName: nil,
                title: "DELETE",
                textColor: appColors.primary,
                backgroundColor: .clear,
                borderColor: appColors.primary,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30,
                horizontalPadding: 32,
                verticalPadding: 14,
                iconSize: 0,
                action: onDelete
            )

            // OK
            PillCountingButton(
                iconName: nil,
                title: "OK",
                textColor: Color.white,
                backgroundColor: appColors.primary,
                borderColor: .clear,
                font: .system(size: 14, weight: .semibold),
                cornerRadius: 30,
                horizontalPadding: 32,
                verticalPadding: 14,
                iconSize: 0,
                action: onOk
            )
        }
    }
}
