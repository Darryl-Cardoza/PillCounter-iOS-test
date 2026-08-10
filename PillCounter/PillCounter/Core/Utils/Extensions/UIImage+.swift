//
//  UIImage+.swift
//  PillCounter
//
//  Created by Bhushan Patil on 14/04/26.

import SwiftUI

extension UIImage {

    // MARK: - Grayscale + Compress
    func compressedGrayscale(maxWidth: CGFloat, quality: CGFloat) -> UIImage? {
        let scale = min(1.0, maxWidth / max(size.width, size.height))
        let targetSize = CGSize(
            width:  (size.width  * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let cgImage = scaled.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0,     forKey: kCIInputSaturationKey)

        let context = CIContext()
        guard
            let outputCI = filter.outputImage,
            let outputCG = context.createCGImage(outputCI, from: outputCI.extent)
        else { return nil }

        return UIImage(cgImage: outputCG)
    }

    // MARK: - Metadata Overlay
    // Renders a compact two-column audit block in the bottom-left corner.
    // Font is ~1.8% of image width — readable when zoomed, unobtrusive at thumbnail size.
    // White text + thick black stroke keeps it legible over any background.
    func addingMetadataOverlay(
        ndc:           String,
        substituteNdc: String,   // omitted when empty
        workflowStep:  String,   // "Target Verification", "Recount", "Vial", etc.
        count:         Int,
        targetCount:   Int32?,
        timestamp:     Int64,
        userInitials:  String,
        geolocation:   String,   // "37.33° N, 122.03° W — 94025"
        rx:            String,
        fileSizeKB:    Double,
        lotNumber:     String? = nil,
        expirationDate: String? = nil,
        serialNumber:  String? = nil
    ) -> UIImage {

        // ── Timestamp ───────────────────────────────────────────────────
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm"
        let dateString = dateFmt.string(from: date)

        // ── Build rows (label · value) ───────────────────────────────────
        var rows: [(String, String)] = []

        func add(_ label: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty else { return }
            rows.append((label, v))
        }

        add("NDC",    ndc)
        add("ReqNDC", substituteNdc)
        add("Step",   workflowStep)

        if let target = targetCount {
            add("Count", "\(count)/\(target)")
        } else {
            add("Count", "\(count)")
        }

        add("User",   userInitials)
        add("Rx",     rx)
        add("Loc",    geolocation)
        add("Date",   dateString)
        add("Size",   String(format: "%.1f KB", fileSizeKB))
        add("Lot",    lotNumber ?? "")
        add("Exp",    expirationDate ?? "")
        add("Serial", serialNumber ?? "")

        // ── Typography ───────────────────────────────────────────────────
        // ~1.8% of image width, floor at 10 pt so it stays readable on small images
        let fontSize: CGFloat = max(size.width * 0.018, 10)
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail

        // Stroke drawn outward (negative value = outside the fill)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: UIColor.white,
            .strokeColor:     UIColor.black,
            .strokeWidth:     -2.5,          // thick enough to read on any bg
            .paragraphStyle:  para
        ]

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: UIColor(white: 0.88, alpha: 1),
            .strokeColor:     UIColor.black,
            .strokeWidth:     -2.0,
            .paragraphStyle:  para
        ]

        // ── Layout constants ─────────────────────────────────────────────
        let margin:    CGFloat = size.width * 0.015   // distance from image edge
        let rowH:      CGFloat = fontSize + 3
        let gap:       CGFloat = 4                    // space between label & value
        let labelColW: CGFloat = fontSize * 4.2       // fixed width for labels
        let valueColW: CGFloat = size.width * 0.38    // value gets up to 38% of width

        let blockH = rowH * CGFloat(rows.count)
        let blockY = size.height - margin - blockH    // pin to bottom-left

        // ── Render ───────────────────────────────────────────────────────
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            draw(at: .zero)

            // ── Full-width backing panel (0.5 black) ─────────────────────────
            // Sits behind the metadata so both the photo and the text stay
            // legible regardless of the underlying image content. Padded a little
            // above/below the text block and spanning the full image width.
            let panelPad: CGFloat = margin * 0.5
            let panelRect = CGRect(
                x:      0,
                y:      blockY - panelPad,
                width:  size.width,
                height: blockH + panelPad * 2
            )
            UIColor.black.withAlphaComponent(0.5).setFill()
            ctx.cgContext.fill(panelRect)

            for (i, (label, value)) in rows.enumerated() {
                let y = blockY + CGFloat(i) * rowH

                // Label column
                let labelRect = CGRect(
                    x:      margin,
                    y:      y,
                    width:  labelColW,
                    height: rowH
                )
                (label as NSString).draw(in: labelRect, withAttributes: labelAttrs)

                // Value column
                let valueRect = CGRect(
                    x:      margin + labelColW + gap,
                    y:      y,
                    width:  valueColW,
                    height: rowH
                )
                (value as NSString).draw(in: valueRect, withAttributes: textAttrs)
            }
        }
    }
}

// MARK: - Normalize orientation
extension UIImage {

    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? self
    }
}
