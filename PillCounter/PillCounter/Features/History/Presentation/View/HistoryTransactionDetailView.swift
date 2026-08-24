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
    @EnvironmentObject private var userViewModel: UserViewModel

    // MARK: - Route payload
    /// Passed in via the route. The screen resolves the entity from the store
    /// by this id — it no longer relies on the caller pre-seeding
    /// `historyViewModel.filteredTransactionsOfUserByDate`.
    let txnId: Int64

    // MARK: - Local State
    @StateObject private var pdfService = PDFShareService.shared
    @State private var fullScreenImage: Image?
    @State private var showDeleteConfirmation: Bool = false
    @State private var bottlePage: Int = 0
    
    /// Resolved once in .onAppear, kept locally so the view doesn't re-resolve on every render.
    @State private var transaction: PillCountTransactionEntity? = nil

    private var allBottleBarcodeImagePaths: [String] {
        [BottleInfo].decode(from: transaction?.bottle_info_list_json).compactMap(\.barcodeImagePath)
    }

    private var allBottleInfos: [BottleInfo] {
        [BottleInfo].decode(from: transaction?.bottle_info_list_json)
    }

    /// Controlled drugs (non-empty drug_type) have extra steps: two-column iPad layout applies.
    /// Normal drugs (empty drug_type) only ever show the pill count section.
    private var isControlledFlow: Bool {
        guard let type = transaction?.drug?.drug_type else { return false }
        return !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Pill count / recount steps compare against the transaction's target count.
    private func countText(step: ControlledStep) -> String {
        let total = historyViewModel.getTotalCount(step: step)
        return "\(total)/\(transaction?.target_count ?? 0)"
    }

    /// Container initial/pending steps have no target — just the counted total.
    private func containerCountText(step: ControlledStep) -> String {
        let total = transaction.map { historyViewModel.getTotalPillCount(for: $0, step: step) } ?? 0
        return "\(total)"
    }

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
                    HStack(spacing:16){
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image("delete")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .overlay { appColors.primary }
                                .mask(
                                    Image("delete")
                                        .resizable()
                                        .scaledToFit()
                                )
                        }
                        .padding(.trailing, 10)
                        
                        
//                        Button { generateAndSharePDF() } label: {
//                            Image("pdf")
//                                .resizable()
//                                .scaledToFit()
//                                .frame(width: 30, height: 30)
//                                .overlay { appColors.primary }
//                                .mask(Image("pdf").resizable().scaledToFit())
//                                .padding(.trailing)
//                        }
                    }
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: transaction?.drug?.drug_name ?? L10n.History.unknownDrug,
                backgroundColor: appColors.primaryBackground
            )

            if pdfService.isLoading {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    PillCountingLoader()
                }
            }
        }
        .customPopup(isPresented: $showDeleteConfirmation) {
            ConfirmationDialogue(
                title: L10n.History.confirmDelete,
                message: nil,
                cancelButtonText: L10n.Common.no,
                confirmButtonText: L10n.Common.yes,
                onCancel: {
                    showDeleteConfirmation = false
                },
                onConfirm: {
                    showDeleteConfirmation = false
                    guard let txnId = transaction?.txn_id else { return }
                    Task {
                        await historyViewModel.softDeleteTransaction(txnId: txnId)
                        router.navigateBack()
                    }
                }
            )
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
            // Resolve the entity from the store by id and prepare step details.
            transaction = historyViewModel.prepareDetails(forTxnId: txnId)
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
                        Spacer(minLength: 80)
                    }
                    .padding(.bottom, 40)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .background(appColors.primaryBackground)
            }
        }
        .padding(.top, 64)
    }

    // MARK: - PDF
    private func generateAndSharePDF() {
        guard let txn = transaction,
              let vc = UIApplication.shared.topMostViewController()
        else { return }

        let fname    = userViewModel.firstName
               let lname    = userViewModel.lastName
               let userName = [fname, lname].filter { !$0.isEmpty }.joined(separator: " ")

               let detailsByStep = historyViewModel.detailsByStep.mapValues { details in
                   details.map { (count: $0.pill_count, createdAt: $0.created_at) }
               }

               let input = DrugHistoryPDFInput(
                   drugName:          txn.drug?.drug_name ?? "",
                   ndc:               txn.drug?.ndc ?? "N/A",
                   date:              Formatter.getDateString(from: txn.created_at),
                   time:              Formatter.getTimeString(from: txn.created_at),
                   note:              txn.note,
                   userName:          userName.isEmpty ? nil : userName,
                   targetCount:       txn.target_count,
                   countType:         txn.is_dispense ? "FIXED" : "REGULAR",
                   substituteNdc:     txn.substitueDrug?.ndc,
                   substituteDrugName: txn.substitueDrug?.drug_name,
                   detailsByStep:     detailsByStep
               )

               pdfService.isLoading = true
               DispatchQueue.global(qos: .userInitiated).async {
                   let url = DrugHistoryPDFExporter.export(input: input)
                   DispatchQueue.main.async {
                       pdfService.isLoading = false
                       guard let url else { return }
                       let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                       if let popover = activityVC.popoverPresentationController {
                           popover.sourceView = vc.view
                           popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
                           popover.permittedArrowDirections = []
                       }
                       activityVC.completionWithItemsHandler = { _, _, _, _ in
                           try? FileManager.default.removeItem(at: url)
                       }
                       vc.present(activityVC, animated: true)
                   }
               }
           }
       
}


extension HistoryTransactionDetailView {
    
    private var drugDetailsTitle: String {
        transaction?.is_substitute == true
            ? L10n.History.substitutedDrugDetails
            : L10n.History.dispensedDrugDetails
    }

    // MARK: - Collapsible Sections
    private var collapsibleSections: some View {
        Group {
            if isLandscape {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) { leftColumnSections }
                    VStack(spacing: 10) { rightColumnSections }
                }
            } else {
                VStack(spacing: 10) {
                    leftColumnSections
                    rightColumnSections
                }
            }
        }
    }

    // MARK: - Left Column (requested / container / dispensed drug details)
    @ViewBuilder
    private var leftColumnSections: some View {
        CollapsibleBox(
            title: L10n.History.requestedDrugDetails,
            bgColor: appColors.secondaryBackground
        ) {
            substituedInfoList
        }
        
        CollapsibleBox(
            title: drugDetailsTitle,
            bgColor: appColors.secondaryBackground,
            countText: allBottleInfos.count > 1 ? "\(bottlePage + 1) \(L10n.Common.of) \(allBottleInfos.count)" : nil
        ) {
            VStack(spacing: 0) {
                detailsInfoList
                pageIndicator
            }
        }

        
        CollapsibleBox(title: L10n.Common.note, bgColor: appColors.secondaryBackground) {
            notesContent
        }
        
     
    }

    @ViewBuilder
    private var containerQRCodeBox: some View {
        CollapsibleBox(
            title: L10n.History.containerQrCode,
            allowCollapse: false,
            defaultExpanded: true,
            bgColor: appColors.secondaryBackground
        ) {
            thumbnailScrollRow(paths: allBottleBarcodeImagePaths)
        }
    }

    @ViewBuilder
    private var vialBox: some View {
        if let details = historyViewModel.detailsByStep[.vial], !details.isEmpty {
            CollapsibleBox(
                title: L10n.History.dispensedVial,
                allowCollapse: false,
                defaultExpanded: true,
                bgColor: appColors.secondaryBackground
            ) {
                thumbnailScrollRow(paths: details.compactMap(\.image_path))
            }
        }
    }

    // MARK: - Thumbnail Scroll Row (shared: container QR code, dispensed vial, step images) — same size everywhere, all orientations
    private func thumbnailScrollRow(paths: [String], countBadge: Int? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(paths.isEmpty ? [nil] : paths.map { $0 as String? }, id: \.self) { path in
                    ZStack {
                        ThumbnailImageView(
                            imagePath: path,
                            width: 140,
                            height: 100,
                            cornerRadius: 12,
                            placeholderImageName: "placeholder_history",
                            placeholderSize: CGSize(width: 20, height: 20)
                        )
                        .onTapGesture {
                            if let path, let loaded = PhotoFileManager.shared.loadImage(from: path) {
                                fullScreenImage = loaded
                            }
                        }
                        .environmentObject(appColors)

                        if let countBadge {
                            Text("\(countBadge)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(appColors.secondary)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Right Column (pill count / recount / vial / remaining stock / notes)
    @ViewBuilder
    private var rightColumnSections: some View {
        
        HStack(alignment: .top, spacing: 10) {
            containerQRCodeBox
            vialBox
        }
        
        
        if let details = historyViewModel.detailsByStep[.containerInitiate],
           !details.isEmpty
        {
            CollapsibleBox(
                title: L10n.History.initialContainerCount,
                allowCollapse: false,
                defaultExpanded: true,
                bgColor: appColors.secondaryBackground,
                countText: containerCountText(step: .containerInitiate)
            ) {
                collapsableBoxContent(step: .containerInitiate)
            }
        }
        
        if !isControlledFlow {
            CollapsibleBox(
                title: L10n.History.pillCount,
                allowCollapse: false,
                defaultExpanded: true,
                bgColor: appColors.secondaryBackground,
                countText: countText(step: .targetVerification)
            ) {
                collapsableBoxContent(step: .targetVerification)
            }
        } else {
            CollapsibleBox(
                title: L10n.History.pillCount,
                bgColor: appColors.secondaryBackground,
                countText: countText(step: .targetVerification)
            ) {
                collapsableBoxContent(step: .targetVerification)
            }
        }

        if let details = historyViewModel.detailsByStep[.targetReverification],
           !details.isEmpty
        {
            CollapsibleBox(
                title: L10n.History.pillRecount,
                bgColor: appColors.secondaryBackground,
                countText: countText(step: .targetReverification)
            ) {
                collapsableBoxContent(step: .targetReverification)
            }
        }

        if let details = historyViewModel.detailsByStep[.containerPending],
           !details.isEmpty
        {
            CollapsibleBox(
                title: L10n.History.remainingContainerCount,
                bgColor: appColors.secondaryBackground,
                countText: containerCountText(step: .containerPending)
            ) {
                collapsableBoxContent(step: .containerPending)
            }
        }
    }

    // MARK: - Collapsible Box Content
    // Shows only this step's own images (from historyViewModel.detailsByStep) via the shared thumbnailScrollRow.
    private func collapsableBoxContent(step: ControlledStep) -> some View {
        let details = historyViewModel.detailsByStep[step] ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(details, id: \.txn_details_id) { detail in
                    ZStack {
                        ThumbnailImageView(
                            imagePath: detail.image_path,
                            width: 140,
                            height: 100,
                            cornerRadius: 12,
                            placeholderImageName: "placeholder_history",
                            placeholderSize: CGSize(width: 20, height: 20)
                        )
                        .onTapGesture {
                            if let path = detail.image_path,
                               let loaded = PhotoFileManager.shared.loadImage(from: path) {
                                fullScreenImage = loaded
                            }
                        }
                        .environmentObject(appColors)

                        Text("\(detail.pill_count)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(appColors.secondary)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    // MARK: - Details Info List
    // Drug name/NDC/date/time + per-bottle exp/lot/serial — all swipeable together, one page per scanned bottle.
    private var detailsInfoList: some View {
        let bottles = allBottleInfos.isEmpty ? [nil] : allBottleInfos.map { $0 as BottleInfo? }

        return TabView(selection: $bottlePage) {
            ForEach(Array(bottles.enumerated()), id: \.offset) { index, bottle in
                VStack(spacing: 0) {
                    detailRow(
                        label: transaction?.is_substitute == true ? L10n.History.substitutedDrug : L10n.History.dispensedDrug,
                        value: transaction?.drug?.drug_name ?? "N/A"
                    )
                    Divider().background(appColors.text.opacity(0.1))

                    detailRow(
                        label: L10n.History.ndc,
                        value: transaction?.drug?.ndc ?? "N/A"
                    )
                    Divider().background(appColors.text.opacity(0.1))

                    detailRow(
                        label: L10n.Common.dateTime,
                        value: Formatter.getDateString(from: transaction?.created_at ?? 0) + " " + Formatter.getTimeString(from: transaction?.created_at ?? 0)
                    )
                    Divider().background(appColors.text.opacity(0.1))

                    detailRow(label: L10n.History.expiryNo, value: bottle?.expirationDate ?? "-")
                    Divider().background(appColors.text.opacity(0.1))

                    detailRow(label: L10n.History.lotNo, value: bottle?.lotNumber ?? "-")
                    Divider().background(appColors.text.opacity(0.1))

                    detailRow(label: L10n.History.serialNo, value: bottle?.serialNumber ?? "-")
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 340)
    }

    // MARK: - Page Indicator
    // Sliding window of at most 3 dots; active dot always highlighted regardless of total bottle count.
    @ViewBuilder
    private var pageIndicator: some View {
        let count = allBottleInfos.count
        if count > 1 {
            let maxDots = 3
            let windowSize = min(count, maxDots)
            let start = min(max(bottlePage - windowSize / 2, 0), count - windowSize)

            HStack(spacing: 6) {
                ForEach(start..<(start + windowSize), id: \.self) { index in
                    Circle()
                        .fill(index == bottlePage ? appColors.primary : appColors.text.opacity(0.2))
                        .frame(width: index == bottlePage ? 8 : 6, height: index == bottlePage ? 8 : 6)
                }
            }
            .padding(.top, 8)
        }
    }

    private var substituedInfoList: some View {
        VStack(spacing: 0) {
            detailRow(
                label: L10n.History.drugName,
                value: transaction?.substitueDrug?.drug_name ?? "N/A"
                
                
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: L10n.History.ndc,
                value: transaction?.substitueDrug?.ndc ?? "N/A"
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

//struct DeleteOkButtons: View {
//    // MARK: - Inputs
//    let appColors: AppColors
//    let onDelete: () -> Void
//    let onOk: () -> Void
//
//    var body: some View {
//        EqualWidthHStackButtons(spacing: 16) {
//
//            // DELETE
//            PillCountingButton(
//                iconName: nil,
//                title: L10n.History.deleteButton,
//                textColor: appColors.primary,
//                backgroundColor: .clear,
//                borderColor: appColors.primary,
//                font: .system(size: 14, weight: .semibold),
//                cornerRadius: 30,
//                horizontalPadding: 32,
//                verticalPadding: 14,
//                iconSize: 0,
//                action: onDelete
//            )
//
//            // OK
//            PillCountingButton(
//                iconName: nil,
//                title: L10n.History.okButton,
//                textColor: Color.white,
//                backgroundColor: appColors.primary,
//                borderColor: .clear,
//                font: .system(size: 14, weight: .semibold),
//                cornerRadius: 30,
//                horizontalPadding: 32,
//                verticalPadding: 14,
//                iconSize: 0,
//                action: onOk
//            )
//        }
//    }
//}
