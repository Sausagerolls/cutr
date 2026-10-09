import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SwiftData

/// A snapshot of everything needed to print a project, so PDF rendering
/// never touches SwiftData objects off the main actor.
nonisolated struct CutSheetReport: Sendable {
    struct PartRow: Sendable {
        var label: String
        var name: String
        var length: Double
        var width: Double
        var quantity: Int
        var grainLocked: Bool
        var stockName: String
        var colorIndex: Int
    }

    var title: String
    var notes: String
    var date: Date
    var unit: LengthUnit
    var kerf: Double
    var edgeTrim: Double
    var parts: [PartRow]
    var result: OptimizationResult

    @MainActor
    init(project: Project, result: OptimizationResult, unit: LengthUnit) {
        title = project.name.isEmpty ? String(localized: "Untitled Cut List") : project.name
        notes = project.notes
        date = .now
        self.unit = unit
        kerf = project.kerf
        edgeTrim = project.edgeTrim
        let stocks = project.sortedStocks
        let firstName = stocks.first?.name ?? ""
        parts = project.sortedParts.enumerated().map { index, part in
            let stockName = stocks.first { $0.id == part.stockID }?.name ?? firstName
            return PartRow(label: Project.autoLabel(index), name: part.name, length: part.length,
                           width: part.width, quantity: part.quantity, grainLocked: part.grainLocked,
                           stockName: stockName, colorIndex: index)
        }
        self.result = result
    }

    var fileName: String {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
        return "\(safe) – Cut Sheet.pdf"
    }
}

nonisolated enum PDFExporter {
    /// A4 portrait in points.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 36

    static func render(_ report: CutSheetReport) -> Data {
        renderDocument(title: report.title, project: nil, reports: [report])
    }

    /// Renders a project: a cover page summarising every cut list, then each cut list in full.
    static func render(_ project: ProjectReport) -> Data {
        renderDocument(title: project.title, project: project, reports: project.reports)
    }

    private static func renderDocument(title: String, project: ProjectReport?, reports: [CutSheetReport]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: {
            let format = UIGraphicsPDFRendererFormat()
            format.documentInfo = [
                kCGPDFContextTitle as String: title,
                kCGPDFContextCreator as String: "Cutr",
            ]
            return format
        }())
        return renderer.pdfData { ctx in
            var pageNumber = 0

            func beginPage() {
                ctx.beginPage()
                pageNumber += 1
                footer(page: pageNumber)
            }

            if let project {
                beginPage()
                cover(project) { beginPage(); return margin }
            }

            for report in reports {
                beginPage()
                var y = header(report)
                y = summary(report, top: y)
                y = partsTable(report, top: y) { beginPage(); return margin }

                // Sheets flow onto pages, two or more per page when they fit.
                y = content.maxY
                for (index, sheet) in report.result.sheets.enumerated() {
                    if index == 0 || y + sheetBlockHeight(sheet) > content.maxY {
                        beginPage()
                        y = content.minY
                    }
                    y = drawSheet(report, sheet: sheet, index: index, top: y, context: ctx.cgContext)
                }
            }
        }
    }

    private static func cover(_ p: ProjectReport, newPage: () -> CGFloat) {
        let currency = Locale.current.currency?.identifier ?? "GBP"
        var y = content.minY
        y += text(p.title, at: CGPoint(x: content.minX, y: y), attrs(24, .bold))
        let date = p.date.formatted(date: .long, time: .shortened)
        y += text(String(localized: "Project · \(p.reports.count) cut lists · \(date)"), at: CGPoint(x: content.minX, y: y + 2), attrs(10, color: .darkGray)) + 6
        if !p.notes.isEmpty {
            y += text(p.notes, at: CGPoint(x: content.minX, y: y), attrs(10)) + 6
        }
        line(y)
        y += 10

        let totals: [(String, String)] = [
            (String(localized: "Cut lists"), "\(p.reports.count)"),
            (String(localized: "Parts"), "\(p.totalParts)"),
            (String(localized: "Sheets"), "\(p.totalSheets)"),
            (String(localized: "Yield"), p.utilisation.formatted(.percent.precision(.fractionLength(0)))),
        ] + (p.totalCost > 0 ? [(String(localized: "Cost"), p.totalCost.formatted(.currency(code: currency)))] : [])
        let columnWidth = content.width / CGFloat(totals.count)
        for (i, stat) in totals.enumerated() {
            let x = content.minX + CGFloat(i) * columnWidth
            text(stat.0.uppercased(), at: CGPoint(x: x, y: y), width: columnWidth, attrs(7.5, .semibold, color: .darkGray))
            text(stat.1, at: CGPoint(x: x, y: y + 11), width: columnWidth, attrs(14, .semibold, mono: true))
        }
        y += 44

        // Shopping list across the whole project.
        y += text(String(localized: "Materials to buy"), at: CGPoint(x: content.minX, y: y), attrs(13, .bold)) + 6
        let u = p.unit
        for m in p.materials {
            var s = "\(m.count) × \(m.name) — \(u.format(m.length)) × \(u.format(m.width)) × \(u.format(m.thickness)) \(u.symbol)"
            if m.cost > 0 { s += " · " + m.cost.formatted(.currency(code: currency)) }
            y += text(s, at: CGPoint(x: content.minX, y: y), attrs(10)) + 3
        }
        y += 14

        // One row per cut list.
        y += text(String(localized: "Cut lists"), at: CGPoint(x: content.minX, y: y), attrs(13, .bold)) + 6
        let columns: [(String, CGFloat, Bool)] = [
            (String(localized: "Name"), content.width - 4 * 70 - 16, false),
            (String(localized: "Parts"), 70, true),
            (String(localized: "Sheets"), 70, true),
            (String(localized: "Yield"), 70, true),
            (String(localized: "Cost"), 70, true),
        ]
        func headerRow() {
            var x = content.minX
            for col in columns {
                text(col.0, at: CGPoint(x: x, y: y), width: col.1, attrs(8, .semibold, color: .darkGray), alignRight: col.2)
                x += col.1 + 4
            }
            y += 14
        }
        headerRow()
        for (i, r) in p.reports.enumerated() {
            if y > content.maxY - 30 {
                y = newPage()
                headerRow()
            }
            if i.isMultiple(of: 2), let cg = UIGraphicsGetCurrentContext() {
                cg.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
                cg.fill(CGRect(x: content.minX - 4, y: y - 2, width: content.width + 8, height: 16))
            }
            let values = [
                r.title, "\(r.result.placedCount)", "\(r.result.sheets.count)",
                r.result.utilisation.formatted(.percent.precision(.fractionLength(0))),
                r.result.totalCost > 0 ? r.result.totalCost.formatted(.currency(code: currency)) : "—",
            ]
            var x = content.minX
            for (col, value) in zip(columns, values) {
                text(value, at: CGPoint(x: x, y: y), width: col.1, attrs(9.5, mono: col.2), alignRight: col.2)
                x += col.1 + 4
            }
            y += 16
        }
    }

    // MARK: Pieces

    private static let content = CGRect(x: margin, y: margin, width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin)

    private static func attrs(_ size: CGFloat, _ weight: UIFont.Weight = .regular, color: UIColor = .black, mono: Bool = false) -> [NSAttributedString.Key: Any] {
        let font = mono ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : UIFont.systemFont(ofSize: size, weight: weight)
        return [.font: font, .foregroundColor: color]
    }

    @discardableResult
    private static func text(_ string: String, at point: CGPoint, width: CGFloat? = nil, _ attributes: [NSAttributedString.Key: Any], alignRight: Bool = false) -> CGFloat {
        let ns = string as NSString
        let size = ns.boundingRect(with: CGSize(width: width ?? content.width, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin], attributes: attributes, context: nil).size
        var origin = point
        if alignRight, let width { origin.x += width - size.width }
        ns.draw(with: CGRect(origin: origin, size: CGSize(width: width ?? content.width, height: size.height)),
                options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        return ceil(size.height)
    }

    private static func header(_ r: CutSheetReport) -> CGFloat {
        var y = content.minY
        y += text(r.title, at: CGPoint(x: content.minX, y: y), attrs(22, .bold))
        let date = r.date.formatted(date: .long, time: .shortened)
        y += text(String(localized: "Cut sheet · \(date)"), at: CGPoint(x: content.minX, y: y + 2), attrs(10, color: .darkGray)) + 6
        if !r.notes.isEmpty {
            y += text(r.notes, at: CGPoint(x: content.minX, y: y), attrs(10)) + 6
        }
        line(y)
        return y + 10
    }

    private static func line(_ y: CGFloat) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setStrokeColor(UIColor(white: 0.75, alpha: 1).cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: content.minX, y: y))
        cg.addLine(to: CGPoint(x: content.maxX, y: y))
        cg.strokePath()
    }

    private static func summary(_ r: CutSheetReport, top: CGFloat) -> CGFloat {
        let u = r.unit
        let res = r.result
        var stats: [(String, String)] = [
            (String(localized: "Sheets"), "\(res.sheets.count)"),
            (String(localized: "Parts"), "\(res.placedCount)"),
            (String(localized: "Yield"), res.utilisation.formatted(.percent.precision(.fractionLength(0)))),
            (String(localized: "Kerf / buffer"), u.format(r.kerf, includeSymbol: true)),
            (String(localized: "Edge trim"), u.format(r.edgeTrim, includeSymbol: true)),
        ]
        if res.totalCost > 0 {
            stats.append((String(localized: "Cost"), res.totalCost.formatted(.currency(code: Locale.current.currency?.identifier ?? "GBP"))))
        }
        let columnWidth = content.width / CGFloat(stats.count)
        for (i, stat) in stats.enumerated() {
            let x = content.minX + CGFloat(i) * columnWidth
            text(stat.0.uppercased(), at: CGPoint(x: x, y: top), width: columnWidth, attrs(7.5, .semibold, color: .darkGray))
            text(stat.1, at: CGPoint(x: x, y: top + 11), width: columnWidth, attrs(14, .semibold, mono: true))
        }
        var y = top + 36

        for usage in res.usage {
            let stock = usage.stock
            var s = "\(usage.sheetsUsed) × \(stock.name) — \(u.format(stock.length)) × \(u.format(stock.width)) × \(u.format(stock.thickness)) \(u.symbol)"
            if stock.price > 0 {
                s += " · " + usage.cost.formatted(.currency(code: Locale.current.currency?.identifier ?? "GBP"))
            }
            y += text(s, at: CGPoint(x: content.minX, y: y), attrs(10)) + 2
        }
        if !res.unplaced.isEmpty {
            y += 4
            for item in res.unplaced {
                let reason = item.reason == .tooLarge ? String(localized: "too large for sheet") : String(localized: "not enough sheets")
                y += text("⚠︎ \(item.count) × \(item.label) \(item.name) — \(reason)", at: CGPoint(x: content.minX, y: y), attrs(10, .semibold, color: .systemRed)) + 2
            }
        }
        line(y + 6)
        return y + 16
    }

    private static func partsTable(_ r: CutSheetReport, top: CGFloat, newPage: () -> CGFloat) -> CGFloat {
        let u = r.unit
        let columns: [(String, CGFloat, Bool)] = [
            ("", 14, false),
            (String(localized: "Label"), 40, false),
            (String(localized: "Name"), 150, false),
            (String(localized: "Length (\(u.symbol))"), 70, true),
            (String(localized: "Width (\(u.symbol))"), 70, true),
            (String(localized: "Qty"), 36, true),
            (String(localized: "Grain"), 44, false),
            (String(localized: "Material"), content.width - 424 - 20, false),
        ]
        var y = top
        y += text(String(localized: "Parts"), at: CGPoint(x: content.minX, y: y), attrs(13, .bold)) + 6

        func headerRow() {
            var x = content.minX
            for col in columns {
                text(col.0, at: CGPoint(x: x, y: y), width: col.1, attrs(8, .semibold, color: .darkGray), alignRight: col.2)
                x += col.1 + 4
            }
            y += 14
        }
        headerRow()

        for (i, part) in r.parts.enumerated() {
            if y > content.maxY - 30 {
                y = newPage()
                headerRow()
            }
            if i.isMultiple(of: 2), let cg = UIGraphicsGetCurrentContext() {
                cg.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
                cg.fill(CGRect(x: content.minX - 4, y: y - 2, width: content.width + 8, height: 16))
            }
            if let cg = UIGraphicsGetCurrentContext() {
                cg.setFillColor(SheetDrawing.color(part.colorIndex).cgColor)
                cg.fill(CGRect(x: content.minX + 2, y: y + 1, width: 9, height: 9))
            }
            let values = [
                "", part.label, part.name.isEmpty ? "—" : part.name,
                u.format(part.length), u.format(part.width), "\(part.quantity)",
                part.grainLocked ? String(localized: "Locked") : "", part.stockName,
            ]
            var x = content.minX
            for (col, value) in zip(columns, values) {
                text(value, at: CGPoint(x: x, y: y), width: col.1, attrs(9.5, mono: col.2), alignRight: col.2)
                x += col.1 + 4
            }
            y += 16
        }
        return y
    }

    /// Groups identical placements so the legend lists "3 × A" rather than three rows.
    private static func groups(_ sheet: SheetLayout) -> [(Placement, Int)] {
        var groups: [(Placement, Int)] = []
        for p in sheet.placements {
            if let i = groups.firstIndex(where: { $0.0.partID == p.partID && $0.0.rotated == p.rotated }) {
                groups[i].1 += 1
            } else {
                groups.append((p, 1))
            }
        }
        return groups
    }

    private static func diagramHeight(_ sheet: SheetLayout) -> CGFloat {
        min(content.width / SheetDrawing.aspect(sheet), content.height * 0.6)
    }

    /// Height a sheet block needs: title, diagram, caption and legend.
    private static func sheetBlockHeight(_ sheet: SheetLayout) -> CGFloat {
        let rows = CGFloat((groups(sheet).count + 1) / 2)
        return 36 + diagramHeight(sheet) + 22 + 18 + rows * 14 + 24
    }

    /// Draws one sheet starting at `top` and returns the y position after it.
    private static func drawSheet(_ r: CutSheetReport, sheet: SheetLayout, index: Int, top: CGFloat, context cg: CGContext) -> CGFloat {
        let u = r.unit
        var y = top
        y += text(String(localized: "Sheet \(index + 1) of \(r.result.sheets.count)"), at: CGPoint(x: content.minX, y: y), attrs(15, .bold))
        let utilisation = sheet.utilisation.formatted(.percent.precision(.fractionLength(0)))
        y += text("\(sheet.stock.name) · \(u.format(sheet.stock.length)) × \(u.format(sheet.stock.width)) \(u.symbol) · \(String(localized: "\(utilisation) used"))",
                  at: CGPoint(x: content.minX, y: y + 2), attrs(10, color: .darkGray)) + 10

        let height = diagramHeight(sheet)
        let drawnWidth = height * SheetDrawing.aspect(sheet)
        let rect = CGRect(x: content.minX, y: y, width: content.width, height: height)
        SheetDrawing.draw(sheet, in: rect, unit: u, trim: r.edgeTrim, style: .print, context: cg)
        y += height + 4

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        var caption = attrs(9, color: .darkGray)
        caption[.paragraphStyle] = center
        text(String(localized: "Length \(u.format(sheet.stock.length, includeSymbol: true)) (left to right) · Width \(u.format(sheet.stock.width, includeSymbol: true))"),
             at: CGPoint(x: content.midX - drawnWidth / 2, y: y), width: drawnWidth, caption)
        y += 18

        let colWidth = content.width / 2
        var col = 0
        for (p, count) in groups(sheet) {
            let x = content.minX + CGFloat(col) * colWidth
            cg.setFillColor(SheetDrawing.color(p.colorIndex).cgColor)
            cg.fill(CGRect(x: x, y: y + 2, width: 8, height: 8))
            var s = "\(count) × \(p.label)"
            if !p.name.isEmpty { s += " \(p.name)" }
            s += " — \(u.format(p.length)) × \(u.format(p.width))"
            if p.rotated { s += " ↻" }
            text(s, at: CGPoint(x: x + 12, y: y), width: colWidth - 16, attrs(9.5))
            col += 1
            if col == 2 { col = 0; y += 14 }
        }
        if col != 0 { y += 14 }
        return y + 24
    }

    private static func footer(page: Int) {
        let a = attrs(8, color: .gray)
        text(String(localized: "Generated with Cutr"), at: CGPoint(x: content.minX, y: pageSize.height - margin + 10), width: 200, a)
        text(String(localized: "Page \(page)"), at: CGPoint(x: content.maxX - 200, y: pageSize.height - margin + 10), width: 200, a, alignRight: true)
    }
}

/// Everything needed to print a project of several cut lists.
nonisolated struct ProjectReport: Sendable {
    struct Material: Sendable {
        var name: String
        var length: Double
        var width: Double
        var thickness: Double
        var count: Int
        var cost: Double
    }

    var title: String
    var notes: String
    var date: Date
    var unit: LengthUnit
    var reports: [CutSheetReport]

    @MainActor
    init(folder: Folder, unit: LengthUnit) {
        title = folder.name.isEmpty ? String(localized: "Untitled Project") : folder.name
        notes = folder.notes
        date = .now
        self.unit = unit
        reports = folder.sortedCutLists.map { CutSheetReport(project: $0, result: $0.optimize(), unit: unit) }
    }

    var totalParts: Int { reports.reduce(0) { $0 + $1.result.placedCount } }
    var totalSheets: Int { reports.reduce(0) { $0 + $1.result.sheets.count } }
    var totalCost: Double { reports.reduce(0) { $0 + $1.result.totalCost } }
    var utilisation: Double {
        let sheetArea = reports.reduce(0) { $0 + $1.result.totalSheetArea }
        return sheetArea > 0 ? reports.reduce(0) { $0 + $1.result.totalPartArea } / sheetArea : 0
    }

    /// Sheets needed across all cut lists, merged when the material and size match.
    var materials: [Material] {
        var merged: [Material] = []
        for usage in reports.flatMap(\.result.usage) {
            let s = usage.stock
            if let i = merged.firstIndex(where: {
                $0.name == s.name && $0.length == s.length && $0.width == s.width && $0.thickness == s.thickness
            }) {
                merged[i].count += usage.sheetsUsed
                merged[i].cost += usage.cost
            } else {
                merged.append(Material(name: s.name, length: s.length, width: s.width, thickness: s.thickness,
                                       count: usage.sheetsUsed, cost: usage.cost))
            }
        }
        return merged
    }

    var fileName: String { Self.fileName(for: title) }

    static func fileName(for title: String) -> String {
        let name = title.isEmpty ? String(localized: "Untitled Project") : title
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "-")
        return "\(safe) – Project Cut Sheets.pdf"
    }
}

/// Lets SwiftUI's ShareLink export a cut sheet or project as a named PDF file.
/// The PDF is only built when the user actually shares or prints it.
nonisolated struct CutSheetPDF: Transferable, Sendable {
    var fileName: String
    var render: @Sendable () async -> Data

    init(report: CutSheetReport) {
        fileName = report.fileName
        render = { PDFExporter.render(report) }
    }

    @MainActor
    init(folder: Folder, unit: LengthUnit) {
        fileName = ProjectReport.fileName(for: folder.name)
        // Models are not Sendable, so look the folder up again on the main actor by ID.
        let id = folder.persistentModelID
        let container = folder.modelContext?.container
        render = {
            let report = await MainActor.run { () -> ProjectReport? in
                guard let folder = container?.mainContext.model(for: id) as? Folder else { return nil }
                return ProjectReport(folder: folder, unit: unit)
            }
            return report.map(PDFExporter.render) ?? Data()
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { pdf in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(pdf.fileName)
            try await pdf.render().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

enum PrintService {
    static func print(_ pdf: CutSheetPDF) {
        Task {
            let data = await pdf.render()
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = (pdf.fileName as NSString).deletingPathExtension
            controller.printInfo = info
            controller.printingItem = data
            controller.present(animated: true)
        }
    }
}
