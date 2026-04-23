//
//  PillScanDetailItem.swift
//  PillCounter
//
//  Created by Bhushan Patil on 23/04/26.
//
import SwiftUI

// MARK: - Data Model
struct PillScanDetailItem: Identifiable {
    let id: Int64          // txn_details_id
    let imagePath: String?
    let pillCount: Int
    let capturedAt: Int64  // timestamp ms
}


struct PillScanDetailCard: View {
 
    let detail: PillCountTransactionDetailsEntity
    let isEditing: Bool
    let isSelected: Bool
 
    @EnvironmentObject private var appColors: AppColors
 
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
 
            ZStack {
                Rectangle()
                    .fill(appColors.secondaryBackground)

                imageView(path: detail.image_path)
                    .frame(height: 120)
                    .padding(8)
            }
            .frame(height: 160)
            .clipShape(TopRoundedRectangle(radius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(detail.pill_count)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(appColors.primary)

                Text(DateUtils.formatToUSDateTime(detail.created_at))
                    .font(.system(size: 11))
                    .foregroundColor(appColors.text.opacity(0.65))
            }
            .padding(.horizontal,12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appColors.secondaryBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .selectableEffect(isSelected: isSelected, highlightColor: appColors.secondary)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    struct TopRoundedRectangle: Shape {
        var radius: CGFloat = 10

        func path(in rect: CGRect) -> Path {
            var path = Path()

            path.move(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(
                to: CGPoint(x: radius, y: 0),
                control: CGPoint(x: 0, y: 0)
            )
            path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: radius),
                control: CGPoint(x: rect.width, y: 0)
            )
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()

            return path
        }
    }
 
    // MARK: - Image
    @ViewBuilder
    private func imageView(path: String?) -> some View {
        if let path,
           let image = PhotoFileManager.shared.loadImage(from: path)
        {
            image
                .resizable()
                .scaledToFit()
                .clipShape(RoundedCorner(radius: 10))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(appColors.text.opacity(0.5), lineWidth: 1)
                .frame(width: 140, height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray.opacity(0.4))
                )
        }
    }
 
    // MARK: - Selection circle
    private var selectionCircle: some View {
        ZStack {
            Circle()
                .fill(isSelected ? appColors.secondary : Color.black.opacity(0.45))
                .frame(width: 22, height: 22)
 
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
    }

}
 
