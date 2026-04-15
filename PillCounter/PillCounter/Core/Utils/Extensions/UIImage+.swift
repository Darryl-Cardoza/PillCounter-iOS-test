//
//  UIImage+.swift
//  PillCounter
//
//  Created by Bhushan Patil on 14/04/26.
//
import SwiftUI

extension UIImage {

    func compressedGrayscale(maxWidth: CGFloat = 1080, quality: CGFloat = 0.5) -> UIImage? {

        // 1. Resize
        let aspectRatio = size.height / size.width
        let newSize = CGSize(width: maxWidth, height: maxWidth * aspectRatio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // 2. Convert to grayscale
        guard let ciImage = CIImage(image: resized) else { return resized }

        let filter = CIFilter(name: "CIPhotoEffectMono")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)

        let context = CIContext()
        if let output = filter?.outputImage,
           let cgImage = context.createCGImage(output, from: output.extent) {
            return UIImage(cgImage: cgImage)
        }

        return resized
    }

    func jpegDataCompressed(_ quality: CGFloat = 0.5) -> Data? {
        return self.jpegData(compressionQuality: quality)
    }
}

extension UIImage {

    func addingMetadataOverlay(
        ndc: String,
        user: String,
        count: Int,
        rx: String,
        location: String,
        timestamp: Int64,
        fileSizeKB: Double
    ) -> UIImage {

        let formattedTime = DateUtils.formatToDayMonthYearTime(timestamp)

        let text = """
        NDC: \(ndc)   RX: \(rx)
        User: \(user)   Count: \(count)
        Location: \(location)
        Time: \(formattedTime)
        Size: \(String(format: "%.1f KB", fileSizeKB))
        """

        let padding: CGFloat = 16
        let font = UIFont.systemFont(ofSize: 22, weight: .medium) // 👈 reduced

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]

        let maxTextWidth = size.width - (padding * 2)
        let boundingRect = NSString(string: text).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        let textHeight = boundingRect.height + (padding * 2)

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            draw(at: .zero)

            let rect = CGRect(
                x: 0,
                y: size.height - textHeight,
                width: size.width,
                height: textHeight
            )

            // Background
            ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
            ctx.cgContext.fill(rect)

            // Draw text
            text.draw(
                in: rect.insetBy(dx: padding, dy: padding),
                withAttributes: attributes
            )
        }
    }
}
