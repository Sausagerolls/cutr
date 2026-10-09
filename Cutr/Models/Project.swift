import Foundation
import SwiftData

/// A saved cut list: the stock sheets available and the parts to cut from them.
/// All lengths are stored in millimetres and converted for display.
@Model
final class Project {
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Gap left between neighbouring parts (saw blade kerf plus any extra buffer).
    var kerf: Double = 3
    /// Margin trimmed off every edge of a sheet before parts are placed.
    var edgeTrim: Double = 0
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \StockSheet.project)
    var stocks: [StockSheet]? = []

    @Relationship(deleteRule: .cascade, inverse: \Part.project)
    var parts: [Part]? = []

    init(name: String, kerf: Double = 3, edgeTrim: Double = 0) {
        self.name = name
        self.kerf = kerf
        self.edgeTrim = edgeTrim
        self.createdAt = .now
        self.updatedAt = .now
    }

    var sortedStocks: [StockSheet] {
        (stocks ?? []).sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    var sortedParts: [Part] {
        (parts ?? []).sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    var totalPartCount: Int {
        (parts ?? []).reduce(0) { $0 + max($1.quantity, 0) }
    }

    func touch() {
        updatedAt = .now
    }

    /// Creates an independent copy including all stock sheets and parts.
    func duplicate(in context: ModelContext) -> Project {
        let copy = Project(name: String(localized: "\(name) Copy"), kerf: kerf, edgeTrim: edgeTrim)
        copy.notes = notes
        context.insert(copy)
        var idMap: [UUID: UUID] = [:]
        for stock in sortedStocks {
            let s = StockSheet(
                name: stock.name, length: stock.length, width: stock.width,
                thickness: stock.thickness, quantity: stock.quantity,
                price: stock.price, order: stock.order)
            idMap[stock.id] = s.id
            s.project = copy
        }
        for part in sortedParts {
            let p = Part(
                name: part.name, length: part.length, width: part.width,
                quantity: part.quantity, grainLocked: part.grainLocked,
                stockID: part.stockID.flatMap { idMap[$0] }, order: part.order)
            p.project = copy
        }
        return copy
    }
}

@Model
final class StockSheet {
    var id: UUID = UUID()
    var name: String = ""
    var length: Double = 2440
    var width: Double = 1220
    var thickness: Double = 18
    /// Number of sheets available. Zero means unlimited (buy as many as needed).
    var quantity: Int = 0
    /// Price per sheet in the user's local currency.
    var price: Double = 0
    var order: Int = 0
    var createdAt: Date = Date.now
    var project: Project?

    init(name: String, length: Double, width: Double, thickness: Double = 18,
         quantity: Int = 0, price: Double = 0, order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.length = length
        self.width = width
        self.thickness = thickness
        self.quantity = quantity
        self.price = price
        self.order = order
        self.createdAt = .now
    }
}

@Model
final class Part {
    var id: UUID = UUID()
    var name: String = ""
    var length: Double = 600
    var width: Double = 400
    var quantity: Int = 1
    /// When true the part keeps its orientation so the grain runs along the sheet length.
    var grainLocked: Bool = false
    /// The stock sheet this part must be cut from. Nil means the project's first stock sheet.
    var stockID: UUID?
    var order: Int = 0
    var createdAt: Date = Date.now
    var project: Project?

    init(name: String, length: Double, width: Double, quantity: Int = 1,
         grainLocked: Bool = false, stockID: UUID? = nil, order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.length = length
        self.width = width
        self.quantity = quantity
        self.grainLocked = grainLocked
        self.stockID = stockID
        self.order = order
        self.createdAt = .now
    }
}
