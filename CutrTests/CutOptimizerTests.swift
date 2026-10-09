import Testing
import Foundation
@testable import Cutr

struct CutOptimizerTests {
    let sheet = OptimizerStock(id: UUID(), name: "Ply", length: 2440, width: 1220, thickness: 18, available: nil, price: 50)

    func part(_ l: Double, _ w: Double, qty: Int = 1, rotate: Bool = true, stock: UUID? = nil) -> OptimizerPart {
        OptimizerPart(id: UUID(), label: "A", name: "", length: l, width: w, quantity: qty,
                      canRotate: rotate, stockID: stock ?? sheet.id, colorIndex: 0)
    }

    /// Every placement must sit inside the trimmed sheet and keep at least `kerf` from every other part.
    func assertValid(_ result: OptimizationResult, kerf: Double, trim: Double) {
        for layout in result.sheets {
            let usable = CGRect(x: trim, y: trim, width: layout.stock.length - 2 * trim, height: layout.stock.width - 2 * trim)
            for p in layout.placements {
                #expect(usable.insetBy(dx: -1e-6, dy: -1e-6).contains(p.rect), "part outside usable area: \(p.rect)")
            }
            for (i, a) in layout.placements.enumerated() {
                for b in layout.placements[(i + 1)...] {
                    let grown = a.rect.insetBy(dx: -kerf + 1e-6, dy: -kerf + 1e-6)
                    #expect(!grown.intersects(b.rect), "parts closer than kerf: \(a.rect) \(b.rect)")
                }
            }
        }
    }

    @Test func fourQuartersFillOneSheetWithoutKerf() {
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part(1220, 610, qty: 4)],
                                           settings: .init(kerf: 0, edgeTrim: 0))
        #expect(result.sheets.count == 1)
        #expect(result.unplacedCount == 0)
        #expect(abs(result.utilisation - 1) < 1e-9)
    }

    @Test func kerfForcesSecondSheet() {
        // Four exact quarters cannot fit once a 3 mm kerf is required between them.
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part(1220, 610, qty: 4)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        #expect(result.sheets.count == 2)
        assertValid(result, kerf: 3, trim: 0)
    }

    @Test func respectsKerfAndTrimOnRandomParts() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let parts = (0..<15).map { _ in
                part(Double.random(in: 50...1200, using: &rng), Double.random(in: 50...600, using: &rng),
                     qty: Int.random(in: 1...3, using: &rng), rotate: Bool.random(using: &rng))
            }
            let result = CutOptimizer.optimize(stocks: [sheet], parts: parts, settings: .init(kerf: 4, edgeTrim: 10))
            #expect(result.unplacedCount == 0)
            #expect(result.placedCount == parts.reduce(0) { $0 + $1.quantity })
            assertValid(result, kerf: 4, trim: 10)
        }
    }

    @Test func manySmallPartsFinishQuickly() {
        // Regression: 999 identical small parts used to take over 20 seconds in debug builds.
        let start = Date.now
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part(50, 50, qty: 999), part(120, 80, qty: 400)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        #expect(Date.now.timeIntervalSince(start) < 5)
        #expect(result.unplacedCount == 0)
        #expect(result.placedCount == 1399)
        assertValid(result, kerf: 3, trim: 0)
    }

    @Test func grainLockedPartIsNeverRotated() {
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part(600, 1000, qty: 3, rotate: false)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        for p in result.sheets.flatMap(\.placements) {
            #expect(!p.rotated)
            #expect(p.length == 600 && p.width == 1000)
        }
    }

    @Test func rotationLetsLongPartFit() {
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part(1000, 2000)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        #expect(result.unplacedCount == 0)
        #expect(result.sheets.first?.placements.first?.rotated == true)
    }

    @Test func oversizedPartIsReported() {
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part(3000, 100)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        #expect(result.sheets.isEmpty)
        #expect(result.unplaced.first?.reason == .tooLarge)
    }

    @Test func limitedStockReportsShortfall() {
        var limited = sheet
        limited.available = 1
        let result = CutOptimizer.optimize(stocks: [limited], parts: [part(1200, 1200, qty: 3, stock: limited.id)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        #expect(result.sheets.count == 1)
        #expect(result.placedCount == 2)
        #expect(result.unplaced.first?.reason == .outOfStock)
        #expect(result.unplacedCount == 1)
    }

    @Test func partsGoToTheirOwnMaterial() {
        let mdf = OptimizerStock(id: UUID(), name: "MDF", length: 1220, width: 610, thickness: 6, available: nil, price: 10)
        let result = CutOptimizer.optimize(stocks: [sheet, mdf],
                                           parts: [part(500, 500, qty: 2), part(300, 300, qty: 2, stock: mdf.id)],
                                           settings: .init(kerf: 3, edgeTrim: 0))
        #expect(result.sheets.count == 2)
        #expect(result.totalCost == 60)
        #expect(Set(result.sheets.map(\.stock.name)) == ["Ply", "MDF"])
    }
}

struct LengthUnitTests {
    @Test func inchFractions() {
        #expect(LengthUnit.inches.parse("23 1/2") == 23.5 * 25.4)
        #expect(LengthUnit.inches.parse("3/4\"") == 0.75 * 25.4)
        #expect(LengthUnit.inches.parse("12-3/8") == 12.375 * 25.4)
        #expect(LengthUnit.inches.format(23.5 * 25.4) == "23 1/2")
        #expect(LengthUnit.inches.format(3.175) == "1/8")
    }

    @Test func metric() {
        #expect(LengthUnit.millimetres.parse("2440") == 2440)
        #expect(LengthUnit.centimetres.parse("12,5") == 125)
        #expect(LengthUnit.millimetres.parse("abc") == nil)
        #expect(LengthUnit.millimetres.format(2440) == "2440")
    }

    @Test func autoLabels() {
        #expect(Project.autoLabel(0) == "A")
        #expect(Project.autoLabel(25) == "Z")
        #expect(Project.autoLabel(26) == "AA")
        #expect(Project.autoLabel(27) == "AB")
    }
}

struct PartShapeTests {
    let gable = PartShape.Preset.gable.points(length: 150, width: 260)

    @Test func areaAndBounds() {
        #expect(PartShape.area(PartShape.rectangle(length: 100, width: 50)) == 5000)
        // Gable: 150 × 260 blank minus two corner triangles with 75 mm legs.
        #expect(abs(PartShape.area(gable) - (150 * 260 - 2 * (75 * 75 / 2))) < 1e-6)
        #expect(PartShape.bounds(gable) == CGRect(x: 0, y: 0, width: 150, height: 260))
    }

    @Test func rectangleDetection() {
        #expect(PartShape.isRectangle(PartShape.rectangle(length: 10, width: 5)))
        // A point added on an edge but not moved is still a rectangle.
        var withPoint = PartShape.rectangle(length: 10, width: 5)
        withPoint.insert(ShapePoint(x: 5, y: 0), at: 1)
        #expect(PartShape.isRectangle(withPoint))
        #expect(!PartShape.isRectangle(gable))
    }

    @Test func selfIntersectionIsRejected() {
        let bowtie = [ShapePoint(x: 0, y: 0), ShapePoint(x: 10, y: 10), ShapePoint(x: 10, y: 0), ShapePoint(x: 0, y: 10)]
        #expect(!PartShape.isSimple(bowtie))
        #expect(PartShape.isSimple(gable))
        for preset in PartShape.Preset.allCases {
            #expect(PartShape.isSimple(preset.points(length: 300, width: 200)), "\(preset)")
        }
    }

    @Test func rotationKeepsShapeInsideRotatedBlank() {
        let rotated = PartShape.rotatedClockwise(gable, width: 260)
        #expect(PartShape.bounds(rotated) == CGRect(x: 0, y: 0, width: 260, height: 150))
        #expect(abs(PartShape.area(rotated) - PartShape.area(gable)) < 1e-6)
    }

    @Test func normalizedStartsAtOrigin() {
        let moved = gable.map { ShapePoint(x: $0.x - 40, y: $0.y + 25) }
        #expect(PartShape.normalized(moved) == gable)
    }

    @Test func shapedPartsPackAsBlanksAndYieldUsesRealArea() {
        let sheet = OptimizerStock(id: UUID(), name: "Ply", length: 1000, width: 1000, thickness: 18, available: nil, price: 0)
        let triangle = PartShape.Preset.rightTriangle.points(length: 400, width: 300)
        let part = OptimizerPart(id: UUID(), label: "A", name: "", length: 400, width: 300, quantity: 4,
                                 canRotate: true, stockID: sheet.id, colorIndex: 0, shape: triangle)
        let result = CutOptimizer.optimize(stocks: [sheet], parts: [part], settings: .init(kerf: 0, edgeTrim: 0))
        #expect(result.sheets.count == 1)
        #expect(result.placedCount == 4)
        for p in result.sheets[0].placements {
            let shape = try! #require(p.shape)
            // The outline always fits its placed blank, rotated or not.
            #expect(PartShape.bounds(shape) == CGRect(x: 0, y: 0, width: p.length, height: p.width))
        }
        // Yield counts the triangles' area (half of each blank), not the blanks.
        #expect(abs(result.totalPartArea - 4 * 400 * 300 / 2) < 1e-6)
    }
}
