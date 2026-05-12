//
//  PDFShareService.swift
//  PillCounter
//
//  Created by HC on 17/12/25.
//

import SwiftUI
import UIKit

// MARK: - ShareSheet (SwiftUI wrapper for UIActivityViewController)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

final class PDFShareService: ObservableObject {

    @Published var isLoading: Bool = false

    static let shared = PDFShareService()
    private init() {}

    // MARK: - Public API
    func generateAndShareDrugHistoryPDF(
        drugName: String,
        totalCount: Int,
        ndc: String,
        expiry: String,
        lotNo: String,
        date: String,
        time: String,
        note: String?,
        presentingVC: UIViewController
    ) {

        // 1️⃣ Show loader immediately
        DispatchQueue.main.async {
            self.isLoading = true
        }

        // 2️⃣ Generate PDF in background
        DispatchQueue.global(qos: .userInitiated).async {

            let pdfData = self.generatePDF(
                drugName: drugName,
                totalCount: totalCount,
                ndc: ndc,
                expiry: expiry,
                lotNo: lotNo,
                date: date,
                time: time,
                note: note
            )

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "DrugHistory_\(UUID().uuidString).pdf"
                )

            do {
                try pdfData.write(to: tempURL)

                // 3️⃣ Present Share Sheet on Main Thread
                DispatchQueue.main.async {

                    let activityVC = UIActivityViewController(
                        activityItems: [tempURL],
                        applicationActivities: nil
                    )

                    // iPad popover safety
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = presentingVC.view
                        popover.sourceRect = CGRect(
                            x: presentingVC.view.bounds.midX,
                            y: presentingVC.view.bounds.midY,
                            width: 0,
                            height: 0
                        )
                        popover.permittedArrowDirections = []
                    }

                    // 4️⃣ Cleanup + hide loader
                    activityVC.completionWithItemsHandler = { _, _, _, _ in
                        try? FileManager.default.removeItem(at: tempURL)
                        self.isLoading = false
                    }

                    presentingVC.present(activityVC, animated: true)
                }

            } catch {
                // 5️⃣ Failure case
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("❌ Failed to create Drug History PDF: \(error)")
                }
            }
        }
    }

}

// MARK: - PDF Generation
extension PDFShareService {

    fileprivate func generatePDF(
        drugName: String,
        totalCount: Int,
        ndc: String,
        expiry: String,
        lotNo: String,
        date: String,
        time: String,
        note: String?
    ) -> Data {

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()

            let centerX = pageRect.midX
            var y: CGFloat = 40

            // Title
            drawCenteredText(
                "Drug History Details",
                font: .boldSystemFont(ofSize: 20),
                y: &y,
                centerX: centerX
            )

            y += 20

            // Section Heading
            drawCenteredText(
                "Drug Information",
                font: .boldSystemFont(ofSize: 16),
                y: &y,
                centerX: centerX
            )

            y += 20

            // TABLE DATA
            let tableData: [(String, String)] = [
                ("Drug Name", drugName),
                ("Total Count", "\(totalCount)"),
                ("NDC / GTIN 14", ndc),
                ("Expiry", expiry),
                ("Lot No", lotNo),
                ("Date", date),
                ("Time", time),
            ]

            // Draw Table
            let tableWidth: CGFloat = 420
            let labelColumnWidth: CGFloat = 180
            let rowHeight: CGFloat = 34

            let tableX = centerX - tableWidth / 2
            drawTable(
                data: tableData,
                startX: tableX,
                startY: &y,
                tableWidth: tableWidth,
                labelColumnWidth: labelColumnWidth,
                rowHeight: rowHeight
            )

            y += 30

            // Notes
            drawCenteredText(
                "Note",
                font: .boldSystemFont(ofSize: 14),
                y: &y,
                centerX: centerX
            )

            y += 10

            drawMultilineCenteredText(
                note?.isEmpty == false ? note! : "—",
                y: &y,
                centerX: centerX,
                width: 420
            )

            y += 40

            // Footer
            let generatedOn = DateFormatter.localizedString(
                from: Date(),
                dateStyle: .medium,
                timeStyle: .short
            )

            drawCenteredText(
                "Generated on \(generatedOn)",
                font: .italicSystemFont(ofSize: 10),
                y: &y,
                centerX: centerX
            )
        }
    }
}

// MARK: - Drawing Helpers
extension PDFShareService {

    fileprivate func drawCenteredText(
        _ text: String,
        font: UIFont,
        y: inout CGFloat,
        centerX: CGFloat
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = text.size(withAttributes: attributes)

        let rect = CGRect(
            x: centerX - size.width / 2,
            y: y,
            width: size.width,
            height: size.height
        )

        text.draw(in: rect, withAttributes: attributes)
        y += size.height
    }

    fileprivate func drawTable(
        data: [(String, String)],
        startX: CGFloat,
        startY: inout CGFloat,
        tableWidth: CGFloat,
        labelColumnWidth: CGFloat,
        rowHeight: CGFloat
    ) {

        let context = UIGraphicsGetCurrentContext()
        let valueColumnWidth = tableWidth - labelColumnWidth

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12)
        ]

        for (label, value) in data {
            let rowY = startY

            // Draw borders
            context?.stroke(
                CGRect(
                    x: startX,
                    y: rowY,
                    width: tableWidth,
                    height: rowHeight
                ))

            context?.stroke(
                CGRect(
                    x: startX + labelColumnWidth,
                    y: rowY,
                    width: 0,
                    height: rowHeight
                ))

            // Label text
            let labelRect = CGRect(
                x: startX + 8,
                y: rowY + 8,
                width: labelColumnWidth - 16,
                height: rowHeight - 16
            )
            label.draw(in: labelRect, withAttributes: textAttributes)

            // Value text
            let valueRect = CGRect(
                x: startX + labelColumnWidth + 8,
                y: rowY + 8,
                width: valueColumnWidth - 16,
                height: rowHeight - 16
            )
            value.draw(in: valueRect, withAttributes: textAttributes)

            startY += rowHeight
        }
    }

    fileprivate func drawMultilineCenteredText(
        _ text: String,
        y: inout CGFloat,
        centerX: CGFloat,
        width: CGFloat
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle,
        ]

        let rect = CGRect(
            x: centerX - width / 2,
            y: y,
            width: width,
            height: 200
        )

        text.draw(in: rect, withAttributes: attributes)
        y += 200
    }
}

extension PDFShareService {

    func generateAndShareUserHistoryPDF(
        selectedDate: String,
        transactions: [PillCountTransactionEntity],
        presentingVC: UIViewController
    ) {

        DispatchQueue.main.async {
            self.isLoading = true
        }

        DispatchQueue.global(qos: .userInitiated).async {

            let pdfData = self.generateUserHistoryPDF(
                selectedDate: selectedDate,
                transactions: transactions
            )

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "DrugHistoryReport_\(UUID().uuidString).pdf"
                )

            do {
                try pdfData.write(to: tempURL)

                DispatchQueue.main.async {

                    let activityVC = UIActivityViewController(
                        activityItems: [tempURL],
                        applicationActivities: nil
                    )

                    // iPad safety
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = presentingVC.view
                        popover.sourceRect = CGRect(
                            x: presentingVC.view.bounds.midX,
                            y: presentingVC.view.bounds.midY,
                            width: 0,
                            height: 0
                        )
                        popover.permittedArrowDirections = []
                    }

                    activityVC.completionWithItemsHandler = { _, _, _, _ in
                        try? FileManager.default.removeItem(at: tempURL)
                        self.isLoading = false
                    }

                    presentingVC.present(activityVC, animated: true)
                }

            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("Failed to create history PDF: \(error)")
                }
            }
        }
    }

}

extension PDFShareService {

    fileprivate func generateUserHistoryPDF(
        selectedDate: String,
        transactions: [PillCountTransactionEntity]
    ) -> Data {

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()

            let centerX = pageRect.midX
            var y: CGFloat = 40

            // Title
            drawCenteredText(
                "Drug History Report",
                font: .boldSystemFont(ofSize: 20),
                y: &y,
                centerX: centerX
            )

            y += 16

            // Selected Date
            drawCenteredText(
                "Selected Date : \(selectedDate)",
                font: .systemFont(ofSize: 14, weight: .medium),
                y: &y,
                centerX: centerX
            )

            y += 30

            // Table setup
            let tableWidth: CGFloat = 520
            let startX = centerX - tableWidth / 2
            let rowHeight: CGFloat = 30

            let columnWidths: [CGFloat] = [
                150,  // Drug Name
                120,  // NDC
                80,  // Pills Count
                80,  // Status
                90,  // Count Type
            ]

            // Table Header
            let headers = [
                "Drug Name",
                "NDC / GTIN-14",
                "Pills Count",
                "Status",
                "Count Type",
            ]

            drawTableRow(
                texts: headers,
                x: startX,
                y: &y,
                widths: columnWidths,
                height: rowHeight,
                font: .boldSystemFont(ofSize: 12),
                background: UIColor.systemGray5
            )

            // Table Rows
            for txn in transactions {

                let pillCount =
                    (txn.pillCountTransactionDetails
                    as? Set<PillCountTransactionDetailsEntity>)?
                    .reduce(0) { $0 + Int($1.pill_count) } ?? 0

                let rowValues = [
                    txn.drug?.drug_name ?? "—",
                    txn.drug?.ndc ?? "—",
                    "\(pillCount)",
                    txn.status ?? "—",
                    convertCountType(txn.count_type),
                ]

                drawTableRow(
                    texts: rowValues,
                    x: startX,
                    y: &y,
                    widths: columnWidths,
                    height: rowHeight,
                    font: .systemFont(ofSize: 11),
                    background: .white
                )

                // New page if required
                if y > pageRect.height - 80 {
                    context.beginPage()
                    y = 40
                }
            }

            y += 30

            // Footer
            let generatedOn = DateFormatter.localizedString(
                from: Date(),
                dateStyle: .medium,
                timeStyle: .short
            )

            drawCenteredText(
                "Generated on \(generatedOn)",
                font: .italicSystemFont(ofSize: 10),
                y: &y,
                centerX: centerX
            )
        }
    }
}
extension PDFShareService {

    fileprivate func drawTableRow(
        texts: [String],
        x: CGFloat,
        y: inout CGFloat,
        widths: [CGFloat],
        height: CGFloat,
        font: UIFont,
        background: UIColor
    ) {

        let context = UIGraphicsGetCurrentContext()
        var currentX = x

        for (index, text) in texts.enumerated() {
            let width = widths[index]

            let rect = CGRect(
                x: currentX,
                y: y,
                width: width,
                height: height
            )

            // Background
            context?.setFillColor(background.cgColor)
            context?.fill(rect)

            // Border
            context?.setStrokeColor(UIColor.black.cgColor)
            context?.stroke(rect)

            // Text
            let textRect = rect.insetBy(dx: 6, dy: 6)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font
            ]
            text.draw(in: textRect, withAttributes: attributes)

            currentX += width
        }

        y += height
    }
}
extension PDFShareService {

    fileprivate func convertCountType(_ value: String?) -> String {
        guard let value = value?.uppercased() else { return "—" }

        switch value {
        case "FIXED":
            return "Fixed"
        case "REGULAR":
            return "Regular"
        default:
            return value
        }
    }
}
