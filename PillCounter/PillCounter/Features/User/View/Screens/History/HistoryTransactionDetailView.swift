//
//  HistoryTransactionDetailView.swift
//  PillCounter
//
//  Created by HC on 18/11/25.
//

import CoreData
import SwiftUI

//struct HistoryTransactionDetailView: View {
//
//    // MARK: - PROPERTIES
//    @State private var transaction: PillCountTransactionEntity? = nil
//
//    // MARK: - ENVIRONMENT
//    @Environment(\.isLandscape) private var isLandscape
//    @EnvironmentObject private var appColors: AppColors
//    @EnvironmentObject private var userViewModel: UserViewModel
//    @EnvironmentObject private var router: Router
//    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
//
//    @StateObject private var pdfService = PDFShareService.shared
////    @State private var showFullScreenImage = false
//    @State private var fullScreenImage: Image?
//    
//    // MARK: - BODY
//    var body: some View {
//        ZStack {
//            BaseView(
//                topRatio: 1.0,
//                topContent: {
//                    mainContent
//                },
//                bottomContent: {
//                    EmptyView()
//                },
//                headerActions: {
//                    Button {
//                        generateAndSharePDF()
//                    } label: {
//                        Image("pdf")
//                            .resizable()
//                            .scaledToFit()
//                            .frame(width: 30, height: 30)
//                            .overlay {
//                                appColors.secondary
//                            }
//                            .mask(
//                                Image("pdf")
//                                    .resizable()
//                                    .scaledToFit()
//                            )
//                            .padding(.trailing)
//                    }
//                },
//                showBackButton: true,
//                showHamburgerMenu: false,
//                title: transaction?.drug?.drug_name ?? "Unknown Drug"
//            )
//
//            if pdfService.isLoading {
//                ZStack {
//                    Color.black.opacity(0.5)
//                        .ignoresSafeArea()
//
//                    PillCountingLoader()
//                }
//            }
//        }
//
//        .fullScreenCover(
//            isPresented: Binding(
//                get: { fullScreenImage != nil },
//                set: { if !$0 { fullScreenImage = nil } }
//            )
//        ) {
//            if let image = fullScreenImage {
//                FullScreenImageView(
//                    image:  image,
//                    onDismiss: {
//                        fullScreenImage = nil
//                    }
//                )
//            }
//        }
//        .onAppear {
//            
//            if pillScanViewModel.currentTransaction != nil {
//                transaction = pillScanViewModel.currentTransaction
//            }
//            // This is for loading dummy transaction for testing purposes.
//            // Load specific details if necessary
////            if pillScanViewModel.currentTransaction == nil {
////                let dummyTransaction =
////                    PreviewDataHelper.shared.createDummyTransaction()
////
////                pillScanViewModel.currentTransaction = dummyTransaction
////                transaction = dummyTransaction
////            }
//        }
//        .onDisappear {
//            transaction = nil
//            pillScanViewModel.currentTransaction = nil
//        }
//    }
//
//    // MARK: - MAIN CONTENT SWITCHER
//    @ViewBuilder
//    private var mainContent: some View {
//        GeometryReader { geo in
//            if geo.size.width > geo.size.height {
//                landscapeLayout(
//                    totalWidth: geo.size.width, safeArea: geo.safeAreaInsets)
//            } else {
//                portraitLayout
//            }
//        }
//    }
//
//    // MARK: - PORTRAIT LAYOUT
//    private var portraitLayout: some View {
//        VStack(alignment: .leading, spacing: 24) {
//
//            // SECTION 1: Summary & Details
//            VStack(spacing: 24) {
//                summaryCard
//
//                detailsInfoList
//            }
//            .padding(.top, 80)  // Header offset
//            .padding(.horizontal, 20)
//            .frame(maxWidth: .infinity)  // Fill width in portrait
//
//            // SECTION 2: Notes & Batches Grid
//            VStack(alignment: .leading, spacing: 12) {
//
//                if let notes = transaction?.note, !notes.isEmpty {
//                    notesSection(notes)
//                        .padding(.horizontal)
//                }
//
//                // Horizontal Scroll for Batches in Portrait
//                ScrollView(.horizontal, showsIndicators: false) {
//                    batchesGrid  // Ensure this refers to your Horizontal Grid
//                        .padding(.horizontal, 20)
//                }
//                .padding(.top, -24)
//                .frame(height: 180)
//            }
//            .padding(.top, 0)
//            .frame(
//                maxWidth: .infinity,
//                maxHeight: .infinity,
//                alignment: .topLeading
//            )
//
//            Spacer()
//
//            HStack {
//                Spacer()
//                DeleteOkButtons(
//                    appColors: appColors,
//                    onDelete: {
//                        Task {
//                            await userViewModel.softDeleteTheSelectedTransaction(
//                                transactionId: transaction?.txn_id ?? 0,
//                                countType: getCountType(
//                                    from: transaction?.count_type ?? ""))
//
//                            router.navigateBack()
//                        }
//                    },
//                    onOk: {
//                        router.navigateBack()
//                    }
//                )
//                Spacer()
//            }
//            .padding(
//                .horizontal,
//                UIDevice.current.userInterfaceIdiom == .pad ? 100 : 24
//            )
//            .padding(.top, -60)
//        }
//        .padding(.top, 30)
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .background(appColors.primaryBackground)
//    }
//
//    private func getCountType(from rawValue: String?) -> CountType {
//        guard
//            let rawValue,
//            let countType = CountType(rawValue: rawValue)
//        else {
//            // Default fallback
//            return .REGULAR
//        }
//        return countType
//    }
//
//    private func landscapeLayout(
//        totalWidth: CGFloat,
//        safeArea: EdgeInsets
//    ) -> some View {
//
//        let usableWidth = totalWidth - safeArea.leading - safeArea.trailing
//        let leftMiddleWidth = usableWidth * 0.65
//
//        return HStack(alignment: .top, spacing: 20) {
//
//            // LEFT + MIDDLE + BUTTONS (STACKED)
//            VStack(alignment: .leading, spacing: 20) {
//
//                // LEFT + MIDDLE COLUMNS
//                HStack(alignment: .top, spacing: 20) {
//
//                    // LEFT COLUMN
//                    VStack(alignment: .leading, spacing: 20) {
//                        summaryCard
//
//                        if let notes = transaction?.note, !notes.isEmpty {
//                            notesSection(notes)
//                        }
//                    }
//                    .frame(width: leftMiddleWidth * 0.55)
//
//                    // MIDDLE COLUMN
//                    VStack {
//                        detailsInfoList
//                        Spacer()
//                    }
//                    .frame(width: leftMiddleWidth * 0.45)
//                }
//                HStack {
//                    Spacer()
//                    DeleteOkButtons(
//                        appColors: appColors,
//                        onDelete: {
//                            Task {
//                                await userViewModel
//                                    .softDeleteTheSelectedTransaction(
//                                        transactionId: transaction?.txn_id ?? 0,
//                                        countType: getCountType(
//                                            from: transaction?.count_type ?? "")
//                                    )
//
//                                router.navigateBack()
//                            }
//                        },
//                        onOk: {
//                            router.navigateBack()
//                        }
//                    )
//                    Spacer()
//                }
//                .padding(.top, -30)
//                .padding(.bottom, 10)
//            }
//            .frame(width: leftMiddleWidth)
//
//            // RIGHT COLUMN (Batches)
//            ScrollView(.vertical, showsIndicators: false) {
//                batchesGridVertical
//            }
//            .frame(maxWidth: .infinity)
//        }
//        .padding(.top, 90)
//        .padding(.leading, safeArea.leading + 55)
//        .padding(.trailing, safeArea.trailing + 55)
//        .background(appColors.primaryBackground)
//    }
//
//    // MARK: - HELPERS & UI
//    // MARK: SUMMARY CARD
//    private var summaryCard: some View {
//        HStack(spacing: 20) {
//
//            // Image / Icon Container
//            ThumbnailImageView(
//                imagePath: transaction?.barcode_image,
//                width: 160,
//                height: 100,
//                cornerRadius: 16,
//                placeholderImageName: "placeholder_history",
//                placeholderSize: CGSize(width: 25, height: 25)
//            )
//            .onTapGesture {
//                if let path = transaction?.barcode_image,
//                   let loadedImage = PhotoFileManager.shared.loadImage(from: path) {
//
//                    fullScreenImage = loadedImage
//                }
//            }
//            .environmentObject(appColors)
//            
//        
//            Spacer()
//
//            VStack {
//                // Note: You can also use the calculated total here if you have it
//                let isFixed = transaction?.count_type == CountType.FIXED.rawValue
//                let targetCount = transaction?.target_count ?? 0
//                
//                if isFixed {
//                    Text("\(transaction.map { getTotalPillCount(for: $0) } ?? 0)")
//                         .foregroundStyle(appColors.secondary)
//                         .font(.system(size: 32, weight: .bold))
//                         .padding(.bottom, -6)
//
//                     Rectangle()
//                         .fill(appColors.secondary)
//                         .frame(width: 70, height: 2)
//
//                     Text("\(targetCount)")
//                         .foregroundStyle(appColors.secondary)
//                         .font(.system(size: 32, weight: .bold))
//                         .padding(.top, -6)
//                         .padding(.bottom,3)
//                } else {
//                    Text("\(transaction.map { getTotalPillCount(for: $0) } ?? 0)")
//                        .foregroundStyle(appColors.secondary)
//                        .font(.system(size: 34, weight: .bold))
//                }
//                
//              
//
//                Text("TOTAL COUNT")
//                    .foregroundStyle(appColors.primary)
//                    .font(.system(size: 16))
//                    .multilineTextAlignment(.center)
//            }
//
//            Spacer()
//        }
//    }
//
//    private func notesSection(_ notes: String) -> some View {
//        ScrollView(.vertical, showsIndicators: true) {
//            Text(notes)
//                .font(.body)
//                .foregroundStyle(appColors.text)
//                .padding()  // Padding inside the scroll view
//                .frame(maxWidth: .infinity, alignment: .topLeading)  // Align text to top-left
//        }
//        .frame(height: 130)
//        .frame(maxWidth: .infinity)
//        .overlay(
//            RoundedRectangle(cornerRadius: 12)
//                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
//        )
//    }
//
//    private var batchesGrid: some View {
//        // 1. Define Rows instead of Columns for LazyHGrid
//        // .flexible() allows the row to fit the height of the content (batchItem)
//        let rows = [
//            GridItem(.flexible())
//        ]
//
//        let detailsArray =
//            (transaction?.pillCountTransactionDetails?.allObjects
//            as? [PillCountTransactionDetailsEntity])?
//            .filter { !$0.is_deleted }
//            .sorted(by: { $0.created_at < $1.created_at }) ?? []
//
//        return LazyHGrid(rows: rows, spacing: 16) {
//            ForEach(detailsArray, id: \.txn_details_id) { detail in
//                batchItem(detail: detail)
//                    // 2. Set a fixed width for horizontal scrolling cards
//                    .frame(width: 160)
//            }
//        }
//    }
//
//    private var batchesGridVertical: some View {
//        // 1. Define Columns for LazyVGrid
//        // We use 2 flexible columns so they split the available width evenly.
//        let columns = [
//            GridItem(.flexible(), spacing: 16)
//        ]
//
//        let detailsArray =
//            (transaction?.pillCountTransactionDetails?.allObjects
//            as? [PillCountTransactionDetailsEntity])?
//            .sorted(by: { $0.created_at < $1.created_at }) ?? []
//
//        return LazyVGrid(columns: columns, spacing: 16) {
//            ForEach(detailsArray, id: \.txn_details_id) { detail in
//                batchItem(detail: detail)
//                // 2. Remove the fixed width (.frame(width: 160))
//                // The GridItem(.flexible()) controls the width now.
//            }
//        }
//    }
//
//    // MARK: - DETAILS LIST COMPONENT
//    private var detailsInfoList: some View {
//        VStack(spacing: 0) {
//            // 1. NDC
//            detailRow(
//                label: "NDC",
//                value: transaction?.drug?.ndc ?? "N/A"
//            )
//
//            Divider().background(appColors.text.opacity(0.1))
//
//            // 2. Expiry
//            detailRow(
//                label: "Expiry No",
//                value: transaction?.expiry ?? "N/A"
//            )
//
//            Divider().background(appColors.text.opacity(0.1))
//
//            // 3. Lot No
//            detailRow(
//                label: "Lot No",
//                value: transaction?.lot_no ?? "N/A"
//            )
//
//            Divider().background(appColors.text.opacity(0.1))
//
//            // 4. Date
//            detailRow(
//                label: "Date",
//                value: Formatter.getDateString(
//                    from: transaction?.created_at ?? 0)
//            )
//
//            Divider().background(appColors.text.opacity(0.1))
//
//            // 5. Time
//            detailRow(
//                label: "Time",
//                value: Formatter.getTimeString(
//                    from: transaction?.created_at ?? 0)
//            )
//        }
//    }
//
//    // Helper builder for a single row
//    private func detailRow(label: String, value: String) -> some View {
//        HStack(alignment: .top) {
//            Text(label)
//                .font(.subheadline)
//                .foregroundStyle(appColors.text.opacity(0.6))
//                .frame(width: 100, alignment: .leading)
//
//            Text(value)
//                .font(.subheadline)
//                .fontWeight(.semibold)
//                .foregroundStyle(appColors.text)
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .multilineTextAlignment(.leading)
//        }
//        .padding(.horizontal, 10)
//        .padding(.vertical, 14)
//    }
//
//    private func batchItem(detail: PillCountTransactionDetailsEntity)
//        -> some View
//    {
//        VStack(alignment: .leading, spacing: 0) {
//            // Image + Count Badge
//            ZStack {
//
//                if let path = detail.image_path,
//                    let image = PhotoFileManager.shared.loadImage(from: path)
//                {
//                    image
//                        .resizable()
//                        .scaledToFill()
//                        .frame(height: 100)
//                        .frame(maxWidth: .infinity)
//                        .clipped()
//                } else {
//                    Rectangle()
//                        .fill(Color.gray.opacity(0.2))
//                        .frame(height: 100)
//                        .overlay(
//                            Image(systemName: "photo")
//                                .foregroundStyle(Color.gray)
//                        )
//                }
//
//                // Count Circle
//                Text("\(detail.pill_count)")
//                    .font(.subheadline)
//                    .fontWeight(.bold)
//                    .foregroundStyle(.white)
//                    .frame(width: 36, height: 36)
//                    .background(appColors.primary)
//                    .clipShape(Circle())
//                    .padding(8)
//            }
//            .onTapGesture {
//                if let path = detail.image_path,
//                   let loadedImage = PhotoFileManager.shared.loadImage(from: path) {
//
//                    fullScreenImage = loadedImage
//                }
//            }
//        }
//        .cornerRadius(16)
//        .overlay(
//            RoundedRectangle(cornerRadius: 16)
//                .stroke(appColors.text.opacity(0.1), lineWidth: 1)
//        )
//    }
//
//    // MARK: - HELPERS
//    // Overload: Accepts the Core Data Entity (Transaction) directly
//    private func getTotalPillCount(for transaction: PillCountTransactionEntity)
//        -> Int
//    {
//        let detailsArray =
//            (transaction.pillCountTransactionDetails?.allObjects
//                as? [PillCountTransactionDetailsEntity]) ?? []
//
//        return pillScanViewModel.getTotalPillCountOfCurrentTransactionByType(
//            type:.targetVerification,
//            details: detailsArray.filter { !$0.is_deleted }
//
//        )
//    }
//
//    private func generateAndSharePDF() {
//        if let vc = UIApplication.shared.topMostViewController() {
//            PDFShareService.shared.generateAndShareDrugHistoryPDF(
//                drugName: transaction?.drug?.drug_name ?? "",
//                totalCount: getTotalPillCount(for: transaction!),
//                ndc: transaction?.drug?.ndc ?? "N/A",
//                expiry: transaction?.expiry ?? "N/A",
//                lotNo: transaction?.lot_no ?? "N/A",
//                date: Formatter.getDateString(
//                    from: transaction?.created_at ?? 0),
//                time: Formatter.getTimeString(
//                    from: transaction?.created_at ?? 0),
//                note: transaction?.note,
//                presentingVC: vc
//            )
//        }
//    }
//}

// MARK: - PREVIEW
//#Preview(traits: .portrait) {
//    let dummyTransaction = PreviewDataHelper.shared.createDummyTransaction()
//    let mockRouter = Router()
//    let mockAppColors = AppColors.shared
//    let mockUserVM = UserViewModel()
//    let mockPillScanVM = PillScanViewModel()
//
//    HistoryTransactionDetailView()
//        .environmentObject(mockRouter)
//        .environmentObject(mockAppColors)
//        .environmentObject(mockUserVM)
//        .environmentObject(mockPillScanVM)
//        .preferredColorScheme(.dark)
//        .previewInterfaceOrientation(.landscapeLeft)
//}

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
