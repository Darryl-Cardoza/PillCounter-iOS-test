//
//  PdfExporter.swift
//  PillCounter
//
//  Created by Bhushan Patil on 15/04/26.
//

//
//  StockCountPDFExporter.swift
//  PillCounter
//
//  Generates a professional PDF report for a stock count batch.
//  Uses UIGraphicsPDFRenderer — no third-party dependencies.
//
//  Format:
//    Page 1:  Cover — App logo area, Batch ID, generated date, summary stats
//    Page N:  Data table — one row per grouped transaction (NDC, drug name,
//             lot, expiry, opened qty, sealed qty, total qty, status)
//
//  Usage:
//    let url = StockCountPDFExporter.export(
//        batch:        viewModel.currentBatch,
//        transactions: viewModel.groupedTransactions
//    )
//    // then present ShareSheet(url: url)
//

import UIKit
import PDFKit

// MARK: - Public Entry Point

enum StockCountPDFExporter {

    /// Generates a PDF and saves it to the temp directory.
    /// - Returns: The file URL, or nil if generation failed.
    @discardableResult
    static func export(
        batch: BatchCountEntity?,
        transactions: [GroupedTransaction]
    ) -> URL? {
        let renderer = PDFRenderer(batch: batch, transactions: transactions)
        return renderer.render()
    }
}

// MARK: - Layout Constants

private enum PDF {
    // Page
    static let pageSize      = CGSize(width: 595, height: 842)   // A4 portrait
    static let margin        = CGFloat(40)

    // Colours
    static let primary       = UIColor(red: 0.12, green: 0.47, blue: 0.71, alpha: 1) // brand blue
    static let accent        = UIColor(red: 0.20, green: 0.60, blue: 0.50, alpha: 1) // teal
    static let rowAlt        = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    static let headerBg      = UIColor(red: 0.12, green: 0.47, blue: 0.71, alpha: 1)
    static let headerText    = UIColor.white
    static let bodyText      = UIColor(white: 0.15, alpha: 1)
    static let mutedText     = UIColor(white: 0.45, alpha: 1)
    static let divider       = UIColor(white: 0.85, alpha: 1)
    static let successGreen  = UIColor(red: 0.18, green: 0.65, blue: 0.35, alpha: 1)
    static let warningOrange = UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
    static let dangerRed     = UIColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1)

    // Fonts
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    // Content width
    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
}

// MARK: - Renderer

private final class PDFRenderer {

    let batch:        BatchCountEntity?
    let transactions: [GroupedTransaction]

    // Table column definitions: (header title, relative width fraction)
    private let columns: [(title: String, fraction: CGFloat)] = [
        ("NDC",         0.14),
        ("Drug Name",   0.22),
        ("Lot",         0.11),
        ("Expiry",      0.10),
        ("Opened",      0.09),
        ("Sealed",      0.09),
        ("Total",       0.09),
        ("Status",      0.16),
    ]

    private let rowHeight:    CGFloat = 28
    private let headerHeight: CGFloat = 32

    init(batch: BatchCountEntity?, transactions: [GroupedTransaction]) {
        self.batch        = batch
        self.transactions = transactions
    }

    // MARK: - Render

    func render() -> URL? {
        let format = UIGraphicsPDFRendererFormat()
        let meta   = [
            kCGPDFContextTitle:   "Stock Count Report" as CFString,
            kCGPDFContextCreator: "PillCounter"        as CFString
        ]
        format.documentInfo = meta as [String: Any]

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: PDF.pageSize),
            format: format
        )

        do {
            let url = tempURL()
            try renderer.writePDF(to: url) { ctx in
                self.drawCoverPage(ctx)
                self.drawDataPages(ctx)
            }
            return url
        } catch {
            print("PDF export error: \(error)")
            return nil
        }
    }

    // MARK: - Cover Page

    private func drawCoverPage(_ ctx: UIGraphicsPDFRendererContext) {
        ctx.beginPage()
        let bounds = CGRect(origin: .zero, size: PDF.pageSize)

        // ── Header band ───────────────────────────────────────────────────────
        let headerRect = CGRect(x: 0, y: 0, width: PDF.pageSize.width, height: 160)
        PDF.primary.setFill()
        UIBezierPath(rect: headerRect).fill()

        // App name
        draw("PillCounter", at: CGPoint(x: PDF.margin, y: 40),
             font: PDF.font(28, weight: .bold), color: .white)

        // Subtitle
        draw("Pharmacy Inventory Management",
             at: CGPoint(x: PDF.margin, y: 76),
             font: PDF.font(13, weight: .regular), color: UIColor.white.withAlphaComponent(0.80))

        // ── Report title ──────────────────────────────────────────────────────
        draw("STOCK COUNT REPORT",
             at: CGPoint(x: PDF.margin, y: 190),
             font: PDF.font(22, weight: .bold), color: PDF.primary)

        let divY: CGFloat = 222
        PDF.primary.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: PDF.margin, y: divY))
        line.addLine(to: CGPoint(x: PDF.pageSize.width - PDF.margin, y: divY))
        line.lineWidth = 2
        line.stroke()

        // ── Batch info card ───────────────────────────────────────────────────
        let cardRect = CGRect(x: PDF.margin, y: 240,
                              width: PDF.contentWidth, height: 130)
        drawRoundedCard(cardRect, fillColor: PDF.rowAlt)

        let cardX = PDF.margin + 20
        var cardY: CGFloat = 258
        let labelFont  = PDF.font(11, weight: .medium)
        let valueFont  = PDF.font(13, weight: .semibold)

        func infoRow(_ label: String, _ value: String) {
            draw(label, at: CGPoint(x: cardX, y: cardY),
                 font: labelFont, color: PDF.mutedText)
            draw(value, at: CGPoint(x: cardX + 130, y: cardY),
                 font: valueFont, color: PDF.bodyText)
            cardY += 26
        }

        infoRow("Batch ID",       "\(batch?.batch_id ?? 0)")
        infoRow("Generated",      formattedNow())
        infoRow("Total Items",    "\(transactions.count)")
//        infoRow("Total Quantity", "\(transactions.reduce(0) { $0 + $1.totalCount })")

        // ── Summary stats row ─────────────────────────────────────────────────
        let statsY: CGFloat = 400
        drawSummaryStats(at: statsY)

        // ── Footer ────────────────────────────────────────────────────────────
        drawPageFooter(ctx, pageNumber: 1, totalPages: nil)
    }

    private func drawSummaryStats(at y: CGFloat) {
        let total    = transactions.count
//        let complete = transactions.filter { ($0.status ?? "").lowercased() == "complete" }.count
//        let pending  = total - complete

        let boxW: CGFloat = (PDF.contentWidth - 24) / 3
        let boxes: [(label: String, value: String, color: UIColor)] = [
            ("Total Items",    "\(total)",    PDF.primary),
//            ("Completed",      "\(complete)", PDF.successGreen),
//            ("Pending",        "\(pending)",  PDF.warningOrange),
        ]

        for (i, box) in boxes.enumerated() {
            let x = PDF.margin + CGFloat(i) * (boxW + 12)
            let rect = CGRect(x: x, y: y, width: boxW, height: 80)
            drawRoundedCard(rect, fillColor: box.color.withAlphaComponent(0.08))

            // Accent left border
            let borderRect = CGRect(x: x, y: y, width: 4, height: 80)
            let path = UIBezierPath(roundedRect: borderRect,
                                    byRoundingCorners: [.topLeft, .bottomLeft],
                                    cornerRadii: CGSize(width: 6, height: 6))
            box.color.setFill()
            path.fill()

            // Value
            draw(box.value,
                 at: CGPoint(x: x + 16, y: y + 14),
                 font: PDF.font(26, weight: .bold),
                 color: box.color)

            // Label
            draw(box.label,
                 at: CGPoint(x: x + 16, y: y + 52),
                 font: PDF.font(11, weight: .medium),
                 color: PDF.mutedText)
        }
    }

    // MARK: - Data Pages

    private func drawDataPages(_ ctx: UIGraphicsPDFRendererContext) {
        let usableHeight = PDF.pageSize.height - PDF.margin * 2 - 60 // footer space
        let startY: CGFloat = PDF.margin + 20

        var currentY    = startY
        var isFirstPage = true
        var pageNumber  = 2

        // ── Start first data page ─────────────────────────────────────────────
        ctx.beginPage()
        currentY = drawDataPageHeader(at: startY, pageNumber: pageNumber)

        for (index, txn) in transactions.enumerated() {
            // Check if we need a new page
            if currentY + rowHeight > usableHeight {
                drawPageFooter(ctx, pageNumber: pageNumber, totalPages: nil)
                ctx.beginPage()
                pageNumber += 1
                isFirstPage = false
                currentY = drawDataPageHeader(at: startY, pageNumber: pageNumber)
            }

            drawTableRow(txn: txn, rowIndex: index, at: currentY)
            currentY += rowHeight
        }

        // Draw bottom divider on last row
        PDF.divider.setStroke()
        let bottomLine = UIBezierPath()
        bottomLine.move(to: CGPoint(x: PDF.margin, y: currentY))
        bottomLine.addLine(to: CGPoint(x: PDF.pageSize.width - PDF.margin, y: currentY))
        bottomLine.lineWidth = 0.5
        bottomLine.stroke()

        drawPageFooter(ctx, pageNumber: pageNumber, totalPages: nil)
    }

    @discardableResult
    private func drawDataPageHeader(at y: CGFloat, pageNumber: Int) -> CGFloat {
        var currentY = y

        // Section title
        draw("TRANSACTION DETAILS",
             at: CGPoint(x: PDF.margin, y: currentY),
             font: PDF.font(14, weight: .bold), color: PDF.primary)
        currentY += 24

        draw("Batch ID: \(batch?.batch_id ?? 0)  ·  \(formattedNow())",
             at: CGPoint(x: PDF.margin, y: currentY),
             font: PDF.font(10), color: PDF.mutedText)
        currentY += 20

        // Table header row
        currentY = drawTableHeader(at: currentY)
        return currentY
    }

    // MARK: - Table Drawing

    private func drawTableHeader(at y: CGFloat) -> CGFloat {
        let rect = CGRect(x: PDF.margin, y: y,
                          width: PDF.contentWidth, height: headerHeight)
        PDF.headerBg.setFill()
        UIBezierPath(roundedRect: CGRect(x: PDF.margin, y: y,
                                         width: PDF.contentWidth, height: headerHeight),
                     cornerRadius: 6).fill()

        var x = PDF.margin
        for col in columns {
            let colW = PDF.contentWidth * col.fraction
            draw(col.title,
                 in: CGRect(x: x + 6, y: y + (headerHeight - 14) / 2,
                             width: colW - 8, height: 16),
                 font: PDF.font(10, weight: .semibold),
                 color: PDF.headerText,
                 alignment: .left)
            x += colW
        }
        return y + headerHeight
    }

    private func drawTableRow(txn: GroupedTransaction, rowIndex: Int, at y: CGFloat) {
        // Alternating row background
        if rowIndex % 2 == 0 {
            let rowRect = CGRect(x: PDF.margin, y: y,
                                 width: PDF.contentWidth, height: rowHeight)
            PDF.rowAlt.setFill()
            UIBezierPath(rect: rowRect).fill()
        }

        // Horizontal divider
        PDF.divider.setStroke()
        let divLine = UIBezierPath()
        divLine.move(to: CGPoint(x: PDF.margin, y: y))
        divLine.addLine(to: CGPoint(x: PDF.pageSize.width - PDF.margin, y: y))
        divLine.lineWidth = 0.5
        divLine.stroke()

        let textY    = y + (rowHeight - 12) / 2
        let cellFont = PDF.font(10)
        var x        = PDF.margin

        let values: [String] = [
            txn.ndc,
            txn.drugName ?? "—",
//            txn.lotNumber ?? "—",
//            txn.expiryDisplay ?? "—",
//            "\(txn.openedCount)",
//            "\(txn.sealedCount)",
//            "\(txn.totalCount)",
//            txn.status ?? "Pending",
        ]

        for (i, col) in columns.enumerated() {
            let colW  = PDF.contentWidth * col.fraction
            let value = values[i]

            // Status column gets a coloured pill badge
            if i == columns.count - 1 {
                drawStatusBadge(value,
                                in: CGRect(x: x + 4, y: y + 5,
                                            width: colW - 8, height: rowHeight - 10))
            } else {
                draw(value,
                     in: CGRect(x: x + 6, y: textY, width: colW - 10, height: 14),
                     font: cellFont, color: PDF.bodyText, alignment: .left)
            }
            x += colW
        }
    }

    private func drawStatusBadge(_ status: String, in rect: CGRect) {
        let lower  = status.lowercased()
        let color: UIColor = lower == "complete"  ? PDF.successGreen
                           : lower == "pending"   ? PDF.warningOrange
                           : lower == "cancelled" ? PDF.dangerRed
                           : PDF.mutedText

        let badgePath = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        color.withAlphaComponent(0.12).setFill()
        badgePath.fill()
        color.withAlphaComponent(0.60).setStroke()
        badgePath.lineWidth = 0.5
        badgePath.stroke()

        draw(status,
             in: rect,
             font: PDF.font(9, weight: .medium),
             color: color,
             alignment: .center)
    }

    // MARK: - Footer

    private func drawPageFooter(_ ctx: UIGraphicsPDFRendererContext,
                                 pageNumber: Int,
                                 totalPages: Int?) {
        let footerY = PDF.pageSize.height - PDF.margin + 10

        // Divider line
        PDF.divider.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: PDF.margin, y: footerY - 14))
        line.addLine(to: CGPoint(x: PDF.pageSize.width - PDF.margin, y: footerY - 14))
        line.lineWidth = 0.5
        line.stroke()

        // Left: App name
        draw("PillCounter — Stock Count Report",
             at: CGPoint(x: PDF.margin, y: footerY),
             font: PDF.font(9), color: PDF.mutedText)

        // Right: Page number
        let pageText = "Page \(pageNumber)"
        let pageSize = (pageText as NSString).size(withAttributes: [.font: PDF.font(9)])
        draw(pageText,
             at: CGPoint(x: PDF.pageSize.width - PDF.margin - pageSize.width, y: footerY),
             font: PDF.font(9), color: PDF.mutedText)
    }

    // MARK: - Drawing Helpers

    private func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private func draw(_ text: String,
                      in rect: CGRect,
                      font: UIFont,
                      color: UIColor,
                      alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment     = alignment
        para.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            font,
            .foregroundColor: color,
            .paragraphStyle:  para
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func drawRoundedCard(_ rect: CGRect, fillColor: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        fillColor.setFill()
        path.fill()
        PDF.divider.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    // MARK: - Utilities

    private func formattedNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yyyy, HH:mm"
        return f.string(from: Date())
    }

    private func tempURL() -> URL {
        let name = "StockCount_Batch\(batch?.batch_id ?? 0)_\(Int(Date().timeIntervalSince1970)).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
