import Foundation
import CoreGraphics

// MARK: - Inputs

nonisolated struct OptimizerStock: Sendable, Hashable {
    var id: UUID
    var name: String
    var length: Double
    var width: Double
    var thickness: Double
    /// Nil means unlimited.
    var available: Int?
    var price: Double
}

nonisolated struct OptimizerPart: Sendable, Hashable {
    var id: UUID
    var label: String
    var name: String
    var length: Double
    var width: Double
    var quantity: Int
    var canRotate: Bool
    var stockID: UUID
    var colorIndex: Int
}

nonisolated struct OptimizerSettings: Sendable, Hashable {
    var kerf: Double
    var edgeTrim: Double
}

// MARK: - Outputs

nonisolated struct Placement: Sendable, Hashable, Identifiable {
    var id = UUID()
    var partID: UUID
    var label: String
    var name: String
    var colorIndex: Int
    var x: Double
    var y: Double
    /// Size along the sheet length (x axis).
    var length: Double
    /// Size along the sheet width (y axis).
    var width: Double
    var rotated: Bool

    var rect: CGRect { CGRect(x: x, y: y, width: length, height: width) }
}

nonisolated struct SheetLayout: Sendable, Equatable, Identifiable {
    var id = UUID()
    var stock: OptimizerStock
    var placements: [Placement]
    /// Leftover rectangles after cutting, useful as offcuts.
    var offcuts: [CGRect]

    var sheetArea: Double { stock.length * stock.width }
    var usedArea: Double { placements.reduce(0) { $0 + $1.length * $1.width } }
    var utilisation: Double { sheetArea > 0 ? usedArea / sheetArea : 0 }
}

nonisolated struct UnplacedPart: Sendable, Hashable, Identifiable {
    var id: UUID { partID }
    var partID: UUID
    var label: String
    var name: String
    var count: Int
    var reason: Reason

    enum Reason: Sendable, Hashable {
        case tooLarge
        case outOfStock
    }
}

nonisolated struct StockUsage: Sendable, Hashable, Identifiable {
    var id: UUID { stock.id }
    var stock: OptimizerStock
    var sheetsUsed: Int
    var cost: Double { Double(sheetsUsed) * stock.price }
}

nonisolated struct OptimizationResult: Sendable, Equatable {
    var sheets: [SheetLayout]
    var unplaced: [UnplacedPart]
    var settings: OptimizerSettings

    static let empty = OptimizationResult(sheets: [], unplaced: [], settings: .init(kerf: 0, edgeTrim: 0))

    var usage: [StockUsage] {
        var order: [UUID] = []
        var counts: [UUID: (OptimizerStock, Int)] = [:]
        for sheet in sheets {
            if counts[sheet.stock.id] == nil { order.append(sheet.stock.id) }
            counts[sheet.stock.id, default: (sheet.stock, 0)].1 += 1
        }
        return order.compactMap { id in counts[id].map { StockUsage(stock: $0.0, sheetsUsed: $0.1) } }
    }

    var totalCost: Double { usage.reduce(0) { $0 + $1.cost } }
    var totalSheetArea: Double { sheets.reduce(0) { $0 + $1.sheetArea } }
    var totalPartArea: Double { sheets.reduce(0) { $0 + $1.usedArea } }
    var utilisation: Double { totalSheetArea > 0 ? totalPartArea / totalSheetArea : 0 }
    var placedCount: Int { sheets.reduce(0) { $0 + $1.placements.count } }
    var unplacedCount: Int { unplaced.reduce(0) { $0 + $1.count } }
}

// MARK: - Optimizer

/// Guillotine bin packer. Every layout it produces can be cut with straight,
/// edge-to-edge cuts on a table saw or panel saw. It runs many combinations of
/// sort order, placement rule and split rule and keeps the best result.
nonisolated enum CutOptimizer {
    private static let epsilon = 1e-6

    enum SortRule: CaseIterable { case area, longestSide, perimeter, length, width }
    enum FitRule: CaseIterable { case bestArea, bestShortSide, bestLongSide, topLeft }
    enum SplitRule: CaseIterable { case shorterLeftover, longerLeftover, minArea, maxArea, horizontal, vertical }

    static func optimize(stocks: [OptimizerStock], parts: [OptimizerPart], settings: OptimizerSettings) -> OptimizationResult {
        var sheets: [SheetLayout] = []
        var unplaced: [UnplacedPart] = []
        for stock in stocks {
            let group = parts.filter { $0.stockID == stock.id && $0.quantity > 0 }
            guard !group.isEmpty else { continue }
            let result = optimize(stock: stock, parts: group, settings: settings)
            sheets += result.sheets
            unplaced += result.unplaced
        }
        // Parts pointing to stock that no longer exists.
        let stockIDs = Set(stocks.map(\.id))
        for part in parts where !stockIDs.contains(part.stockID) && part.quantity > 0 {
            unplaced.append(UnplacedPart(partID: part.id, label: part.label, name: part.name,
                                         count: part.quantity, reason: .outOfStock))
        }
        return OptimizationResult(sheets: sheets, unplaced: unplaced, settings: settings)
    }

    private struct Item {
        var part: OptimizerPart
    }

    private struct WorkingSheet {
        var free: [CGRect]
        var placements: [Placement]
    }

    private static func optimize(stock: OptimizerStock, parts: [OptimizerPart], settings: OptimizerSettings) -> (sheets: [SheetLayout], unplaced: [UnplacedPart]) {
        let trim = max(settings.edgeTrim, 0)
        let kerf = max(settings.kerf, 0)
        let usable = CGRect(x: trim, y: trim, width: stock.length - 2 * trim, height: stock.width - 2 * trim)

        var tooLarge: [UnplacedPart] = []
        var items: [OptimizerPart] = []
        for part in parts {
            if fits(part.length, part.width, in: usable.size) || (part.canRotate && fits(part.width, part.length, in: usable.size)) {
                for _ in 0..<part.quantity { items.append(part) }
            } else {
                tooLarge.append(UnplacedPart(partID: part.id, label: part.label, name: part.name,
                                             count: part.quantity, reason: .tooLarge))
            }
        }

        var best: (sheets: [WorkingSheet], unplaced: [OptimizerPart], score: Score)?
        for sort in SortRule.allCases {
            let ordered = sorted(items, by: sort)
            for fit in FitRule.allCases {
                for split in SplitRule.allCases {
                    let run = pack(ordered, usable: usable, kerf: kerf, available: stock.available, fit: fit, split: split)
                    let score = Score(run.sheets, unplaced: run.unplaced.count, sheetArea: usable.width * usable.height)
                    if best == nil || score < best!.score {
                        best = (run.sheets, run.unplaced, score)
                    }
                }
            }
        }

        var unplaced = tooLarge
        if let best {
            var outOfStock: [UUID: UnplacedPart] = [:]
            var order: [UUID] = []
            for part in best.unplaced {
                if outOfStock[part.id] == nil {
                    order.append(part.id)
                    outOfStock[part.id] = UnplacedPart(partID: part.id, label: part.label, name: part.name, count: 0, reason: .outOfStock)
                }
                outOfStock[part.id]!.count += 1
            }
            unplaced += order.compactMap { outOfStock[$0] }
            let layouts = best.sheets.map { sheet in
                SheetLayout(stock: stock,
                            placements: sheet.placements.sorted { ($0.y, $0.x) < ($1.y, $1.x) },
                            offcuts: sheet.free.filter { $0.width > 1 && $0.height > 1 })
            }
            return (layouts, unplaced)
        }
        return ([], unplaced)
    }

    /// Lower is better: fewest unplaced, then fewest sheets, then the most
    /// concentrated usage (so the last sheet keeps the largest offcut).
    private struct Score: Comparable {
        var unplaced: Int
        var sheets: Int
        var spread: Double

        init(_ sheets: [WorkingSheet], unplaced: Int, sheetArea: Double) {
            self.unplaced = unplaced
            self.sheets = sheets.count
            // Sum of squared fill ratios is larger when sheets are packed fuller.
            // It is also larger when the biggest free rect is larger. Negate so lower wins.
            var fill = 0.0
            for sheet in sheets {
                let used = sheet.placements.reduce(0) { $0 + $1.length * $1.width }
                let ratio = sheetArea > 0 ? used / sheetArea : 0
                fill += ratio * ratio
                let biggest = sheet.free.map { $0.width * $0.height }.max() ?? 0
                fill += 0.01 * (sheetArea > 0 ? biggest / sheetArea : 0)
            }
            self.spread = -fill
        }

        static func < (a: Score, b: Score) -> Bool {
            (a.unplaced, a.sheets, a.spread) < (b.unplaced, b.sheets, b.spread)
        }
    }

    private static func sorted(_ items: [OptimizerPart], by rule: SortRule) -> [OptimizerPart] {
        func key(_ p: OptimizerPart) -> (Double, Double) {
            let long = max(p.length, p.width), short = min(p.length, p.width)
            switch rule {
            case .area: return (p.length * p.width, long)
            case .longestSide: return (long, short)
            case .perimeter: return (long + short, long)
            case .length: return (p.length, p.width)
            case .width: return (p.width, p.length)
            }
        }
        return items.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            if ka != kb { return ka > kb }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func fits(_ length: Double, _ width: Double, in size: CGSize) -> Bool {
        length <= size.width + epsilon && width <= size.height + epsilon
    }

    private static func pack(_ items: [OptimizerPart], usable: CGRect, kerf: Double, available: Int?,
                             fit: FitRule, split: SplitRule) -> (sheets: [WorkingSheet], unplaced: [OptimizerPart]) {
        var sheets: [WorkingSheet] = []
        var unplaced: [OptimizerPart] = []

        for part in items {
            var choice: (sheet: Int, rect: Int, rotated: Bool, score: (Double, Double))?
            for (s, sheet) in sheets.enumerated() {
                for (r, free) in sheet.free.enumerated() {
                    for rotated in orientations(part) {
                        let (l, w) = rotated ? (part.width, part.length) : (part.length, part.width)
                        guard fits(l, w, in: free.size) else { continue }
                        let score = fitScore(fit, free: free, length: l, width: w)
                        if choice == nil || score < choice!.score {
                            choice = (s, r, rotated, score)
                        }
                    }
                }
            }

            if choice == nil {
                if let available, sheets.count >= available {
                    unplaced.append(part)
                    continue
                }
                sheets.append(WorkingSheet(free: [usable], placements: []))
                let s = sheets.count - 1
                for rotated in orientations(part) {
                    let (l, w) = rotated ? (part.width, part.length) : (part.length, part.width)
                    guard fits(l, w, in: usable.size) else { continue }
                    let score = fitScore(fit, free: usable, length: l, width: w)
                    if choice == nil || score < choice!.score { choice = (s, 0, rotated, score) }
                }
            }

            guard let choice else {
                unplaced.append(part)
                continue
            }

            let free = sheets[choice.sheet].free.remove(at: choice.rect)
            let (l, w) = choice.rotated ? (part.width, part.length) : (part.length, part.width)
            sheets[choice.sheet].placements.append(Placement(
                partID: part.id, label: part.label, name: part.name, colorIndex: part.colorIndex,
                x: free.minX, y: free.minY, length: l, width: w, rotated: choice.rotated))
            sheets[choice.sheet].free += splitFree(free, length: l, width: w, kerf: kerf, rule: split)
        }
        return (sheets, unplaced)
    }

    private static func orientations(_ part: OptimizerPart) -> [Bool] {
        part.canRotate && abs(part.length - part.width) > epsilon ? [false, true] : [false]
    }

    private static func fitScore(_ rule: FitRule, free: CGRect, length: Double, width: Double) -> (Double, Double) {
        let dl = free.width - length, dw = free.height - width
        switch rule {
        case .bestArea: return (free.width * free.height - length * width, min(dl, dw))
        case .bestShortSide: return (min(dl, dw), max(dl, dw))
        case .bestLongSide: return (max(dl, dw), min(dl, dw))
        case .topLeft: return (free.minY, free.minX)
        }
    }

    /// Places the part at the top-left corner of `free` and returns the two
    /// leftover rectangles, separated from the part by the kerf.
    private static func splitFree(_ free: CGRect, length: Double, width: Double, kerf: Double, rule: SplitRule) -> [CGRect] {
        let rightW = free.width - length - kerf
        let bottomH = free.height - width - kerf

        let horizontal: Bool
        switch rule {
        case .shorterLeftover: horizontal = rightW < bottomH
        case .longerLeftover: horizontal = rightW >= bottomH
        case .minArea: horizontal = rightW * width < length * bottomH
        case .maxArea: horizontal = rightW * width >= length * bottomH
        case .horizontal: horizontal = true
        case .vertical: horizontal = false
        }

        var right: CGRect
        var bottom: CGRect
        if horizontal {
            // First cut runs the full length of the free rect, below the part.
            bottom = CGRect(x: free.minX, y: free.minY + width + kerf, width: free.width, height: bottomH)
            right = CGRect(x: free.minX + length + kerf, y: free.minY, width: rightW, height: width)
        } else {
            // First cut runs the full width of the free rect, beside the part.
            right = CGRect(x: free.minX + length + kerf, y: free.minY, width: rightW, height: free.height)
            bottom = CGRect(x: free.minX, y: free.minY + width + kerf, width: length, height: bottomH)
        }
        return [right, bottom].filter { $0.width > epsilon && $0.height > epsilon }
    }
}

// MARK: - Model bridge

extension Project {
    /// Label for a part at `index` in sorted order: A, B, … Z, AA, AB …
    static func autoLabel(_ index: Int) -> String {
        var n = index
        var label = ""
        repeat {
            label = String(UnicodeScalar(UInt8(65 + n % 26))) + label
            n = n / 26 - 1
        } while n >= 0
        return label
    }

    var optimizerSettings: OptimizerSettings {
        OptimizerSettings(kerf: kerf, edgeTrim: edgeTrim)
    }

    func optimizerInput() -> (stocks: [OptimizerStock], parts: [OptimizerPart]) {
        let stocks = sortedStocks.map {
            OptimizerStock(id: $0.id, name: $0.name, length: $0.length, width: $0.width,
                           thickness: $0.thickness, available: $0.quantity > 0 ? $0.quantity : nil, price: $0.price)
        }
        let fallback = stocks.first?.id ?? UUID()
        let validIDs = Set(stocks.map(\.id))
        let parts = sortedParts.enumerated().map { index, part in
            let stockID = part.stockID.flatMap { validIDs.contains($0) ? $0 : nil } ?? fallback
            return OptimizerPart(id: part.id, label: Self.autoLabel(index), name: part.name,
                                 length: part.length, width: part.width, quantity: part.quantity,
                                 canRotate: !part.grainLocked, stockID: stockID, colorIndex: index)
        }
        return (stocks, parts)
    }

    func optimize() -> OptimizationResult {
        let input = optimizerInput()
        return CutOptimizer.optimize(stocks: input.stocks, parts: input.parts, settings: optimizerSettings)
    }
}
