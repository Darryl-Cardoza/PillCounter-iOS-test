//
//  DispenseItemRowView.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/04/26.
//
import SwiftUI



// MARK: - Reusable View
struct DispenseItemRowView: View {
    let data: TransactionRowData
    @EnvironmentObject private var appColors: AppColors


    private var isPartial: Bool {
        data.status == CountStatus.PARTIAL.rawValue &&
        data.targetCount != data.pillCount
    }



    private var displayText: String {
        "\(data.pillCount) / \(data.targetCount)"
    }

    private var fillFraction: Double {
        guard data.targetCount > 0 else { return 0 }
        return min(Double(data.pillCount) / Double(data.targetCount), 1.0)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {

            ThumbnailImageView(
                imagePath: data.barcodeImagePath,
                width: 80,
                height: 64,
                cornerRadius: 8,
                borderColor: appColors.primaryBackground,
                placeholderImageName: "dispense_placeholder",
                placeholderBackgroundColor: appColors.text,
                placeholderSize: CGSize(width: 28, height: 28),
                showImageBackground: appColors.primaryBackground
            )

            // Center info
            VStack(alignment: .leading, spacing: 5) {

                HStack{
                    Text("NDC \(data.ndc)")
                        .foregroundColor(appColors.primary)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    Text(data.drugType)
                        .foregroundColor(appColors.text)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                
                // Drug name
                Text(data.drugName)
                    .foregroundColor(appColors.text)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 10){
                    
                    // Date
                    Text(DateUtils.formatToUSDateTime(data.createdAt))
                        .foregroundColor(appColors.text.opacity(0.6))
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                    
                    
                    Text(data.bucketId)
                        .foregroundColor(appColors.text)
                        .font(.system(size: 12, weight: .regular))
                }
            }

            Spacer()

            // Right side
            HStack(spacing: 10) {
                VStack(spacing: 10) {
                    DonutProgressView(
                        fraction: fillFraction,
                        size: 30
                    )
                    Text(displayText)
                        .foregroundColor(appColors.text)
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .padding(.trailing, 8)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 12)
        .background(appColors.secondaryBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
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
