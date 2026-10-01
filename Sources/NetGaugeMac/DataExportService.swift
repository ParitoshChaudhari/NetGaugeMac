import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import zlib

// MARK: - Export Models & Enums

public enum ExportScope: String, CaseIterable, Identifiable, Sendable {
    case all       = "All Data"
    case dateRange = "Date Range"

    public var id: String { rawValue }
}

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf   = "PDF Document"
    case excel = "Excel Spreadsheet"
    case json  = "JSON Archive"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .pdf:   return "pdf"
        case .excel: return "xlsx"
        case .json:  return "json"
        }
    }

    public var utType: UTType {
        switch self {
        case .pdf:   return .pdf
        case .excel: return UTType(filenameExtension: "xlsx") ?? .data
        case .json:  return .json
        }
    }
}

public struct ExportRawRecord: Sendable {
    public let timestamp: Date
    public let networkName: String
    public let bytesRx: UInt64
    public let bytesTx: UInt64

    public init(timestamp: Date, networkName: String, bytesRx: UInt64, bytesTx: UInt64) {
        self.timestamp = timestamp
        self.networkName = networkName
        self.bytesRx = bytesRx
        self.bytesTx = bytesTx
    }
}

public struct ExportNetworkItem: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let connectionType: String // "Wi-Fi", "Personal Hotspot", "Ethernet", etc.
    public let isHotspot: Bool
    public let downloadBytes: UInt64
    public let uploadBytes: UInt64
    public let totalBytes: UInt64
    public let formattedDownload: String
    public let formattedUpload: String
    public let formattedTotal: String
    public let percentageOfTotal: Double
}

public struct ExportMonthlyItem: Codable, Sendable, Identifiable {
    public var id: String { "\(year)-\(String(format: "%02d", month))" }
    public let year: Int
    public let month: Int
    public let label: String // "October 2026"
    public let downloadBytes: UInt64
    public let uploadBytes: UInt64
    public let totalBytes: UInt64
    public let formattedDownload: String
    public let formattedUpload: String
    public let formattedTotal: String
    public let topNetworkName: String
    public let percentageOfPeriod: Double
    public let networks: [ExportNetworkItem]
}

public struct ExportDailyItem: Codable, Sendable, Identifiable {
    public var id: String { "\(dateString)-\(networkName)" }
    public let date: Date
    public let dateString: String // "2026-10-01"
    public let formattedDate: String // "Oct 1, 2026"
    public let networkName: String
    public let connectionType: String
    public let isHotspot: Bool
    public let downloadBytes: UInt64
    public let uploadBytes: UInt64
    public let totalBytes: UInt64
    public let formattedDownload: String
    public let formattedUpload: String
    public let formattedTotal: String
}

public struct ExportReport: Codable, Sendable {
    public let appName: String
    public let appVersion: String
    public let scopeName: String
    public let startDate: Date?
    public let endDate: Date?
    public let generatedAt: Date
    public let totalDownloadBytes: UInt64
    public let totalUploadBytes: UInt64
    public let totalBytes: UInt64
    public let formattedDownload: String
    public let formattedUpload: String
    public let formattedTotal: String
    public let networkCount: Int
    public let topNetworkName: String
    public let networks: [ExportNetworkItem]
    public let monthlySummaries: [ExportMonthlyItem]
    public let dailyRecords: [ExportDailyItem]
}

// MARK: - Data Export Service

public final class DataExportService: Sendable {
    public static let shared = DataExportService()
    private init() {}

    // MARK: - Classification & Formatters

    public static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        let mb = Double(bytes) / 1_000_000.0
        let kb = Double(bytes) / 1_000.0

        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    public static func classifyNetwork(name: String) -> (cleanName: String, type: String, isHotspot: Bool) {
        let lower = name.lowercased()
        let isHotspot = lower.contains("hotspot") || lower.contains("iphone") || lower.contains("ipad") || lower.contains("cellular")

        var clean = name
        var connType = "Wi-Fi"

        if isHotspot {
            connType = "Personal Hotspot"
        } else if lower.contains("ethernet") || name.hasPrefix("en") && !name.contains("Wi-Fi") {
            connType = "Ethernet / Wired"
        } else if name.hasPrefix("Wi-Fi:") {
            clean = name.replacingOccurrences(of: "Wi-Fi:", with: "").trimmingCharacters(in: .whitespaces)
            connType = "Wi-Fi"
        } else {
            connType = "Network Interface"
        }

        return (clean, connType, isHotspot)
    }

    // MARK: - Build Export Report Data

    public func buildReport(
        rawRecords: [ExportRawRecord],
        scope: ExportScope,
        startDate: Date?,
        endDate: Date?
    ) -> ExportReport {
        let cal = Calendar.current
        let now = Date()

        let totalDownload = rawRecords.reduce(UInt64(0)) { $0 + $1.bytesRx }
        let totalUpload   = rawRecords.reduce(UInt64(0)) { $0 + $1.bytesTx }
        let totalBytes    = totalDownload + totalUpload

        // 1. Group by Network Name
        var netGroups: [String: (rx: UInt64, tx: UInt64)] = [:]
        for r in rawRecords {
            let cur = netGroups[r.networkName] ?? (0, 0)
            netGroups[r.networkName] = (cur.rx + r.bytesRx, cur.tx + r.bytesTx)
        }

        var networkItems: [ExportNetworkItem] = []
        for (name, data) in netGroups {
            let total = data.rx + data.tx
            let classification = Self.classifyNetwork(name: name)
            let pct = totalBytes > 0 ? (Double(total) / Double(totalBytes)) * 100.0 : 0.0

            networkItems.append(ExportNetworkItem(
                name: name,
                displayName: classification.cleanName,
                connectionType: classification.type,
                isHotspot: classification.isHotspot,
                downloadBytes: data.rx,
                uploadBytes: data.tx,
                totalBytes: total,
                formattedDownload: Self.formatBytes(data.rx),
                formattedUpload: Self.formatBytes(data.tx),
                formattedTotal: Self.formatBytes(total),
                percentageOfTotal: pct
            ))
        }
        networkItems.sort { $0.totalBytes > $1.totalBytes }

        let topNetName = networkItems.first?.name ?? "None"

        // 2. Group by Month
        struct MonthKey: Hashable {
            let year: Int
            let month: Int
        }

        var monthRecords: [MonthKey: [ExportRawRecord]] = [:]
        for r in rawRecords {
            let comps = cal.dateComponents([.year, .month], from: r.timestamp)
            let key = MonthKey(year: comps.year ?? 2026, month: comps.month ?? 1)
            monthRecords[key, default: []].append(r)
        }

        var monthlyItems: [ExportMonthlyItem] = []
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"

        for (key, records) in monthRecords {
            let mRx = records.reduce(UInt64(0)) { $0 + $1.bytesRx }
            let mTx = records.reduce(UInt64(0)) { $0 + $1.bytesTx }
            let mTotal = mRx + mTx
            let pct = totalBytes > 0 ? (Double(mTotal) / Double(totalBytes)) * 100.0 : 0.0

            // Per-network within month
            var mNetMap: [String: (rx: UInt64, tx: UInt64)] = [:]
            for r in records {
                let cur = mNetMap[r.networkName] ?? (0, 0)
                mNetMap[r.networkName] = (cur.rx + r.bytesRx, cur.tx + r.bytesTx)
            }

            var mNetItems: [ExportNetworkItem] = []
            for (name, data) in mNetMap {
                let subTotal = data.rx + data.tx
                let classification = Self.classifyNetwork(name: name)
                let subPct = mTotal > 0 ? (Double(subTotal) / Double(mTotal)) * 100.0 : 0.0
                mNetItems.append(ExportNetworkItem(
                    name: name,
                    displayName: classification.cleanName,
                    connectionType: classification.type,
                    isHotspot: classification.isHotspot,
                    downloadBytes: data.rx,
                    uploadBytes: data.tx,
                    totalBytes: subTotal,
                    formattedDownload: Self.formatBytes(data.rx),
                    formattedUpload: Self.formatBytes(data.tx),
                    formattedTotal: Self.formatBytes(subTotal),
                    percentageOfTotal: subPct
                ))
            }
            mNetItems.sort { $0.totalBytes > $1.totalBytes }

            var comps = DateComponents()
            comps.year = key.year
            comps.month = key.month
            comps.day = 1
            let monthDate = cal.date(from: comps) ?? now
            let monthLabel = monthFormatter.string(from: monthDate)

            monthlyItems.append(ExportMonthlyItem(
                year: key.year,
                month: key.month,
                label: monthLabel,
                downloadBytes: mRx,
                uploadBytes: mTx,
                totalBytes: mTotal,
                formattedDownload: Self.formatBytes(mRx),
                formattedUpload: Self.formatBytes(mTx),
                formattedTotal: Self.formatBytes(mTotal),
                topNetworkName: mNetItems.first?.name ?? "None",
                percentageOfPeriod: pct,
                networks: mNetItems
            ))
        }

        // Sort months chronologically ascending (or latest first)
        monthlyItems.sort {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }

        // 3. Group by Day
        struct DayKey: Hashable {
            let dayDate: Date
            let networkName: String
        }

        var dayGroups: [DayKey: (rx: UInt64, tx: UInt64)] = [:]
        for r in rawRecords {
            let d = cal.startOfDay(for: r.timestamp)
            let key = DayKey(dayDate: d, networkName: r.networkName)
            let cur = dayGroups[key] ?? (0, 0)
            dayGroups[key] = (cur.rx + r.bytesRx, cur.tx + r.bytesTx)
        }

        let isoDateFormatter = DateFormatter()
        isoDateFormatter.dateFormat = "yyyy-MM-dd"

        let readableDateFormatter = DateFormatter()
        readableDateFormatter.dateStyle = .medium
        readableDateFormatter.timeStyle = .none

        var dailyItems: [ExportDailyItem] = []
        for (key, data) in dayGroups {
            let total = data.rx + data.tx
            let classification = Self.classifyNetwork(name: key.networkName)
            dailyItems.append(ExportDailyItem(
                date: key.dayDate,
                dateString: isoDateFormatter.string(from: key.dayDate),
                formattedDate: readableDateFormatter.string(from: key.dayDate),
                networkName: key.networkName,
                connectionType: classification.type,
                isHotspot: classification.isHotspot,
                downloadBytes: data.rx,
                uploadBytes: data.tx,
                totalBytes: total,
                formattedDownload: Self.formatBytes(data.rx),
                formattedUpload: Self.formatBytes(data.tx),
                formattedTotal: Self.formatBytes(total)
            ))
        }
        dailyItems.sort { $0.date > $1.date }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.6"

        return ExportReport(
            appName: "NetGauge",
            appVersion: version,
            scopeName: scope.rawValue,
            startDate: startDate,
            endDate: endDate,
            generatedAt: now,
            totalDownloadBytes: totalDownload,
            totalUploadBytes: totalUpload,
            totalBytes: totalBytes,
            formattedDownload: Self.formatBytes(totalDownload),
            formattedUpload: Self.formatBytes(totalUpload),
            formattedTotal: Self.formatBytes(totalBytes),
            networkCount: networkItems.count,
            topNetworkName: topNetName,
            networks: networkItems,
            monthlySummaries: monthlyItems,
            dailyRecords: dailyItems
        )
    }

    // MARK: - PDF Generation

    public func generatePDF(report: ExportReport) -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return Data() }

        // Standard Letter: 612 pt x 792 pt
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 36
        let contentWidth = pageWidth - (margin * 2)

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        // Quartz PDF coordinate mapping: translates top-down cursorY to Quartz y=0 at bottom
        func qY(_ topDownY: CGFloat, height: CGFloat = 0) -> CGFloat {
            return pageHeight - topDownY - height
        }

        // Color definitions
        let colorAmber     = NSColor(red: 0.96, green: 0.73, blue: 0.22, alpha: 1.0) // #F5BA38
        let colorCharcoal  = NSColor(red: 0.17, green: 0.15, blue: 0.13, alpha: 1.0) // #2C2620
        let colorDarkText  = NSColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1.0)
        let colorMutedText = NSColor(red: 0.45, green: 0.42, blue: 0.38, alpha: 1.0)
        let colorCardBg    = NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0)
        let colorBorder    = NSColor(red: 0.88, green: 0.85, blue: 0.80, alpha: 1.0)
        let colorAltRow    = NSColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1.0)
        let colorWhite     = NSColor.white
        let colorHotspot   = NSColor(red: 0.88, green: 0.52, blue: 0.35, alpha: 1.0) // Warm terracotta

        var currentPage = 1
        var cursorY: CGFloat = margin

        func startNewPage() {
            if currentPage > 1 {
                pdfContext.endPDFPage()
            }
            pdfContext.beginPDFPage(nil)

            let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.current = nsContext

            // Accent bar at top
            colorAmber.setFill()
            CGRect(x: 0, y: qY(0, height: 4), width: pageWidth, height: 4).fill()

            cursorY = margin + 10
        }

        func drawFooter(pageNumber: Int) {
            let footerY: CGFloat = margin - 18
            // Divider
            colorBorder.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: margin, y: footerY + 14))
            path.line(to: CGPoint(x: pageWidth - margin, y: footerY + 14))
            path.lineWidth = 0.5
            path.stroke()

            let footerLeft = "NetGauge for macOS • Network Monitor & Bandwidth Tracker"
            let footerRight = "Page \(pageNumber)"

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: colorMutedText
            ]

            (footerLeft as NSString).draw(at: CGPoint(x: margin, y: footerY), withAttributes: attrs)

            let rightSize = (footerRight as NSString).size(withAttributes: attrs)
            (footerRight as NSString).draw(at: CGPoint(x: pageWidth - margin - rightSize.width, y: footerY), withAttributes: attrs)
        }

        // Start first page
        startNewPage()

        // 1. Header Block
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: colorCharcoal
        ]
        let titleRect = CGRect(x: margin, y: qY(cursorY, height: 26), width: contentWidth, height: 26)
        ("NetGauge Network Usage Report" as NSString).draw(with: titleRect, options: [.truncatesLastVisibleLine], attributes: titleAttrs)
        cursorY += 28

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: colorMutedText
        ]
        let subRect = CGRect(x: margin, y: qY(cursorY, height: 16), width: contentWidth, height: 16)
        ("Bandwidth consumption, Wi-Fi & Personal Hotspot detailed analytics" as NSString).draw(with: subRect, options: [.truncatesLastVisibleLine], attributes: subtitleAttrs)

        // Metadata box (top-right)
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let genStr = "Generated: \(df.string(from: report.generatedAt))"
        let scopeStr = "Scope: \(report.scopeName)"
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: colorCharcoal
        ]
        let scopeSize = (scopeStr as NSString).size(withAttributes: metaAttrs)
        let genSize   = (genStr as NSString).size(withAttributes: metaAttrs)
        let scopeRect = CGRect(x: pageWidth - margin - scopeSize.width, y: qY(margin + 10, height: 14), width: scopeSize.width, height: 14)
        (scopeStr as NSString).draw(with: scopeRect, options: [], attributes: metaAttrs)
        let genRect = CGRect(x: pageWidth - margin - genSize.width, y: qY(margin + 24, height: 14), width: genSize.width, height: 14)
        (genStr as NSString).draw(with: genRect, options: [], attributes: metaAttrs)

        cursorY += 20

        // Divider
        colorBorder.setStroke()
        let sepPath = NSBezierPath()
        let sepY = qY(cursorY, height: 0)
        sepPath.move(to: CGPoint(x: margin, y: sepY))
        sepPath.line(to: CGPoint(x: pageWidth - margin, y: sepY))
        sepPath.lineWidth = 1
        sepPath.stroke()
        cursorY += 14

        // 2. Executive Metric Cards (4 cards in a row)
        let cardCount: CGFloat = 4
        let cardSpacing: CGFloat = 10
        let cardWidth = (contentWidth - ((cardCount - 1) * cardSpacing)) / cardCount
        let cardHeight: CGFloat = 62

        let cardsData: [(title: String, value: String, sub: String, color: NSColor)] = [
            ("TOTAL USAGE", report.formattedTotal, "Download + Upload", colorCharcoal),
            ("DOWNLOAD", report.formattedDownload, "Received traffic", colorAmber),
            ("UPLOAD", report.formattedUpload, "Transmitted traffic", colorHotspot),
            ("TOP NETWORK", report.topNetworkName, "\(report.networkCount) networks active", colorCharcoal)
        ]

        for (i, card) in cardsData.enumerated() {
            let cardX = margin + CGFloat(i) * (cardWidth + cardSpacing)
            let cardRect = CGRect(x: cardX, y: qY(cursorY, height: cardHeight), width: cardWidth, height: cardHeight)

            // Fill card
            colorCardBg.setFill()
            let bp = NSBezierPath(roundedRect: cardRect, xRadius: 6, yRadius: 6)
            bp.fill()
            colorBorder.setStroke()
            bp.lineWidth = 1
            bp.stroke()

            // Card title
            let cTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: colorMutedText
            ]
            let cTitleRect = CGRect(x: cardX + 10, y: qY(cursorY + 8, height: 12), width: cardWidth - 20, height: 12)
            (card.title as NSString).draw(with: cTitleRect, options: [.truncatesLastVisibleLine], attributes: cTitleAttrs)

            // Card value
            let cValAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: i == 3 ? 11 : 15),
                .foregroundColor: card.color
            ]
            let valRect = CGRect(x: cardX + 10, y: qY(cursorY + 22, height: 20), width: cardWidth - 20, height: 20)
            (card.value as NSString).draw(with: valRect, options: [.truncatesLastVisibleLine], attributes: cValAttrs)

            // Card subtitle
            let cSubAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7.5, weight: .regular),
                .foregroundColor: colorMutedText
            ]
            let cSubRect = CGRect(x: cardX + 10, y: qY(cursorY + 44, height: 12), width: cardWidth - 20, height: 12)
            (card.sub as NSString).draw(with: cSubRect, options: [.truncatesLastVisibleLine], attributes: cSubAttrs)
        }

        cursorY += cardHeight + 20

        // Helper to check page overflow before drawing a section or row
        func checkPageBreak(requiredHeight: CGFloat) {
            if cursorY + requiredHeight > pageHeight - margin - 20 {
                drawFooter(pageNumber: currentPage)
                currentPage += 1
                startNewPage()
            }
        }

        // 3. Section: Monthly Usage Summary
        checkPageBreak(requiredHeight: 120)

        let secTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: colorCharcoal
        ]
        let mTitleRect = CGRect(x: margin, y: qY(cursorY, height: 18), width: contentWidth, height: 18)
        ("Monthly Usage Summary" as NSString).draw(with: mTitleRect, options: [.truncatesLastVisibleLine], attributes: secTitleAttrs)
        cursorY += 24

        // Table headers for Monthly
        let mCols: [(title: String, width: CGFloat, align: NSTextAlignment)] = [
            ("Period / Month", 140, .left),
            ("Download", 95, .right),
            ("Upload", 95, .right),
            ("Total Usage", 100, .right),
            ("Top Network", 110, .left)
        ]

        func drawTableHeader(cols: [(title: String, width: CGFloat, align: NSTextAlignment)]) {
            colorCharcoal.setFill()
            CGRect(x: margin, y: qY(cursorY, height: 22), width: contentWidth, height: 22).fill()

            var x = margin + 6
            for col in cols {
                let pStyle = NSMutableParagraphStyle()
                pStyle.alignment = col.align
                let hAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 8.5),
                    .foregroundColor: colorWhite,
                    .paragraphStyle: pStyle
                ]
                let cellRect = CGRect(x: x, y: qY(cursorY + 4, height: 14), width: col.width - 12, height: 14)
                (col.title as NSString).draw(with: cellRect, options: [.truncatesLastVisibleLine], attributes: hAttrs)
                x += col.width
            }
            cursorY += 22
        }

        drawTableHeader(cols: mCols)

        if report.monthlySummaries.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: colorMutedText
            ]
            let emptyRect = CGRect(x: margin + 8, y: qY(cursorY + 4, height: 14), width: contentWidth - 16, height: 14)
            ("No monthly records available for the selected period." as NSString).draw(with: emptyRect, options: [], attributes: emptyAttrs)
            cursorY += 24
        } else {
            for (idx, m) in report.monthlySummaries.enumerated() {
                checkPageBreak(requiredHeight: 22)
                let rowBg = (idx % 2 == 0) ? colorWhite : colorAltRow
                rowBg.setFill()
                CGRect(x: margin, y: qY(cursorY, height: 20), width: contentWidth, height: 20).fill()

                var x = margin + 6
                let cells: [(val: String, width: CGFloat, align: NSTextAlignment, bold: Bool)] = [
                    (m.label, 140, .left, true),
                    (m.formattedDownload, 95, .right, false),
                    (m.formattedUpload, 95, .right, false),
                    (m.formattedTotal, 100, .right, true),
                    (m.topNetworkName, 110, .left, false)
                ]

                for cell in cells {
                    let pStyle = NSMutableParagraphStyle()
                    pStyle.alignment = cell.align
                    let rAttrs: [NSAttributedString.Key: Any] = [
                        .font: cell.bold ? NSFont.boldSystemFont(ofSize: 8.5) : NSFont.systemFont(ofSize: 8.5),
                        .foregroundColor: colorDarkText,
                        .paragraphStyle: pStyle
                    ]
                    let cellRect = CGRect(x: x, y: qY(cursorY + 3, height: 14), width: cell.width - 12, height: 14)
                    (cell.val as NSString).draw(with: cellRect, options: [.truncatesLastVisibleLine], attributes: rAttrs)
                    x += cell.width
                }
                cursorY += 20
            }
        }

        cursorY += 16

        // 4. Section: Wi-Fi & Personal Hotspot Usage Breakdown
        checkPageBreak(requiredHeight: 120)

        let netTitleRect = CGRect(x: margin, y: qY(cursorY, height: 18), width: contentWidth, height: 18)
        ("Wi-Fi & Personal Hotspot Usage Breakdown" as NSString).draw(with: netTitleRect, options: [.truncatesLastVisibleLine], attributes: secTitleAttrs)
        cursorY += 24

        let netCols: [(title: String, width: CGFloat, align: NSTextAlignment)] = [
            ("Network / Hotspot Name", 160, .left),
            ("Connection Type", 100, .left),
            ("Download", 90, .right),
            ("Upload", 90, .right),
            ("Total Data (% Share)", 100, .right)
        ]

        drawTableHeader(cols: netCols)

        if report.networks.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: colorMutedText
            ]
            let emptyRect = CGRect(x: margin + 8, y: qY(cursorY + 4, height: 14), width: contentWidth - 16, height: 14)
            ("No network interfaces recorded for this period." as NSString).draw(with: emptyRect, options: [], attributes: emptyAttrs)
            cursorY += 24
        } else {
            for (idx, net) in report.networks.enumerated() {
                checkPageBreak(requiredHeight: 22)
                let rowBg = (idx % 2 == 0) ? colorWhite : colorAltRow
                rowBg.setFill()
                CGRect(x: margin, y: qY(cursorY, height: 20), width: contentWidth, height: 20).fill()

                var x = margin + 6
                let pctStr = String(format: "%.1f%%", net.percentageOfTotal)
                let totalWithPct = "\(net.formattedTotal) (\(pctStr))"

                let cells: [(val: String, width: CGFloat, align: NSTextAlignment, isHotspot: Bool, bold: Bool)] = [
                    (net.name, 160, .left, net.isHotspot, false),
                    (net.connectionType, 100, .left, false, false),
                    (net.formattedDownload, 90, .right, false, false),
                    (net.formattedUpload, 90, .right, false, false),
                    (totalWithPct, 100, .right, false, true)
                ]

                for cell in cells {
                    let pStyle = NSMutableParagraphStyle()
                    pStyle.alignment = cell.align
                    var textColor = colorDarkText
                    if cell.isHotspot { textColor = colorHotspot }

                    let rAttrs: [NSAttributedString.Key: Any] = [
                        .font: cell.bold ? NSFont.boldSystemFont(ofSize: 8.5) : NSFont.systemFont(ofSize: 8.5),
                        .foregroundColor: textColor,
                        .paragraphStyle: pStyle
                    ]
                    let cellRect = CGRect(x: x, y: qY(cursorY + 3, height: 14), width: cell.width - 12, height: 14)
                    (cell.val as NSString).draw(with: cellRect, options: [.truncatesLastVisibleLine], attributes: rAttrs)
                    x += cell.width
                }
                cursorY += 20
            }
        }

        cursorY += 16

        // 5. Section: Daily Usage Details (if available)
        if !report.dailyRecords.isEmpty {
            checkPageBreak(requiredHeight: 100)

            let dailyTitleRect = CGRect(x: margin, y: qY(cursorY, height: 18), width: contentWidth, height: 18)
            ("Daily Usage History" as NSString).draw(with: dailyTitleRect, options: [.truncatesLastVisibleLine], attributes: secTitleAttrs)
            cursorY += 24

            let dailyCols: [(title: String, width: CGFloat, align: NSTextAlignment)] = [
                ("Date", 110, .left),
                ("Network Name", 150, .left),
                ("Connection Type", 90, .left),
                ("Download", 95, .right),
                ("Upload", 95, .right)
            ]

            drawTableHeader(cols: dailyCols)

            for (idx, day) in report.dailyRecords.prefix(60).enumerated() { // Cap at 60 for clean PDF length
                checkPageBreak(requiredHeight: 20)
                let rowBg = (idx % 2 == 0) ? colorWhite : colorAltRow
                rowBg.setFill()
                CGRect(x: margin, y: qY(cursorY, height: 18), width: contentWidth, height: 18).fill()

                var x = margin + 6
                let cells: [(val: String, width: CGFloat, align: NSTextAlignment)] = [
                    (day.formattedDate, 110, .left),
                    (day.networkName, 150, .left),
                    (day.connectionType, 90, .left),
                    (day.formattedDownload, 95, .right),
                    (day.formattedUpload, 95, .right)
                ]

                for cell in cells {
                    let pStyle = NSMutableParagraphStyle()
                    pStyle.alignment = cell.align
                    let rAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 8),
                        .foregroundColor: colorDarkText,
                        .paragraphStyle: pStyle
                    ]
                    let cellRect = CGRect(x: x, y: qY(cursorY + 2.5, height: 13), width: cell.width - 12, height: 13)
                    (cell.val as NSString).draw(with: cellRect, options: [.truncatesLastVisibleLine], attributes: rAttrs)
                    x += cell.width
                }
                cursorY += 18
            }
        }

        // Draw footer on last page
        drawFooter(pageNumber: currentPage)

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return pdfData as Data
    }

    // MARK: - Excel (.xlsx) Generation via Pure Swift ZIP & OpenXML

    public func generateExcel(report: ExportReport) -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet4.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        let wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>
          <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet4.xml"/>
          <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Executive Summary" sheetId="1" r:id="rId1"/>
            <sheet name="Monthly Summary" sheetId="2" r:id="rId2"/>
            <sheet name="Wi-Fi &amp; Hotspots" sheetId="3" r:id="rId3"/>
            <sheet name="Daily Details" sheetId="4" r:id="rId4"/>
          </sheets>
        </workbook>
        """

        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="4">
            <font><name val="Calibri"/><sz val="11"/></font>
            <font><b/><name val="Calibri"/><sz val="11"/><color rgb="FFFFFFFF"/></font>
            <font><b/><name val="Calibri"/><sz val="14"/><color rgb="FF2C2620"/></font>
            <font><b/><name val="Calibri"/><sz val="11"/></font>
          </fonts>
          <fills count="4">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FF2C2620"/></patternFill></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFF8F6F2"/></patternFill></fill>
          </fills>
          <borders count="2">
            <border><left/><right/><top/><bottom/></border>
            <border><left/><right/><top style="thin"><color rgb="FFB8ADA0"/></top><bottom style="thin"><color rgb="FFB8ADA0"/></bottom></border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="5">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
            <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
            <xf numFmtId="0" fontId="3" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
            <xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"/>
          </cellXfs>
        </styleSheet>
        """

        // Helper to format inline string cell
        func cellStr(_ ref: String, _ text: String, style: Int = 0) -> String {
            let safe = text.replacingOccurrences(of: "&", with: "&amp;")
                           .replacingOccurrences(of: "<", with: "&lt;")
                           .replacingOccurrences(of: ">", with: "&gt;")
            let sAttr = style > 0 ? " s=\"\(style)\"" : ""
            return "<c r=\"\(ref)\"\(sAttr) t=\"inlineStr\"><is><t>\(safe)</t></is></c>"
        }

        func cellNum(_ ref: String, _ num: UInt64, style: Int = 0) -> String {
            let sAttr = style > 0 ? " s=\"\(style)\"" : ""
            return "<c r=\"\(ref)\"\(sAttr)><v>\(num)</v></c>"
        }

        // Sheet 1: Executive Summary
        var s1Rows: [String] = []
        s1Rows.append("<row r=\"1\">\(cellStr("A1", "NetGauge Network Usage Report", style: 2))</row>")
        s1Rows.append("<row r=\"2\">\(cellStr("A2", "Scope: \(report.scopeName)  •  Generated: \(report.generatedAt)"))</row>")
        s1Rows.append("<row r=\"4\">\(cellStr("A4", "Metric", style: 1))\(cellStr("B4", "Formatted Value", style: 1))\(cellStr("C4", "Exact Bytes", style: 1))</row>")
        s1Rows.append("<row r=\"5\">\(cellStr("A5", "Total Data Usage"))\(cellStr("B5", report.formattedTotal))\(cellNum("C5", report.totalBytes))</row>")
        s1Rows.append("<row r=\"6\">\(cellStr("A6", "Total Download"))\(cellStr("B6", report.formattedDownload))\(cellNum("C6", report.totalDownloadBytes))</row>")
        s1Rows.append("<row r=\"7\">\(cellStr("A7", "Total Upload"))\(cellStr("B7", report.formattedUpload))\(cellNum("C7", report.totalUploadBytes))</row>")
        s1Rows.append("<row r=\"8\">\(cellStr("A8", "Active Networks"))\(cellStr("B8", "\(report.networkCount)"))\(cellNum("C8", UInt64(report.networkCount)))</row>")
        s1Rows.append("<row r=\"9\">\(cellStr("A9", "Top Network"))\(cellStr("B9", report.topNetworkName))\(cellStr("C9", "-"))</row>")

        let sheet1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>
            <col min="1" max="1" width="26" customWidth="1"/>
            <col min="2" max="2" width="22" customWidth="1"/>
            <col min="3" max="3" width="20" customWidth="1"/>
          </cols>
          <sheetData>
            \(s1Rows.joined(separator: "\n"))
          </sheetData>
        </worksheet>
        """

        // Sheet 2: Monthly Summary
        var s2Rows: [String] = []
        s2Rows.append("<row r=\"1\">\(cellStr("A1", "Period / Month", style: 1))\(cellStr("B1", "Total Usage", style: 1))\(cellStr("C1", "Download", style: 1))\(cellStr("D1", "Upload", style: 1))\(cellStr("E1", "Top Network", style: 1))\(cellStr("F1", "% of Total Period", style: 1))\(cellStr("G1", "Total Bytes", style: 1))</row>")

        var rIdx = 2
        for m in report.monthlySummaries {
            let rowStyle = (rIdx % 2 == 1) ? 4 : 0
            let pctStr = String(format: "%.1f%%", m.percentageOfPeriod)
            s2Rows.append("<row r=\"\(rIdx)\">\(cellStr("A\(rIdx)", m.label, style: rowStyle))\(cellStr("B\(rIdx)", m.formattedTotal, style: rowStyle))\(cellStr("C\(rIdx)", m.formattedDownload, style: rowStyle))\(cellStr("D\(rIdx)", m.formattedUpload, style: rowStyle))\(cellStr("E\(rIdx)", m.topNetworkName, style: rowStyle))\(cellStr("F\(rIdx)", pctStr, style: rowStyle))\(cellNum("G\(rIdx)", m.totalBytes, style: rowStyle))</row>")
            rIdx += 1
        }

        let sheet2 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>
            <col min="1" max="1" width="22" customWidth="1"/>
            <col min="2" max="2" width="18" customWidth="1"/>
            <col min="3" max="3" width="18" customWidth="1"/>
            <col min="4" max="4" width="18" customWidth="1"/>
            <col min="5" max="5" width="25" customWidth="1"/>
            <col min="6" max="6" width="20" customWidth="1"/>
            <col min="7" max="7" width="20" customWidth="1"/>
          </cols>
          <sheetData>
            \(s2Rows.joined(separator: "\n"))
          </sheetData>
        </worksheet>
        """

        // Sheet 3: Wi-Fi & Hotspots
        var s3Rows: [String] = []
        s3Rows.append("<row r=\"1\">\(cellStr("A1", "Network / Hotspot Name", style: 1))\(cellStr("B1", "Connection Type", style: 1))\(cellStr("C1", "Total Usage", style: 1))\(cellStr("D1", "Download", style: 1))\(cellStr("E1", "Upload", style: 1))\(cellStr("F1", "% Share", style: 1))\(cellStr("G1", "Total Bytes", style: 1))</row>")

        rIdx = 2
        for net in report.networks {
            let rowStyle = (rIdx % 2 == 1) ? 4 : 0
            let pctStr = String(format: "%.1f%%", net.percentageOfTotal)
            s3Rows.append("<row r=\"\(rIdx)\">\(cellStr("A\(rIdx)", net.name, style: rowStyle))\(cellStr("B\(rIdx)", net.connectionType, style: rowStyle))\(cellStr("C\(rIdx)", net.formattedTotal, style: rowStyle))\(cellStr("D\(rIdx)", net.formattedDownload, style: rowStyle))\(cellStr("E\(rIdx)", net.formattedUpload, style: rowStyle))\(cellStr("F\(rIdx)", pctStr, style: rowStyle))\(cellNum("G\(rIdx)", net.totalBytes, style: rowStyle))</row>")
            rIdx += 1
        }

        let sheet3 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>
            <col min="1" max="1" width="30" customWidth="1"/>
            <col min="2" max="2" width="22" customWidth="1"/>
            <col min="3" max="3" width="18" customWidth="1"/>
            <col min="4" max="4" width="18" customWidth="1"/>
            <col min="5" max="5" width="18" customWidth="1"/>
            <col min="6" max="6" width="15" customWidth="1"/>
            <col min="7" max="7" width="20" customWidth="1"/>
          </cols>
          <sheetData>
            \(s3Rows.joined(separator: "\n"))
          </sheetData>
        </worksheet>
        """

        // Sheet 4: Daily Details
        var s4Rows: [String] = []
        s4Rows.append("<row r=\"1\">\(cellStr("A1", "Date", style: 1))\(cellStr("B1", "Network Name", style: 1))\(cellStr("C1", "Connection Type", style: 1))\(cellStr("D1", "Total Usage", style: 1))\(cellStr("E1", "Download", style: 1))\(cellStr("F1", "Upload", style: 1))\(cellStr("G1", "Total Bytes", style: 1))</row>")

        rIdx = 2
        for d in report.dailyRecords {
            let rowStyle = (rIdx % 2 == 1) ? 4 : 0
            s4Rows.append("<row r=\"\(rIdx)\">\(cellStr("A\(rIdx)", d.dateString, style: rowStyle))\(cellStr("B\(rIdx)", d.networkName, style: rowStyle))\(cellStr("C\(rIdx)", d.connectionType, style: rowStyle))\(cellStr("D\(rIdx)", d.formattedTotal, style: rowStyle))\(cellStr("E\(rIdx)", d.formattedDownload, style: rowStyle))\(cellStr("F\(rIdx)", d.formattedUpload, style: rowStyle))\(cellNum("G\(rIdx)", d.totalBytes, style: rowStyle))</row>")
            rIdx += 1
        }

        let sheet4 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <cols>
            <col min="1" max="1" width="16" customWidth="1"/>
            <col min="2" max="2" width="28" customWidth="1"/>
            <col min="3" max="3" width="20" customWidth="1"/>
            <col min="4" max="4" width="18" customWidth="1"/>
            <col min="5" max="5" width="18" customWidth="1"/>
            <col min="6" max="6" width="18" customWidth="1"/>
            <col min="7" max="7" width="20" customWidth="1"/>
          </cols>
          <sheetData>
            \(s4Rows.joined(separator: "\n"))
          </sheetData>
        </worksheet>
        """

        let zipEntries: [ZipEntry] = [
            ZipEntry(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipEntry(path: "_rels/.rels", data: Data(rootRels.utf8)),
            ZipEntry(path: "xl/_rels/workbook.xml.rels", data: Data(wbRels.utf8)),
            ZipEntry(path: "xl/workbook.xml", data: Data(workbook.utf8)),
            ZipEntry(path: "xl/styles.xml", data: Data(styles.utf8)),
            ZipEntry(path: "xl/worksheets/sheet1.xml", data: Data(sheet1.utf8)),
            ZipEntry(path: "xl/worksheets/sheet2.xml", data: Data(sheet2.utf8)),
            ZipEntry(path: "xl/worksheets/sheet3.xml", data: Data(sheet3.utf8)),
            ZipEntry(path: "xl/worksheets/sheet4.xml", data: Data(sheet4.utf8))
        ]

        return Self.createZipArchive(entries: zipEntries)
    }

    // MARK: - JSON Export

    public func generateJSON(report: ExportReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    // MARK: - In-Memory PKZIP Engine

    public struct ZipEntry {
        public let path: String
        public let data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    public static func createZipArchive(entries: [ZipEntry]) -> Data {
        var body = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameBytes = Array(entry.path.utf8)
            let nameLen = UInt16(nameBytes.count)
            let dataLen = UInt32(entry.data.count)
            let crc = UInt32(crc32(0, [UInt8](entry.data), uInt(entry.data.count)))
            let localOffset = UInt32(body.count)

            // Local File Header (30 bytes + name)
            var localHeader = Data()
            var sig: UInt32 = 0x04034b50; localHeader.append(Data(bytes: &sig, count: 4))
            var ver: UInt16 = 20;         localHeader.append(Data(bytes: &ver, count: 2))
            var flag: UInt16 = 0;         localHeader.append(Data(bytes: &flag, count: 2))
            var method: UInt16 = 0;       localHeader.append(Data(bytes: &method, count: 2)) // Stored
            var mtime: UInt16 = 0;        localHeader.append(Data(bytes: &mtime, count: 2))
            var mdate: UInt16 = 0;        localHeader.append(Data(bytes: &mdate, count: 2))
            var c = crc;                  localHeader.append(Data(bytes: &c, count: 4))
            var sz = dataLen;             localHeader.append(Data(bytes: &sz, count: 4))
            var usz = dataLen;            localHeader.append(Data(bytes: &usz, count: 4))
            var nlen = nameLen;           localHeader.append(Data(bytes: &nlen, count: 2))
            var elen: UInt16 = 0;         localHeader.append(Data(bytes: &elen, count: 2))
            localHeader.append(contentsOf: nameBytes)

            body.append(localHeader)
            body.append(entry.data)

            // Central Directory Entry (46 bytes + name)
            var cdEntry = Data()
            var cdSig: UInt32 = 0x02014b50; cdEntry.append(Data(bytes: &cdSig, count: 4))
            var cdVerMade: UInt16 = 20;     cdEntry.append(Data(bytes: &cdVerMade, count: 2))
            var cdVerNeed: UInt16 = 20;     cdEntry.append(Data(bytes: &cdVerNeed, count: 2))
            var cdFlag: UInt16 = 0;         cdEntry.append(Data(bytes: &cdFlag, count: 2))
            var cdMethod: UInt16 = 0;       cdEntry.append(Data(bytes: &cdMethod, count: 2))
            var cdMtime: UInt16 = 0;        cdEntry.append(Data(bytes: &cdMtime, count: 2))
            var cdMdate: UInt16 = 0;        cdEntry.append(Data(bytes: &cdMdate, count: 2))
            var cdCrc = crc;                cdEntry.append(Data(bytes: &cdCrc, count: 4))
            var cdSz = dataLen;             cdEntry.append(Data(bytes: &cdSz, count: 4))
            var cdUsz = dataLen;            cdEntry.append(Data(bytes: &cdUsz, count: 4))
            var cdNlen = nameLen;           cdEntry.append(Data(bytes: &cdNlen, count: 2))
            var cdElen: UInt16 = 0;         cdEntry.append(Data(bytes: &cdElen, count: 2))
            var cdCommentLen: UInt16 = 0;   cdEntry.append(Data(bytes: &cdCommentLen, count: 2))
            var cdDisk: UInt16 = 0;         cdEntry.append(Data(bytes: &cdDisk, count: 2))
            var cdAttr: UInt16 = 0;         cdEntry.append(Data(bytes: &cdAttr, count: 2))
            var cdExtAttr: UInt32 = 0;      cdEntry.append(Data(bytes: &cdExtAttr, count: 4))
            var cdOffset = localOffset;     cdEntry.append(Data(bytes: &cdOffset, count: 4))
            cdEntry.append(contentsOf: nameBytes)

            centralDirectory.append(cdEntry)
        }

        let cdOffset = UInt32(body.count)
        let cdSize = UInt32(centralDirectory.count)
        let entryCount = UInt16(entries.count)

        // End of Central Directory (22 bytes)
        var eocd = Data()
        var eocdSig: UInt32 = 0x06054b50; eocd.append(Data(bytes: &eocdSig, count: 4))
        var diskNo: UInt16 = 0;           eocd.append(Data(bytes: &diskNo, count: 2))
        var cdDiskNo: UInt16 = 0;         eocd.append(Data(bytes: &cdDiskNo, count: 2))
        var diskEntries = entryCount;     eocd.append(Data(bytes: &diskEntries, count: 2))
        var totalEntries = entryCount;    eocd.append(Data(bytes: &totalEntries, count: 2))
        var cSize = cdSize;               eocd.append(Data(bytes: &cSize, count: 4))
        var cOffset = cdOffset;           eocd.append(Data(bytes: &cOffset, count: 4))
        var commentLen: UInt16 = 0;       eocd.append(Data(bytes: &commentLen, count: 2))

        var result = Data()
        result.append(body)
        result.append(centralDirectory)
        result.append(eocd)
        return result
    }

    // MARK: - Save Dialog Helper

    @MainActor
    public func promptSave(
        format: ExportFormat,
        data: Data,
        defaultFilename: String
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save NetGauge \(format.rawValue)"
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let targetURL = panel.url else {
            return nil
        }

        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }
}
