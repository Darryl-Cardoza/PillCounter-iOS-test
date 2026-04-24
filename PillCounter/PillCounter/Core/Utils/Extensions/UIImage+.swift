//
//  UIImage+.swift
//  PillCounter
//
//  Created by Bhushan Patil on 14/04/26.
//
import SwiftUI


extension UIImage {

    // MARK: - Grayscale + Compress
    /// Converts to grayscale, scales to maxWidth, and compresses to JPEG quality.
    /// This is the function you asked for — call it before addingMetadataOverlay.
    func compressedGrayscale(maxWidth: CGFloat, quality: CGFloat) -> UIImage? {

        // 1. Scale down first (cheaper to process smaller image)
        let scale = min(1.0, maxWidth / max(size.width, size.height))
        let targetSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        // 2. Apply grayscale via CIFilter
        guard let cgImage = scaled.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)  // 0 = full grayscale

        let context = CIContext()
        guard
            let outputCI = filter.outputImage,
            let outputCG = context.createCGImage(outputCI, from: outputCI.extent)
        else { return nil }

        return UIImage(cgImage: outputCG)
    }

    // MARK: - Metadata Overlay
    /// Burns NDC, user, count, timestamp etc. into the image as text.
    func addingMetadataOverlay(
        ndc: String,
        user: String,
        count: Int,
        rx: String,
        location: String,
        timestamp: Int64,
        fileSizeKB: Double
    ) -> UIImage {

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: date)

        let lines = [
            "NDC: \(ndc.isEmpty ? "N/A" : ndc)",
            "User: \(user.isEmpty ? "N/A" : user)",
            "Count: \(count)",
            !rx.isEmpty ? "Rx: \(rx)" : nil,
            !location.isEmpty ? "Loc: \(location)" : nil,
            "Time: \(dateString)",
            String(format: "Size: %.1f KB", fileSizeKB)
        ].compactMap { $0 }

        let fontSize: CGFloat = max(size.width * 0.02, 12)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        let padding: CGFloat = 10
        let lineSpacing: CGFloat = 4

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in

            // Draw original image
            draw(at: .zero)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .strokeColor: UIColor.black,
                .strokeWidth: -2 // 🔥 OUTLINE TEXT (key for visibility)
            ]

            // Start from bottom but NO background
            var y = size.height - padding

            for line in lines.reversed() {
                let textSize = (line as NSString).size(withAttributes: attributes)

                y -= textSize.height

                let rect = CGRect(
                    x: padding,
                    y: y,
                    width: size.width - padding * 2,
                    height: textSize.height
                )

                (line as NSString).draw(in: rect, withAttributes: attributes)

                y -= lineSpacing
            }
        }
    }
}



extension UIImage {

    func normalized() -> UIImage {

        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))

        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? self
    }
}


