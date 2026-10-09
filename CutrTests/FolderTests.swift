import Testing
import Foundation
import SwiftData
@testable import Cutr

struct FolderTests {
    /// The container must outlive the context, so tests keep it in a local.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: CutrApp.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: CutrApp.schema, configurations: config)
        SampleData.insert(into: container.mainContext)
        return container
    }

    @Test func deletingProjectKeepsCutLists() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let folder = try #require(try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.name == "Kitchen Renovation" })).first)
        #expect(folder.cutListCount == 2)
        let before = try context.fetchCount(FetchDescriptor<Project>())
        context.delete(folder)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Project>()) == before)
        #expect(try context.fetch(FetchDescriptor<Project>()).allSatisfy { $0.folder?.name != "Kitchen Renovation" })
    }

    @Test func duplicateStaysInSameProject() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cutList = try #require(try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.name == "Wall Cabinets" })).first)
        let copy = cutList.duplicate(in: context)
        #expect(copy.folder == cutList.folder)
        #expect(copy.folder?.cutListCount == 3)
    }

    @Test func filterMatchesProjects() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let all = try context.fetch(FetchDescriptor<Project>())
        let folder = try #require(try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.name == "Workshop" })).first)
        #expect(all.filter { LibraryFilter.folder(folder).contains($0) }.map(\.name) == ["Garage Shelving"])
        #expect(Set(all.filter { LibraryFilter.ungrouped.contains($0) }.map(\.name)) == ["Standing Desk", "Bird Box"])
        #expect(all.filter { LibraryFilter.all.contains($0) }.count == all.count)
    }

    @Test func projectReportMergesMaterials() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let folder = try #require(try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.name == "Kitchen Renovation" })).first)
        let report = ProjectReport(folder: folder, unit: .millimetres)
        #expect(report.reports.count == 2)
        // Both cut lists use 2440 × 1220 × 18 birch ply, so it appears once in the shopping list.
        let ply = report.materials.filter { $0.name == "Birch Ply 18mm" }
        #expect(ply.count == 1)
        #expect(ply.first?.count == report.reports.flatMap(\.result.usage).filter { $0.stock.name == "Birch Ply 18mm" }.reduce(0) { $0 + $1.sheetsUsed })
        let data = PDFExporter.render(report)
        #expect(data.starts(with: Array("%PDF".utf8)))
        if let dir = ProcessInfo.processInfo.environment["CUTR_PDF_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("project.pdf"))
        }
    }
}
