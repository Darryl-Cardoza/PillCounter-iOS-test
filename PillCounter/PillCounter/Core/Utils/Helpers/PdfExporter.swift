//
//  PdfExporter.swift
//  PillCounter
//
//  Created by Bhushan Patil on 15/04/26.
//
//  Generates a PDF that mirrors the batch detail UI:
//    • Header band — Batch ID + generated date
//    • Summary row — Total NDC count + total pills
//    • Optional Note section
//    • One "card" per GroupedTransaction:
//        – Drug name + NDC + total (header row)
//        – Sealed Bottles section with lot/expiry/qty rows + total
//        – Opened Bottles section with lot/expiry/qty rows + total
//    • Page numbers in footer
//

import UIKit

// MARK: - Public Entry Point

enum StockCountPDFExporter {

    /// Generates a PDF for a stock-count batch and saves it to the temp directory.
    /// - Returns: The file URL, or nil if generation failed.
    @discardableResult
    static func export(
        batch: BatchCountEntity?,
        transactions: [GroupedTransaction]
    ) -> URL? {
        BatchPDFRenderer(batch: batch, transactions: transactions, note: nil).render()
    }

    @discardableResult
    static func export(
        batch: BatchCountEntity?,
        transactions: [GroupedTransaction],
        note: String?
    ) -> URL? {
        BatchPDFRenderer(batch: batch, transactions: transactions, note: note).render()
    }
}

// MARK: - Layout Constants

private enum PDF {
    static let pageWidth:  CGFloat = 595
    static let pageHeight: CGFloat = 842
    static let margin:     CGFloat = 30
    static var contentWidth: CGFloat { pageWidth - margin * 2 }

    // Colours
    static let brand      = UIColor(red: 0.12, green: 0.47, blue: 0.71, alpha: 1)
    static let brandLight = UIColor(red: 0.12, green: 0.47, blue: 0.71, alpha: 0.10)
    static let accent     = UIColor(red: 0.18, green: 0.60, blue: 0.48, alpha: 1)   // teal total
    static let cardBg     = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    static let divider    = UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
    static let bodyText   = UIColor(white: 0.15, alpha: 1)
    static let mutedText  = UIColor(white: 0.45, alpha: 1)
    static let sectionBg  = UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Renderer

private final class BatchPDFRenderer {

    let batch:        BatchCountEntity?
    let transactions: [GroupedTransaction]
    let note:         String?

    private var pageNumber = 0
    private var ctx: UIGraphicsPDFRendererContext!

    init(batch: BatchCountEntity?, transactions: [GroupedTransaction], note: String?) {
        self.batch        = batch
        self.transactions = transactions
        self.note         = note
    }

    // MARK: - Entry

    func render() -> URL? {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle   as String: "Stock Count Report",
            kCGPDFContextCreator as String: "PillCounter"
        ]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: PDF.pageWidth, height: PDF.pageHeight),
            format: format
        )
        do {
            let url = tempURL()
            try renderer.writePDF(to: url) { ctx in
                self.ctx = ctx
                self.renderAll()
            }
            return url
        } catch {
            print("PDF export error: \(error)")
            return nil
        }
    }

    // MARK: - Page Flow

    private func renderAll() {
        beginPage()
        var y = drawPageHeader()

        y = drawSummaryCard(at: y)

        if let note = note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            y = drawNoteSection(note, at: y)
        }

        for txn in transactions {
            y = drawTransactionCard(txn, at: y)
        }

        drawFooter()
    }

    // MARK: - New Page

    private func beginPage() {
        ctx.beginPage()
        pageNumber += 1
    }

    private func checkPageBreak(neededHeight: CGFloat, currentY: CGFloat) -> CGFloat {
        let footerReserve: CGFloat = 50
        if currentY + neededHeight > PDF.pageHeight - footerReserve {
            drawFooter()
            beginPage()
            return drawContinuationHeader()
        }
        return currentY
    }

    // MARK: - Page Header

    private func drawPageHeader() -> CGFloat {
        // Blue band
        let bandH: CGFloat = 70
        fill(CGRect(x: 0, y: 0, width: PDF.pageWidth, height: bandH), color: PDF.brand)

        // App title
        draw("PillCounter",
             at: CGPoint(x: PDF.margin, y: 14),
             font: PDF.font(18, weight: .bold), color: .white)

        // Batch ID right-aligned
        let batchText = "BATCH ID  \(batch?.batch_id ?? 0)"
        let batchSize = textSize(batchText, font: PDF.font(13, weight: .semibold))
        draw(batchText,
             at: CGPoint(x: PDF.pageWidth - PDF.margin - batchSize.width, y: 14),
             font: PDF.font(13, weight: .semibold), color: .white)

        // Generated date below
        let genText = "Generated: \(formattedNow())"
        let genSize = textSize(genText, font: PDF.font(10))
        draw(genText,
             at: CGPoint(x: PDF.pageWidth - PDF.margin - genSize.width, y: 36),
             font: PDF.font(10), color: UIColor.white.withAlphaComponent(0.80))

        return bandH + 18
    }

    private func drawContinuationHeader() -> CGFloat {
        let bandH: CGFloat = 44
        fill(CGRect(x: 0, y: 0, width: PDF.pageWidth, height: bandH), color: PDF.brand)

        draw("PillCounter — Batch \(batch?.batch_id ?? 0) (cont.)",
             at: CGPoint(x: PDF.margin, y: 14),
             font: PDF.font(12, weight: .semibold), color: .white)

        return bandH + 14
    }

    // MARK: - Summary Card

    private func drawSummaryCard(at y: CGFloat) -> CGFloat {
        let totalNdc   = transactions.count
        let totalPills = transactions.reduce(0) { $0 + Int($1.total) }

        let cardH: CGFloat = 58
        let cardY = y
        drawRoundedRect(CGRect(x: PDF.margin, y: cardY, width: PDF.contentWidth, height: cardH),
                        fill: PDF.cardBg, stroke: PDF.divider, radius: 8)

        // Left: NDC count
        draw("TOTAL NDC COUNT",
             at: CGPoint(x: PDF.margin + 14, y: cardY + 10),
             font: PDF.font(9, weight: .semibold), color: PDF.mutedText)

        draw("\(totalNdc)",
             at: CGPoint(x: PDF.margin + 14, y: cardY + 26),
             font: PDF.font(18, weight: .bold), color: PDF.brand)

        // Right: total pills
        let pillsLabel = "TOTAL PILLS"
        let pillsValue = "\(totalPills)"
        let vw = textSize(pillsValue, font: PDF.font(18, weight: .bold)).width
        let lw = textSize(pillsLabel, font: PDF.font(9, weight: .semibold)).width
        let rx = PDF.margin + PDF.contentWidth - max(vw, lw) - 14

        draw(pillsLabel,
             at: CGPoint(x: rx, y: cardY + 10),
             font: PDF.font(9, weight: .semibold), color: PDF.mutedText)

        draw(pillsValue,
             at: CGPoint(x: rx, y: cardY + 26),
             font: PDF.font(18, weight: .bold), color: PDF.accent)

        return cardY + cardH + 14
    }

    // MARK: - Note Section

    private func drawNoteSection(_ note: String, at startY: CGFloat) -> CGFloat {
        let textWidth  = PDF.contentWidth - 28
        let textHeight = estimateTextHeight(note, font: PDF.font(11), width: textWidth)
        let sectionH   = textHeight + 36

        var y = checkPageBreak(neededHeight: sectionH + 8, currentY: startY)

        drawRoundedRect(CGRect(x: PDF.margin, y: y, width: PDF.contentWidth, height: sectionH),
                        fill: PDF.sectionBg, stroke: PDF.divider, radius: 8)

        draw("NOTE",
             at: CGPoint(x: PDF.margin + 14, y: y + 10),
             font: PDF.font(10, weight: .semibold), color: PDF.mutedText)

        drawWrapped(note,
                    in: CGRect(x: PDF.margin + 14, y: y + 26, width: textWidth, height: textHeight),
                    font: PDF.font(11), color: PDF.bodyText)

        return y + sectionH + 14
    }

    // MARK: - Transaction Card

    private func drawTransactionCard(_ txn: GroupedTransaction, at startY: CGFloat) -> CGFloat {
        // Estimate card height before drawing so we can page-break if needed
        let cardH = estimateCardHeight(txn)
        var y = checkPageBreak(neededHeight: cardH + 10, currentY: startY)

        let cardX = PDF.margin
        let cardW = PDF.contentWidth

        // Card background
        drawRoundedRect(CGRect(x: cardX, y: y, width: cardW, height: cardH),
                        fill: PDF.cardBg, stroke: PDF.divider, radius: 10)

        // ── Header row ──────────────────────────────────────────────────────
        let headerH: CGFloat = 44
        let headerPath = UIBezierPath(roundedRect: CGRect(x: cardX, y: y, width: cardW, height: headerH),
                                      byRoundingCorners: [.topLeft, .topRight],
                                      cornerRadii: CGSize(width: 10, height: 10))
        PDF.brand.withAlphaComponent(0.08).setFill()
        headerPath.fill()

        draw(txn.drugName,
             at: CGPoint(x: cardX + 14, y: y + 10),
             font: PDF.font(13, weight: .semibold), color: PDF.bodyText)

        draw(txn.ndc,
             at: CGPoint(x: cardX + 14, y: y + 27),
             font: PDF.font(10), color: PDF.mutedText)

        // Total (right)
        let totalStr  = "\(txn.total)"
        let totalW    = textSize(totalStr, font: PDF.font(16, weight: .bold)).width
        draw(totalStr,
             at: CGPoint(x: cardX + cardW - totalW - 14, y: y + 14),
             font: PDF.font(16, weight: .bold), color: PDF.accent)

        y += headerH

        // Thin divider under header
        drawHLine(x: cardX + 10, y: y, width: cardW - 20, color: PDF.divider)
        y += 1

        // ── Sealed Bottles ──────────────────────────────────────────────────
        let sealedDetails = txn.lotDetails.filter { $0.sealedQty > 0 }
        y = drawSubSection(title: "Sealed Bottles",
                           count: "\(txn.sealedBottles)",
                           details: sealedDetails.map { (lot: $0.lot, expiry: $0.expiry, qty: Int($0.sealedQty)) },
                           cardX: cardX, cardW: cardW, y: y)

        // ── Opened Bottles ──────────────────────────────────────────────────
        let openDetails = txn.lotDetails.filter { $0.openQty > 0 }
        y = drawSubSection(title: "Opened Bottles",
                           count: "\(txn.openPills)",
                           details: openDetails.map { (lot: $0.lot, expiry: $0.expiry, qty: Int($0.openQty)) },
                           cardX: cardX, cardW: cardW, y: y)

        return y + 14   // gap between cards
    }

    // MARK: - Sub-section (Sealed / Opened)

    private func drawSubSection(
        title: String,
        count: String,
        details: [(lot: String, expiry: String, qty: Int)],
        cardX: CGFloat,
        cardW: CGFloat,
        y: CGFloat
    ) -> CGFloat {
        var y = y
        let rowH: CGFloat = 26
        let inset: CGFloat = 14

        // Section title row
        fill(CGRect(x: cardX, y: y, width: cardW, height: rowH + 2), color: PDF.sectionBg)

        draw(title,
             at: CGPoint(x: cardX + inset, y: y + 6),
             font: PDF.font(11, weight: .semibold), color: PDF.bodyText)

        let cw = textSize(count, font: PDF.font(11, weight: .semibold)).width
        draw(count,
             at: CGPoint(x: cardX + cardW - cw - inset, y: y + 6),
             font: PDF.font(11, weight: .semibold), color: PDF.bodyText)

        y += rowH + 2

        if !details.isEmpty {
            // Column header
            drawLotColumnHeader(cardX: cardX, cardW: cardW, y: y)
            y += 20

            var sectionTotal = 0
            for detail in details {
                drawHLine(x: cardX + 10, y: y, width: cardW - 20, color: PDF.divider)
                y += 1
                y = drawLotRow(lot: detail.lot, expiry: detail.expiry, qty: detail.qty,
                                cardX: cardX, cardW: cardW, y: y)
                sectionTotal += detail.qty
            }

            // Total row
            drawHLine(x: cardX + 10, y: y, width: cardW - 20, color: PDF.divider)
            y += 1
            y = drawLotTotalRow(total: sectionTotal, cardX: cardX, cardW: cardW, y: y)
        }

        drawHLine(x: cardX + 10, y: y, width: cardW - 20, color: PDF.divider)
        y += 1

        return y
    }

    private func drawLotColumnHeader(cardX: CGFloat, cardW: CGFloat, y: CGFloat) {
        let inset: CGFloat = 14
        let lotW   = (cardW - inset * 2) * 0.45
        let expW   = (cardW - inset * 2) * 0.35
        let qtyW   = (cardW - inset * 2) * 0.20

        draw("Lot Number",
             in: CGRect(x: cardX + inset, y: y + 4, width: lotW, height: 14),
             font: PDF.font(10, weight: .semibold), color: PDF.mutedText)

        draw("Expiry Date",
             in: CGRect(x: cardX + inset + lotW, y: y + 4, width: expW, height: 14),
             font: PDF.font(10, weight: .semibold), color: PDF.mutedText)

        draw("Pills",
             in: CGRect(x: cardX + inset + lotW + expW, y: y + 4, width: qtyW, height: 14),
             font: PDF.font(10, weight: .semibold), color: PDF.mutedText,
             alignment: .right)
    }

    private func drawLotRow(lot: String, expiry: String, qty: Int,
                             cardX: CGFloat, cardW: CGFloat, y: CGFloat) -> CGFloat {
        let rowH:  CGFloat = 24
        let inset: CGFloat = 14
        let lotW   = (cardW - inset * 2) * 0.45
        let expW   = (cardW - inset * 2) * 0.35
        let qtyW   = (cardW - inset * 2) * 0.20

        let isLotEmpty    = lot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isExpiryEmpty = expiry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isLotEmpty && isExpiryEmpty {
            draw("—",
                 in: CGRect(x: cardX + inset, y: y + 5, width: lotW + expW, height: 14),
                 font: PDF.font(11), color: PDF.mutedText)
        } else {
            draw(lot,
                 in: CGRect(x: cardX + inset, y: y + 5, width: lotW, height: 14),
                 font: PDF.font(11), color: PDF.bodyText)

            if !isExpiryEmpty {
                draw(expiry,
                     in: CGRect(x: cardX + inset + lotW, y: y + 5, width: expW, height: 14),
                     font: PDF.font(11), color: PDF.mutedText)
            }
        }

        draw("\(qty)",
             in: CGRect(x: cardX + inset + lotW + expW, y: y + 5, width: qtyW, height: 14),
             font: PDF.font(11, weight: .medium), color: PDF.bodyText,
             alignment: .right)

        return y + rowH
    }

    private func drawLotTotalRow(total: Int, cardX: CGFloat, cardW: CGFloat, y: CGFloat) -> CGFloat {
        let rowH:  CGFloat = 24
        let inset: CGFloat = 14
        let labW   = (cardW - inset * 2) * 0.80
        let numW   = (cardW - inset * 2) * 0.20

        draw("Total",
             in: CGRect(x: cardX + inset, y: y + 5, width: labW, height: 14),
             font: PDF.font(11, weight: .semibold), color: PDF.bodyText)

        draw("\(total)",
             in: CGRect(x: cardX + inset + labW, y: y + 5, width: numW, height: 14),
             font: PDF.font(11, weight: .semibold), color: PDF.bodyText,
             alignment: .right)

        return y + rowH
    }

    // MARK: - Footer

    private func drawFooter() {
        let footerY = PDF.pageHeight - 30
        drawHLine(x: PDF.margin, y: footerY - 10, width: PDF.contentWidth, color: PDF.divider)

        draw("PillCounter — Stock Count Report",
             at: CGPoint(x: PDF.margin, y: footerY),
             font: PDF.font(9), color: PDF.mutedText)

        let pageText = "Page \(pageNumber)"
        let pw = textSize(pageText, font: PDF.font(9)).width
        draw(pageText,
             at: CGPoint(x: PDF.pageWidth - PDF.margin - pw, y: footerY),
             font: PDF.font(9), color: PDF.mutedText)
    }

    // MARK: - Height Estimation

    private func estimateCardHeight(_ txn: GroupedTransaction) -> CGFloat {
        let headerH:     CGFloat = 45
        let divider:     CGFloat = 1
        let sectionRowH: CGFloat = 28
        let lotRowH:     CGFloat = 25
        let colHeaderH:  CGFloat = 20
        let totalRowH:   CGFloat = 25

        func subH(_ details: [LotDetail], _ filter: (LotDetail) -> Bool) -> CGFloat {
            let filtered = details.filter(filter)
            guard !filtered.isEmpty else { return sectionRowH + divider }
            return sectionRowH + colHeaderH + CGFloat(filtered.count) * lotRowH + totalRowH + divider * CGFloat(filtered.count + 1)
        }

        let sealedH = subH(txn.lotDetails, { $0.sealedQty > 0 })
        let openH   = subH(txn.lotDetails, { $0.openQty > 0 })

        return headerH + divider + sealedH + openH
    }

    private func estimateTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let boundingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let rect = (text as NSString).boundingRect(
            with: boundingSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height)
    }

    // MARK: - Drawing Primitives

    private func fill(_ rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(rect: rect).fill()
    }

    private func drawRoundedRect(_ rect: CGRect, fill fillColor: UIColor, stroke strokeColor: UIColor, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawHLine(x: CGFloat, y: CGFloat, width: CGFloat, color: UIColor) {
        color.setStroke()
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + width, y: y))
        p.lineWidth = 0.5
        p.stroke()
    }

    private func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                      alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment     = alignment
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func drawWrapped(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func textSize(_ text: String, font: UIFont) -> CGSize {
        (text as NSString).size(withAttributes: [.font: font])
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
