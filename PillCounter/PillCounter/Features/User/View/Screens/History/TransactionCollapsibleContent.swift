//
//  TransactionCollapsibleContent.swift
//  PillCounter
//
//  Created by Bhushan Patil on 18/03/26.
//
//import SwiftUI
//
//struct TransactionCollapsibleContent: View {
//    
//    let transaction: PillCountTransactionEntity
//    let stepType: ControlledStep
//    
//    @EnvironmentObject private var appColors: AppColors
//    @EnvironmentObject private var pillScanViewModel: PillScanViewModel
//    
//    var body: some View {
//        
//        VStack(spacing: 10) {
//            
//            headerSection
//            
//            ScrollView(.horizontal, showsIndicators: false) {
//                batchesGrid
//            }
//        }
//    }
//    
//    
//    
//    private var headerSection: some View {
//        HStack(spacing: 20) {
//            
//            // Image / Icon Container
//            ThumbnailImageView(
//                imagePath: transaction.barcode_image,
//                width: 160,
//                height: 120,
//                cornerRadius: 12,
//                placeholderImageName: "placeholder_history",
//                placeholderSize: CGSize(width: 20, height: 20)
//            )
//            .onTapGesture {
//                if let path = transaction.barcode_image,
//                   let loadedImage = PhotoFileManager.shared.loadImage(from: path) {
//                    
//                    //                    fullScreenImage = loadedImage
//                }
//            }
//            .environmentObject(appColors)
//            
//            
//            Spacer()
//            
//            VStack {
//                // Note: You can also use the calculated total here if you have it
//                let isFixed = transaction.count_type == CountType.FIXED.rawValue
//                let targetCount = transaction.target_count ?? 0
//                
//                if isFixed {
//                    Text("\(transaction.map { getTotalPillCount(for: $0) } ?? 0)")
//                        .foregroundStyle(appColors.secondary)
//                        .font(.system(size: 25, weight: .bold))
//                        .padding(.bottom, -6)
//                    
//                    Rectangle()
//                        .fill(appColors.secondary)
//                        .frame(width: 50, height: 2)
//                    
//                    Text("\(targetCount)")
//                        .foregroundStyle(appColors.secondary)
//                        .font(.system(size: 25, weight: .bold))
//                        .padding(.top, -6)
//                        .padding(.bottom,3)
//                } else {
//                    Text("\(transaction.map { getTotalPillCount(for: $0) } ?? 0)")
//                        .foregroundStyle(appColors.secondary)
//                        .font(.system(size: 25, weight: .bold))
//                }
//                
//                
//                
//                Text("TOTAL RECOUNT")
//                    .foregroundStyle(appColors.primary)
//                    .font(.system(size: 14))
//                    .multilineTextAlignment(.center)
//            }
//            
//            Spacer()
//        }
//        
//    }
//    
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
//    
//    private var batchesGrid: some View {
//
//        let rows = [GridItem(.flexible())]
//
//        let detailsArray =
//            (transaction.pillCountTransactionDetails?.allObjects
//            as? [PillCountTransactionDetailsEntity])?
//            .filter { !$0.is_deleted }
//            .sorted(by: { $0.created_at < $1.created_at }) ?? []
//
//        return LazyHGrid(rows: rows, spacing: 16) {
//            ForEach(detailsArray, id: \.txn_details_id) { detail in
//                batchItem(detail: detail)
//                    .frame(width: 160)
//            }
//        }
//    }
//    
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
//                        .frame(width: 150, height: 100)
//                        .clipped()
//                } else {
//                    Rectangle()
//                        .fill(Color.gray.opacity(0.2))
//                        .frame(width: 150, height: 110)
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
////                    fullScreenImage = loadedImage
//                }
//            }
//        }
//        .cornerRadius(16)
//        .overlay(
//            RoundedRectangle(cornerRadius: 16)
//                .stroke(appColors.text.opacity(0.1), lineWidth: 1)
//        )
//    }
//}
