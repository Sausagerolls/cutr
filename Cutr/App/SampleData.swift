import Foundation
import SwiftData

enum SampleData {
    static func insert(into context: ModelContext) {
        let renovation = Folder(name: String(localized: "Kitchen Renovation"))
        renovation.notes = String(localized: "Ground floor kitchen refit.")
        let workshop = Folder(name: String(localized: "Workshop"))
        context.insert(renovation)
        context.insert(workshop)

        let kitchen = Project(name: String(localized: "Kitchen Base Units"), kerf: 3, edgeTrim: 5)
        kitchen.notes = String(localized: "Carcasses for the three base units under the window.")
        kitchen.createdAt = .now.addingTimeInterval(-86_400 * 6)
        kitchen.updatedAt = .now.addingTimeInterval(-3_600)
        context.insert(kitchen)
        kitchen.folder = renovation
        let ply = StockSheet(name: "Birch Ply 18mm", length: 2440, width: 1220, thickness: 18, price: 72, order: 0)
        let mdf = StockSheet(name: "MDF 6mm", length: 2440, width: 1220, thickness: 6, price: 19, order: 1)
        ply.project = kitchen
        mdf.project = kitchen
        let kitchenParts: [(String, Double, Double, Int, Bool, StockSheet)] = [
            ("Side panel", 720, 560, 6, true, ply),
            ("Base", 764, 560, 3, false, ply),
            ("Top rail", 764, 100, 6, false, ply),
            ("Shelf", 760, 520, 3, false, ply),
            ("Kick board", 2400, 150, 1, true, ply),
            ("Back panel", 800, 720, 3, false, mdf),
            ("Drawer base", 700, 480, 3, false, mdf),
            ("Corner shelf", 500, 500, 2, false, ply),
        ]
        for (i, p) in kitchenParts.enumerated() {
            let part = Part(name: p.0, length: p.1, width: p.2, quantity: p.3, grainLocked: p.4, stockID: p.5.id, order: i)
            if p.0 == "Corner shelf" {
                part.shape = PartShape.Preset.rightTriangle.points(length: 500, width: 500)
            }
            part.project = kitchen
        }

        let shelf = Project(name: String(localized: "Garage Shelving"), kerf: 4, edgeTrim: 0)
        shelf.createdAt = .now.addingTimeInterval(-86_400 * 20)
        shelf.updatedAt = .now.addingTimeInterval(-86_400 * 2)
        context.insert(shelf)
        shelf.folder = workshop
        let osb = StockSheet(name: "OSB 18mm", length: 2440, width: 1220, thickness: 18, quantity: 3, price: 28, order: 0)
        osb.project = shelf
        for (i, p) in [("Upright", 1800.0, 400.0, 4), ("Shelf", 1180.0, 400.0, 6)].enumerated() {
            let part = Part(name: p.0, length: p.1, width: p.2, quantity: p.3, order: i)
            part.project = shelf
        }

        let desk = Project(name: String(localized: "Standing Desk"), kerf: 3, edgeTrim: 0)
        desk.createdAt = .now.addingTimeInterval(-86_400 * 45)
        desk.updatedAt = .now.addingTimeInterval(-86_400 * 30)
        context.insert(desk)
        let oak = StockSheet(name: "Oak Veneer Ply 25mm", length: 2440, width: 1220, thickness: 25, price: 145, order: 0)
        oak.project = desk
        for (i, p) in [("Desktop", 1600.0, 800.0, 1, true), ("Modesty panel", 1400.0, 350.0, 1, true), ("Shelf", 1400.0, 250.0, 1, false)].enumerated() {
            let part = Part(name: p.0, length: p.1, width: p.2, quantity: p.3, grainLocked: p.4, order: i)
            part.project = desk
        }

        let bird = Project(name: String(localized: "Bird Box"), kerf: 2, edgeTrim: 0)
        bird.createdAt = .now.addingTimeInterval(-86_400 * 90)
        bird.updatedAt = .now.addingTimeInterval(-86_400 * 88)
        context.insert(bird)
        let pine = StockSheet(name: "Pine Board", length: 1200, width: 150, thickness: 15, price: 6.5, order: 0)
        pine.project = bird
        for (i, p) in [("Front", 150.0, 260.0, 1), ("Back", 150.0, 260.0, 1), ("Side", 220.0, 120.0, 2), ("Roof", 200.0, 150.0, 2), ("Floor", 120.0, 120.0, 1)].enumerated() {
            let part = Part(name: p.0, length: p.1, width: p.2, quantity: p.3, grainLocked: false, order: i)
            if p.0 == "Front" || p.0 == "Back" {
                // Gable ends with a pointed top for the roof.
                part.shape = PartShape.Preset.gable.points(length: p.1, width: p.2)
            }
            part.project = bird
        }
        let wall = Project(name: String(localized: "Wall Cabinets"), kerf: 3, edgeTrim: 5)
        wall.createdAt = .now.addingTimeInterval(-86_400 * 5)
        wall.updatedAt = .now.addingTimeInterval(-86_400)
        context.insert(wall)
        wall.folder = renovation
        let wallPly = StockSheet(name: "Birch Ply 18mm", length: 2440, width: 1220, thickness: 18, price: 72, order: 0)
        wallPly.project = wall
        for (i, p) in [("Side", 720.0, 320.0, 6, true), ("Top & bottom", 564.0, 320.0, 6, false), ("Shelf", 560.0, 300.0, 3, false)].enumerated() {
            let part = Part(name: p.0, length: p.1, width: p.2, quantity: p.3, grainLocked: p.4, order: i)
            part.project = wall
        }

        try? context.save()
    }
}
