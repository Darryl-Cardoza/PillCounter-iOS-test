//
//  HistoryTransactionDetailView.swift
//  PillCounter
//
//  Created by HC on 18/11/25.
//

import CoreData
import SwiftUI

struct HistoryTransactionDetailViewNew: View {

    // MARK: - PROPERTIES
    @State private var transaction: PillCountTransactionEntity? = nil

    // MARK: - ENVIRONMENT
    @Environment(\.isLandscape) private var isLandscape
    @EnvironmentObject private var appColors: AppColors
    @EnvironmentObject private var userViewModel: UserViewModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var pillScanViewModel: PillScanViewModel

    @StateObject private var pdfService = PDFShareService.shared
//    @State private var showFullScreenImage = false
    @State private var fullScreenImage: Image?
    
    // MARK: - BODY
    var body: some View {
        ZStack {
            BaseView(
                topRatio: 1.0,
                topContent: {
                    mainContent
                },
                bottomContent: {
                    EmptyView()
                },
                headerActions: {
                    Button {
                        generateAndSharePDF()
                    } label: {
                        Image("pdf")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .overlay {
                                appColors.secondary
                            }
                            .mask(
                                Image("pdf")
                                    .resizable()
                                    .scaledToFit()
                            )
                            .padding(.trailing)
                    }
                },
                showBackButton: true,
                showHamburgerMenu: false,
                title: transaction?.drug?.drug_name ?? "Unknown Drug"
            )

            if pdfService.isLoading {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

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
                FullScreenImageView(
                    image:  image,
                    onDismiss: {
                        fullScreenImage = nil
                    }
                )
            }
        }
        .onAppear {
            
            if pillScanViewModel.currentTransaction != nil {
                transaction = pillScanViewModel.currentTransaction
            }
            // This is for loading dummy transaction for testing purposes.
            // Load specific details if necessary
//            if pillScanViewModel.currentTransaction == nil {
//                let dummyTransaction =
//                    PreviewDataHelper.shared.createDummyTransaction()
//
//                pillScanViewModel.currentTransaction = dummyTransaction
//                transaction = dummyTransaction
//            }
        }
        .onDisappear {
            transaction = nil
            pillScanViewModel.currentTransaction = nil
        }
    }

    // MARK: - MAIN CONTENT SWITCHER
    @ViewBuilder
    private var mainContent: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
               portraitLayout
            } else {
                portraitLayout
            }
        }
    }

    // MARK: - PORTRAIT LAYOUT

    
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // SECTION 1: Summary & Details
                    VStack(spacing: 24) {
                        collapsibleSections
                
                    }
                    .padding(.top, 80)  // Header offset
                    .padding(.bottom,50)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)  // Fill width in portrait
                 
                    
                    
                    HStack {
                        Spacer()
                        DeleteOkButtons(
                            appColors: appColors,
                            onDelete: {
                                Task {
                                    await userViewModel.softDeleteTheSelectedTransaction(
                                        transactionId: transaction?.txn_id ?? 0,
                                        countType: getCountType(
                                            from: transaction?.count_type ?? ""))
                                    
                                    router.navigateBack()
                                }
                            },
                            onOk: {
                                router.navigateBack()
                            }
                        )
                        Spacer()
                    }
                    .padding(
                        .horizontal,
                        UIDevice.current.userInterfaceIdiom == .pad ? 100 : 24
                    )
                    .padding(.top, -60)
                }
                .padding(.top, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appColors.secondaryBackground)
            }
        }
    }

    private func getCountType(from rawValue: String?) -> CountType {
        guard
            let rawValue,
            let countType = CountType(rawValue: rawValue)
        else {
            // Default fallback
            return .REGULAR
        }
        return countType
    }
    

    private func batchesGrid(step: ControlledStep) -> some View {
        let rows = [
            GridItem(.flexible())
        ]
        let detailsArray =
            (transaction?.pillCountTransactionDetails?.allObjects
            as? [PillCountTransactionDetailsEntity])?
            .filter { !$0.is_deleted }
            .filter { $0.type == step.rawValue }
            .sorted(by: { $0.created_at < $1.created_at }) ?? []

        return LazyHGrid(rows: rows, spacing: 16) {
            ForEach(detailsArray, id: \.txn_details_id) { detail in
                batchItem(detail: detail)
                    .frame(width: 160)
            }
        }
    }
    
    private var batchesGridVertical: some View {
        // 1. Define Columns for LazyVGrid
        // We use 2 flexible columns so they split the available width evenly.
        let columns = [
            GridItem(.flexible(), spacing: 16)
        ]

        let detailsArray =
            (transaction?.pillCountTransactionDetails?.allObjects
            as? [PillCountTransactionDetailsEntity])?
            .sorted(by: { $0.created_at < $1.created_at }) ?? []

        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(detailsArray, id: \.txn_details_id) { detail in
                batchItem(detail: detail)
                // 2. Remove the fixed width (.frame(width: 160))
                // The GridItem(.flexible()) controls the width now.
            }
        }
    }

    // MARK: - DETAILS LIST COMPONENT
    private var detailsInfoList: some View {
        VStack(spacing: 0) {
            //Substitued drug name
            detailRow(
                label: "Substituted Drug",
                value: transaction?.drug?.drug_name ?? "N/A"
            )
            
            // 1. NDC
            detailRow(
                label: "NDC",
                value: transaction?.drug?.ndc ?? "N/A"
            )

            Divider().background(appColors.text.opacity(0.1))

            // 2. Expiry
            detailRow(
                label: "Expiry No",
                value: transaction?.expiry ?? "N/A"
            )

            Divider().background(appColors.text.opacity(0.1))

            // 3. Lot No
            detailRow(
                label: "Lot No",
                value: transaction?.lot_no ?? "N/A"
            )

            Divider().background(appColors.text.opacity(0.1))

            // 4. Date
            detailRow(
                label: "Date",
                value: Formatter.getDateString(
                    from: transaction?.created_at ?? 0)
            )

            Divider().background(appColors.text.opacity(0.1))

            // 5. Time
            detailRow(
                label: "Time",
                value: Formatter.getTimeString(
                    from: transaction?.created_at ?? 0)
            )
        }
    }

    // Helper builder for a single row
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

    private func batchItem(detail: PillCountTransactionDetailsEntity)
        -> some View
    {
        VStack(alignment: .leading, spacing: 0) {
            // Image + Count Badge
            ZStack {

                if let path = detail.image_path,
                    let image = PhotoFileManager.shared.loadImage(from: path)
                {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 100)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 110)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(Color.gray)
                        )
                }

                // Count Circle
                Text("\(detail.pill_count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(appColors.primary)
                    .clipShape(Circle())
                    .padding(8)
            }
            .onTapGesture {
                if let path = detail.image_path,
                   let loadedImage = PhotoFileManager.shared.loadImage(from: path) {

                    fullScreenImage = loadedImage
                }
            }
        }
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(appColors.text.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - HELPERS
    // Overload: Accepts the Core Data Entity (Transaction) directly
    private func getTotalPillCount(
        for transaction: PillCountTransactionEntity,
        step: ControlledStep
    ) -> Int {

        let detailsArray =
            (transaction.pillCountTransactionDetails?.allObjects
            as? [PillCountTransactionDetailsEntity])?
            .filter { !$0.is_deleted } ?? []

        return pillScanViewModel.getTotalPillCountOfCurrentTransactionByType(
            type: step,
            details: detailsArray
        )
    }

    private func generateAndSharePDF() {
        if let vc = UIApplication.shared.topMostViewController() {
            PDFShareService.shared.generateAndShareDrugHistoryPDF(
                drugName: transaction?.drug?.drug_name ?? "",
                totalCount: getTotalPillCount(for: transaction!, step: .targetVerification),
                ndc: transaction?.drug?.ndc ?? "N/A",
                expiry: transaction?.expiry ?? "N/A",
                lotNo: transaction?.lot_no ?? "N/A",
                date: Formatter.getDateString(
                    from: transaction?.created_at ?? 0),
                time: Formatter.getTimeString(
                    from: transaction?.created_at ?? 0),
                note: transaction?.note,
                presentingVC: vc
            )
        }
    }
    
    private var collapsibleSections: some View {
        VStack(spacing: 12) {
            
            CollapsibleBox(title: "INITIAL CONTAINER COUNT", allowCollapse: false, defaultExpanded: true) {
                collapsableBoxContent(step: .containerInitiate, showTargetCount: false)
            }
            
            
            CollapsibleBox(title: "SUBSTITUTED DRUG DETAILS") {
                detailsInfoList
            }
            
            CollapsibleBox(title: "PILL COUNT 1") {
                collapsableBoxContent(step: .targetVerification)
            }
            
            CollapsibleBox(title: "PILL COUNT 2") {
                collapsableBoxContent(step: .targetReverification)
            }
                
            CollapsibleBox(title: "DISPENSED VIAL") {
                collapsableBoxContent(step: .vial, showVialInfo: true)
            }
            
            CollapsibleBox(title: "REMAINING CONTAINER COUNT") {
                collapsableBoxContent(step: .containerPending, showTargetCount: false)
            }
            
            CollapsibleBox(title: "NOTE") {
                notesContent
            }
        }
    }
    
    private func collapsableBoxContent(step: ControlledStep, showTargetCount: Bool = true, showVialInfo: Bool = false) -> some View {
            VStack (spacing: 10){
                if !showVialInfo {
                    HStack(spacing: 20) {
                        // Image / Icon Container
                        ThumbnailImageView(
                            imagePath: transaction?.barcode_image,
                            width: 160,
                            height: 120,
                            cornerRadius: 12,
                            placeholderImageName: "placeholder_history",
                            placeholderSize: CGSize(width: 20, height: 20)
                        )
                        .onTapGesture {
                            if let path = transaction?.barcode_image,
                               let loadedImage = PhotoFileManager.shared.loadImage(from: path) {
                                
                                fullScreenImage = loadedImage
                            }
                        }
                        .environmentObject(appColors)
                        
                        
                        Spacer()
                        
                        VStack {
                            // Note: You can also use the calculated total here if you have it
                            let targetCount = transaction?.target_count ?? 0
                            
                            if showTargetCount {
                                Text("\(transaction.map { getTotalPillCount(for: $0,  step: step) } ?? 0)")
                                    .foregroundStyle(appColors.secondary)
                                    .font(.system(size: 25, weight: .bold))
                                    .padding(.bottom, -6)
                                
                                Rectangle()
                                    .fill(appColors.secondary)
                                    .frame(width: 50, height: 2)
                                
                                Text("\(targetCount)")
                                    .foregroundStyle(appColors.secondary)
                                    .font(.system(size: 25, weight: .bold))
                                    .padding(.top, -6)
                                    .padding(.bottom,3)
                            } else {
                                Text("\(transaction.map { getTotalPillCount(for: $0, step: step) } ?? 0)")
                                    .foregroundStyle(appColors.secondary)
                                    .font(.system(size: 25, weight: .bold))
                                    .padding(.bottom,3)

                            }
                            
                            
                            Text("TOTAL COUNT")
                                .foregroundStyle(appColors.primary)
                                .font(.system(size: 14))
                                .multilineTextAlignment(.center)
                        }
                        
                        Spacer()
                    }
                    Spacer()
                }
            
            ScrollView(.horizontal, showsIndicators: false) {
                batchesGrid(step: step)
            }
        }
    }
    
    private var notesContent: some View {
        Text(transaction?.note ?? "No notes available")
            .font(.system(size: 14))
            .foregroundStyle(appColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CollapsibleBox<Content: View>: View {

    let title: String
    let content: Content
    var allowCollapse: Bool = true

    @State private var isExpanded: Bool

    @EnvironmentObject private var appColors: AppColors

    init(
        title: String,
        allowCollapse: Bool = true,
        defaultExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.allowCollapse = allowCollapse
        self._isExpanded = State(initialValue: allowCollapse ? defaultExpanded : true)
        self.content = content()
    }


    var body: some View {
        VStack(spacing: 0) {

            // HEADER
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appColors.primary)

                Spacer()

                if allowCollapse{
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut, value: isExpanded)
                        .foregroundStyle(appColors.primary)
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                if allowCollapse{
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            // CONTENT
            if isExpanded {
                content
                    .padding()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .background(appColors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 0)
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
//                title: "DELETE",
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
//                title: "OK",
//                textColor: Color.white,
//                backgroundColor: appColors.secondary,
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



