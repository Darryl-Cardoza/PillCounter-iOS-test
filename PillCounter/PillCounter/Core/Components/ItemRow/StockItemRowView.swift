//
//  StockItemRowView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
import SwiftUI

// MARK: - Reusable View
struct StockItemRowView: View {
    let data: StockData
    let appColors: AppColors



//    private var displayText: String {
//        "\(data.pillCount) / \(data.targetCount)"
//    }

//    private var fillFraction: Double {
//        guard data.targetCount > 0 else { return 0 }
//        return min(Double(data.pillCount) / Double(data.targetCount), 1.0)
//    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {

            ThumbnailImageView(
                imagePath: nil,
                width: 80,
                height: 60,
                cornerRadius: 8,
                borderColor: appColors.primaryBackground,
                placeholderImageName:  data.isFromPms ? "batch_icon" : "dispense_placeholder",
                placeholderBackgroundColor: appColors.text,
                placeholderSize: CGSize(width: 28, height: 28),
                showImageBackground: appColors.primaryBackground
            )

            // Center info
            VStack(alignment: .leading, spacing: 8) {

                Text(String(data.batchId))
                    .foregroundColor(appColors.primary)
                    .font(.system(size: 14, weight: .semibold))
                                    

                HStack(spacing: 10){
                    // Date
                    Text(DateUtils.formatToUSDateTime(data.createdAt))
                        .foregroundColor(appColors.text.opacity(0.6))
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                    
                    if data.bucketId != "NORMAL"{
                        Text(data.bucketId)
                            .foregroundColor(appColors.text)
                            .font(.system(size: 12, weight: .regular))
                    }
                }
            }

            Spacer()

            // Right side
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                  
                    Text(String(data.ndcCount))
                        .foregroundColor(appColors.secondary)
                        .font(.system(size: 16, weight: .bold))
                                        

                    Text("NDCs")
                        .foregroundColor(appColors.text)
                        .font(.system(size: 12, weight: .regular))
                }
            }
            .padding(.trailing, 8)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 12)
        .background(appColors.secondaryBackground)
        .cornerRadius(12)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func tintedIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .overlay(appColors.primary)
            .mask(
                Image(name)
                    .resizable()
                    .scaledToFit()
            )
    }
}
