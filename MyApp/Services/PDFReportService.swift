import UIKit

/// Everything a report needs, already localized and formatted. Built by `ReportContentBuilder`.
struct ReportContent {
    struct InfoRow {
        let label: String
        let value: String
    }

    struct RoomRow {
        let name: String
        let type: String
        let floor: String
        let dimensions: String
        let area: String
    }

    struct FloorPlanSection {
        let floorName: String
        /// Rendered plan, or nil when the floor has no plan geometry.
        let image: UIImage?
    }

    struct Labels {
        let reportTitle: String
        let projectSection: String
        let roomsSection: String
        let roomColumns: [String]
        let noRooms: String
        let plansSection: String
        let planUnavailable: String
        let aiSection: String
        let aiPending: String
        /// Format with two integer placeholders: current page, total pages.
        let pageFormat: String
    }

    let labels: Labels
    let projectName: String
    let generatedAt: String
    let info: [InfoRow]
    /// Shown prominently when the project contains sample (non-scanned) data.
    let sampleNotice: String?
    let rooms: [RoomRow]
    let floorPlans: [FloorPlanSection]
    let locale: Locale
}

/// Renders `ReportContent` into a paginated A4 PDF with `UIGraphicsPDFRenderer`.
/// System fonts are used, so Uzbek Latin (incl. ʻ ʼ) and Cyrillic text render correctly.
struct PDFReportService {
    static let pageSize = CGSize(width: 595.2, height: 841.8) // A4 in points
    private let margin: CGFloat = 48
    private let footerHeight: CGFloat = 34

    private var contentWidth: CGFloat { Self.pageSize.width - margin * 2 }
    private var contentBottom: CGFloat { Self.pageSize.height - margin - footerHeight }

    // Fixed light palette — reports are printed documents regardless of app appearance.
    private enum Ink {
        static let primary = UIColor(red: 0x1A / 255, green: 0x1C / 255, blue: 0x1D / 255, alpha: 1)
        static let secondary = UIColor(red: 0x5C / 255, green: 0x60 / 255, blue: 0x5D / 255, alpha: 1)
        static let line = UIColor(red: 0xDD / 255, green: 0xDA / 255, blue: 0xD3 / 255, alpha: 1)
        static let surface = UIColor(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xF0 / 255, alpha: 1)
        static let graphite = UIColor(red: 0x23 / 255, green: 0x27 / 255, blue: 0x2A / 255, alpha: 1)
        static let accent = UIColor(red: 0xD2 / 255, green: 0x40 / 255, blue: 0x1C / 255, alpha: 1)
        static let accentTint = UIColor(red: 0xF6 / 255, green: 0xE2 / 255, blue: 0xDA / 255, alpha: 1)
        static let brandStroke = UIColor(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEB / 255, alpha: 1)
    }

    private enum Block {
        case header
        case notice(String)
        case sectionTitle(String)
        case infoRow(ReportContent.InfoRow)
        case tableHeader
        case tableRow(ReportContent.RoomRow)
        case paragraph(String)
        case subheading(String)
        case image(UIImage)
        case spacer(CGFloat)
    }

    private let columnFractions: [CGFloat] = [0.27, 0.18, 0.16, 0.25, 0.14]

    func render(_ content: ReportContent) -> Data {
        let pages = paginate(blocks(for: content), content: content)
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: Self.pageSize),
            format: documentFormat(for: content)
        )
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                var y = margin
                for block in page {
                    let height = self.height(of: block, content: content)
                    draw(block, at: y, height: height, content: content)
                    y += height
                }
                drawFooter(page: index + 1, of: pages.count, content: content)
            }
        }
    }

    // MARK: - Structure

    private func blocks(for content: ReportContent) -> [Block] {
        var blocks: [Block] = [.header, .spacer(18)]
        if let notice = content.sampleNotice {
            blocks += [.notice(notice), .spacer(14)]
        }

        blocks.append(.sectionTitle(content.labels.projectSection))
        blocks += content.info.map(Block.infoRow)
        blocks.append(.spacer(18))

        blocks.append(.sectionTitle(content.labels.roomsSection))
        if content.rooms.isEmpty {
            blocks.append(.paragraph(content.labels.noRooms))
        } else {
            blocks.append(.tableHeader)
            blocks += content.rooms.map(Block.tableRow)
        }
        blocks.append(.spacer(18))

        blocks.append(.sectionTitle(content.labels.plansSection))
        for section in content.floorPlans {
            blocks.append(.subheading(section.floorName))
            if let image = section.image {
                blocks.append(.image(image))
            } else {
                blocks.append(.paragraph(content.labels.planUnavailable))
            }
            blocks.append(.spacer(10))
        }
        blocks.append(.spacer(8))

        blocks += [.sectionTitle(content.labels.aiSection), .paragraph(content.labels.aiPending)]
        return blocks
    }

    /// Splits blocks into pages. Keeps section titles / subheadings with the following block and
    /// repeats the room table header at the top of a page that continues the table.
    private func paginate(_ blocks: [Block], content: ReportContent) -> [[Block]] {
        var pages: [[Block]] = [[]]
        var y = margin
        var inTable = false

        func newPage() {
            pages.append([])
            y = margin
        }

        for (index, block) in blocks.enumerated() {
            var needed = height(of: block, content: content)
            if isHeading(block) {
                // Keep a heading (and any headings right after it) with the first content block.
                var next = index + 1
                while next < blocks.count {
                    needed += height(of: blocks[next], content: content)
                    if !isHeading(blocks[next]) { break }
                    next += 1
                }
            }

            if case .spacer = block, y + needed > contentBottom {
                continue // never start a page with a spacer
            }
            if y + needed > contentBottom, !(pages[pages.count - 1].isEmpty) {
                newPage()
                if case .tableRow = block, inTable {
                    pages[pages.count - 1].append(.tableHeader)
                    y += height(of: .tableHeader, content: content)
                }
            }

            switch block {
            case .tableHeader: inTable = true
            case .tableRow: break
            default: inTable = false
            }
            pages[pages.count - 1].append(block)
            y += height(of: block, content: content)
        }
        return pages
    }

    private func isHeading(_ block: Block) -> Bool {
        switch block {
        case .sectionTitle, .subheading, .tableHeader: true
        default: false
        }
    }

    // MARK: - Measuring

    private func height(of block: Block, content: ReportContent) -> CGFloat {
        switch block {
        case .header:
            return 44 + 8 + textHeight(content.projectName, font: Fonts.title, width: contentWidth)
                + 4 + textHeight(content.generatedAt, font: Fonts.body, width: contentWidth)
        case .notice(let text):
            return textHeight(text, font: Fonts.body, width: contentWidth - 24) + 20
        case .sectionTitle(let text):
            return textHeight(text, font: Fonts.section, width: contentWidth) + 12
        case .subheading(let text):
            return textHeight(text, font: Fonts.bodyBold, width: contentWidth) + 8
        case .infoRow(let row):
            let labelWidth = contentWidth * 0.38
            return max(textHeight(row.label, font: Fonts.body, width: labelWidth - 8),
                       textHeight(row.value, font: Fonts.bodyBold, width: contentWidth - labelWidth)) + 10
        case .tableHeader:
            return rowHeight(content.labels.roomColumns, font: Fonts.small)
        case .tableRow(let row):
            return rowHeight([row.name, row.type, row.floor, row.dimensions, row.area], font: Fonts.body)
        case .paragraph(let text):
            return textHeight(text, font: Fonts.body, width: contentWidth) + 8
        case .image(let image):
            return imageRect(for: image, at: 0).height + 6
        case .spacer(let height):
            return height
        }
    }

    private func rowHeight(_ cells: [String], font: UIFont) -> CGFloat {
        let heights = zip(cells, columnWidths).map { textHeight($0, font: font, width: $1 - 10) }
        return (heights.max() ?? 0) + 14
    }

    private var columnWidths: [CGFloat] { columnFractions.map { $0 * contentWidth } }

    private func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let rect = attributed(text, font: font, color: Ink.primary).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }

    private func imageRect(for image: UIImage, at y: CGFloat) -> CGRect {
        let maxSize = CGSize(width: contentWidth, height: 380)
        let scale = min(maxSize.width / max(image.size.width, 1), maxSize.height / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: margin + (contentWidth - size.width) / 2, y: y, width: size.width, height: size.height)
    }

    // MARK: - Drawing

    private func draw(_ block: Block, at y: CGFloat, height: CGFloat, content: ReportContent) {
        switch block {
        case .header:
            drawBrand(at: CGPoint(x: margin, y: y))
            draw(content.labels.reportTitle, font: Fonts.small, color: Ink.secondary,
                 in: CGRect(x: margin + 160, y: y + 12, width: contentWidth - 160, height: 20), alignment: .right)
            var cursor = y + 52
            let titleHeight = textHeight(content.projectName, font: Fonts.title, width: contentWidth)
            draw(content.projectName, font: Fonts.title, color: Ink.primary,
                 in: CGRect(x: margin, y: cursor, width: contentWidth, height: titleHeight))
            cursor += titleHeight + 4
            draw(content.generatedAt, font: Fonts.body, color: Ink.secondary,
                 in: CGRect(x: margin, y: cursor, width: contentWidth, height: 20))
            fillLine(y: y + height + 8)

        case .notice(let text):
            let box = CGRect(x: margin, y: y, width: contentWidth, height: height - 6)
            Ink.accentTint.setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
            draw(text, font: Fonts.body, color: Ink.primary, in: box.insetBy(dx: 12, dy: 7))

        case .sectionTitle(let text):
            draw(text, font: Fonts.section, color: Ink.accent,
                 in: CGRect(x: margin, y: y + 4, width: contentWidth, height: height))

        case .subheading(let text):
            draw(text, font: Fonts.bodyBold, color: Ink.primary,
                 in: CGRect(x: margin, y: y + 2, width: contentWidth, height: height))

        case .infoRow(let row):
            let labelWidth = contentWidth * 0.38
            draw(row.label, font: Fonts.body, color: Ink.secondary,
                 in: CGRect(x: margin, y: y + 4, width: labelWidth - 8, height: height))
            draw(row.value, font: Fonts.bodyBold, color: Ink.primary,
                 in: CGRect(x: margin + labelWidth, y: y + 4, width: contentWidth - labelWidth, height: height))
            fillLine(y: y + height - 0.5)

        case .tableHeader:
            Ink.surface.setFill()
            UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: height), cornerRadius: 6).fill()
            drawCells(content.labels.roomColumns, y: y, font: Fonts.small, color: Ink.secondary)

        case .tableRow(let row):
            drawCells([row.name, row.type, row.floor, row.dimensions, row.area], y: y, font: Fonts.body, color: Ink.primary)
            fillLine(y: y + height - 0.5)

        case .paragraph(let text):
            draw(text, font: Fonts.body, color: Ink.secondary,
                 in: CGRect(x: margin, y: y + 2, width: contentWidth, height: height))

        case .image(let image):
            let rect = imageRect(for: image, at: y)
            image.draw(in: rect)
            Ink.line.setStroke()
            let border = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            border.lineWidth = 0.5
            border.stroke()

        case .spacer:
            break
        }
    }

    private func drawCells(_ cells: [String], y: CGFloat, font: UIFont, color: UIColor) {
        var x = margin
        for (index, (text, width)) in zip(cells, columnWidths).enumerated() {
            let alignment: NSTextAlignment = index == cells.count - 1 ? .right : .left
            draw(text, font: font, color: color,
                 in: CGRect(x: x + 5, y: y + 7, width: width - 10, height: .greatestFiniteMagnitude),
                 alignment: alignment)
            x += width
        }
    }

    private func drawFooter(page: Int, of total: Int, content: ReportContent) {
        let y = Self.pageSize.height - margin - 14
        fillLine(y: y - 10)
        draw("iHomeScan · \(content.generatedAt)", font: Fonts.small, color: Ink.secondary,
             in: CGRect(x: margin, y: y, width: contentWidth * 0.7, height: 16))
        let pageText = String(format: content.labels.pageFormat, locale: content.locale, page, total)
        draw(pageText, font: Fonts.small, color: Ink.secondary,
             in: CGRect(x: margin + contentWidth * 0.5, y: y, width: contentWidth * 0.5, height: 16), alignment: .right)
    }

    /// Graphite tile with scan-frame corners and an accent line, followed by the wordmark.
    private func drawBrand(at origin: CGPoint) {
        let tile = CGRect(origin: origin, size: CGSize(width: 36, height: 36))
        Ink.graphite.setFill()
        UIBezierPath(roundedRect: tile, cornerRadius: 10).fill()

        let unit = tile.width * 0.66 / 24
        let inset = tile.width * 0.17
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + inset + x * unit, y: tile.minY + inset + y * unit) }
        let corners = UIBezierPath()
        for points in [[p(8, 4), p(4, 4), p(4, 8)], [p(16, 4), p(20, 4), p(20, 8)],
                       [p(4, 16), p(4, 20), p(8, 20)], [p(20, 16), p(20, 20), p(16, 20)]] {
            corners.move(to: points[0])
            points.dropFirst().forEach(corners.addLine)
        }
        corners.lineWidth = 2.2 * unit
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        Ink.brandStroke.setStroke()
        corners.stroke()

        let line = UIBezierPath()
        line.move(to: p(8, 12))
        line.addLine(to: p(16, 12))
        line.lineWidth = 2.2 * unit
        line.lineCapStyle = .round
        Ink.accent.setStroke()
        line.stroke()

        draw("iHomeScan", font: Fonts.brand, color: Ink.primary,
             in: CGRect(x: tile.maxX + 10, y: origin.y + 6, width: 200, height: 26))
    }

    private func fillLine(y: CGFloat) {
        Ink.line.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5))
    }

    private func draw(_ text: String, font: UIFont, color: UIColor, in rect: CGRect, alignment: NSTextAlignment = .left) {
        attributed(text, font: font, color: color, alignment: alignment)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func attributed(_ text: String, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    private func documentFormat(for content: ReportContent) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(content.labels.reportTitle) — \(content.projectName)",
            kCGPDFContextCreator as String: "iHomeScan",
        ]
        return format
    }

    private enum Fonts {
        static let brand = UIFont.systemFont(ofSize: 18, weight: .bold)
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let section = UIFont.systemFont(ofSize: 14, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 10.5)
        static let bodyBold = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        static let small = UIFont.systemFont(ofSize: 9, weight: .medium)
    }
}
