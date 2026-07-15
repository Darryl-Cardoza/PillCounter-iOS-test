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
    
    /// Resolved once in .onAppear, kept locally so the view doesn't re-resolve on every render.
    @State private var transaction: PillCountTransactionEntity? = nil

    private var firstBottleBarcodeImagePath: String? {
        [BottleInfo].decode(from: transaction?.bottle_info_list_json).first?.barcodeImagePath
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

//            HStack {
//                Spacer()
//
//                DeleteOkButtons(
//                    appColors: appColors,
//                    onDelete: {
//                        Task {
//                            await historyViewModel.softDeleteTransaction(
//                                txnId: transaction?.txn_id ?? 0
//                            )
//                            router.navigateBack()
//                        }
//                    },
//                    onOk: {
//                        router.navigateBack()
//                    }
//                )
//
//                Spacer()
//            }
//            .padding(.vertical, 16)
//            .background(appColors.primaryBackground)
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
    
    // MARK: - Collapsible Sections
    private var collapsibleSections: some View {
        VStack(spacing: 10) {
            var drugDetailsTitle: String {
                if transaction?.is_substitute == true {
                    return L10n.History.substitutedDrugDetails
                } else {
                    return L10n.History.dispensedDrugDetails
                }
            }

            if let type = transaction?.drug?.drug_type, type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CollapsibleBox(
                    title: L10n.History.pillCount,
                    allowCollapse: false,
                    defaultExpanded: true,
                    bgColor: appColors.secondaryBackground
                ) {
                    collapsableBoxContent(step: .targetVerification)
                }
            }

            if let details = historyViewModel.detailsByStep[.containerInitiate],
               !details.isEmpty
            {
                CollapsibleBox(
                    title: L10n.History.initialContainerCount,
                    allowCollapse: false,
                    defaultExpanded: true,
                    bgColor: appColors.secondaryBackground
                ) {
                    collapsableBoxContent(step: .containerInitiate, showTargetCount: false)
                }
            }
            
            if transaction?.is_substitute == true {
                CollapsibleBox(
                    title: L10n.History.requestedDrugDetails,
                    bgColor: appColors.secondaryBackground
                ) {
                    substituedInfoList
                }
            }
            
            CollapsibleBox(title: drugDetailsTitle,   bgColor: appColors.secondaryBackground) {
                detailsInfoList
            }

            if let type = transaction?.drug?.drug_type, !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                CollapsibleBox(
                    title: L10n.History.pillCount,
                    bgColor: appColors.secondaryBackground
                ) {
                    collapsableBoxContent(step: .targetVerification)
                }
            }

            if let details = historyViewModel.detailsByStep[.targetReverification],
               !details.isEmpty
            {
                CollapsibleBox(
                    title: L10n.History.pillRecount,
                    bgColor: appColors.secondaryBackground
                ) {
                    collapsableBoxContent(step: .targetReverification)
                }
            }

            if let details = historyViewModel.detailsByStep[.vial],
               !details.isEmpty
            {
                CollapsibleBox(
                    title: L10n.History.dispensedVial,
                    bgColor: appColors.secondaryBackground
                ) {
                    collapsableBoxContent(step: .vial, showVialInfo: true)
                }
            }

            if let details = historyViewModel.detailsByStep[.containerPending],
               !details.isEmpty
            {
                CollapsibleBox(
                    title: L10n.History.remainingContainerCount,
                    bgColor: appColors.secondaryBackground
                ) {
                    collapsableBoxContent(step: .containerPending, showTargetCount: false)
                }
            }

            CollapsibleBox(title: L10n.Common.note, bgColor: appColors.secondaryBackground) {
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
        VStack(spacing: 20) {
            if showVialInfo{
                if let detail = historyViewModel.detailsByStep[step]?.first {
                    batchItem(detail: detail, step: step)
                }
            } else {
                HStack(spacing: 20) {
                    ThumbnailImageView(
                        imagePath: firstBottleBarcodeImagePath,
                        width: 140,
                        height: 100,
                        cornerRadius: 12,
                        placeholderImageName: "placeholder_history",
                        placeholderSize: CGSize(width: 20, height: 20)
                    )
                    .onTapGesture {
                        if let path = firstBottleBarcodeImagePath,
                           let loaded = PhotoFileManager.shared.loadImage(from: path) {
                            fullScreenImage = loaded
                        }
                    }
                    .environmentObject(appColors)

                    VStack(alignment: .center, spacing: 4) {
                       Spacer()
                        if showTargetCount {
                            // Counted / Target
//                            Text("\(historyViewModel.getTotalCount(step: step))")
//                                .foregroundStyle(appColors.secondary)
//                                .font(.system(size: 25, weight: .bold))
//                                .padding(.bottom, -6)
//
//                            Rectangle()
//                                .fill(appColors.secondary)
//                                .frame(width: 50, height: 2)
//
//                            Text("\(transaction?.target_count ?? 0)")
//                                .foregroundStyle(appColors.secondary)
//                                .font(.system(size: 25, weight: .bold))
//                                .padding(.top, -6)
//                                .padding(.bottom, 3)
                            
                            let totalCount = historyViewModel.getTotalCount(step: step)
                             if totalCount > 0 {
                                 Text("\(totalCount)")
                                     .foregroundStyle(appColors.secondary)
                                     .font(.system(size: 25, weight: .bold))
                                     .padding(.bottom, 3)
                                     .minimumScaleFactor(0.6)
                                     .lineLimit(1)
                                     .padding(.bottom, -6)

                                 Rectangle()
                                     .fill(appColors.secondary)
                                     .frame(width: 50, height: 2)

                                 Text("\(transaction?.target_count ?? 0)")
                                     .foregroundStyle(appColors.secondary)
                                     .font(.system(size: 25, weight: .bold))
                                     .minimumScaleFactor(0.6)
                                     .lineLimit(1)
                                     .padding(.top, -6)

//                                 Text(NSLocalizedString("TOTAL_COUNT", comment: ""))
//                                     .foregroundStyle(appColors.text)
//                                     .font(.system(size: 14))
//                                     .fontWeight(.semibold)
//                                     .multilineTextAlignment(.center)
//                                     .lineLimit(2)
                             }
                        }  else {
                            if let txn = transaction {
                                let pillCount = historyViewModel.getTotalPillCount(for: txn, step: step)
                                if pillCount > 0 {
                                    Text("\(pillCount)")
                                        .foregroundStyle(appColors.secondary)
                                        .font(.system(size: 25, weight: .bold))
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                    
//                                    Text(NSLocalizedString("TOTAL_COUNT", comment: ""))
//                                        .foregroundStyle(appColors.text)
//                                        .font(.system(size: 14))
//                                        .fontWeight(.semibold)
//                                        .multilineTextAlignment(.center)
//                                        .lineLimit(2)
                                }
                            }
                        }

                        Spacer()
                    }
                    .frame(width: 120, height: 100)

                    Spacer()
                }
            }

            // Images grid — reads from historyViewModel.detailsByStep.
            // Vial shows a single image above, so skip the grid for it.
            if !showVialInfo {
                ScrollView(.horizontal, showsIndicators: false) {
                    batchesGrid(step: step)
                }
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
                label: L10n.History.substitutedDrug,
                value: transaction?.drug?.drug_name ?? "N/A"
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: L10n.History.ndc,
                value: transaction?.drug?.ndc ?? "N/A"
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: L10n.Common.date,
                value: Formatter.getDateString(from: transaction?.created_at ?? 0)
            )
            Divider().background(appColors.text.opacity(0.1))

            detailRow(
                label: L10n.Common.time,
                value: Formatter.getTimeString(from: transaction?.created_at ?? 0)
            )
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
