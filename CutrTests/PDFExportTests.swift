import Testing
import Foundation
import SwiftData
@testable import Cutr

struct PDFExportTests {
    @Test func rendersSampleProject() throws {
        let config = ModelConfiguration(schema: CutrApp.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: CutrApp.schema, configurations: config)
        SampleData.insert(into: container.mainContext)
        let project = try #require(try container.mainContext.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.name == "Kitchen Base Units" })).first)
        let result = project.optimize()
        let data = PDFExporter.render(CutSheetReport(project: project, result: result, unit: .millimetres))
        #expect(data.starts(with: Array("%PDF".utf8)))
        if let dir = ProcessInfo.processInfo.environment["CUTR_PDF_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sample.pdf"))
        }
    }
}
