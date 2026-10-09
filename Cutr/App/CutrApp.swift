import SwiftUI
import SwiftData

@main
struct CutrApp: App {
    let container: ModelContainer = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    static let schema = Schema([Folder.self, Project.self, StockSheet.self, Part.self])

    /// Uses CloudKit sync when iCloud is available, falling back to a local
    /// store so the app still works when signed out or without entitlements.
    static func makeContainer() -> ModelContainer {
        if LaunchOptions.isUITest {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
        if LaunchOptions.isDemo {
            // Screenshots and UI tests expect the default sort order.
            UserDefaults.standard.removeObject(forKey: SettingsKey.projectSort)
            UserDefaults.standard.removeObject(forKey: SettingsKey.projectSortAscending)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try! ModelContainer(for: schema, configurations: config)
            SampleData.insert(into: container.mainContext)
            return container
        }
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("CloudKit store unavailable, using local store: \(error)")
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
    }
}

/// Launch arguments used for App Store screenshots and UI tests.
enum LaunchOptions {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    /// Starts with an empty, in-memory store.
    static var isUITest: Bool { ProcessInfo.processInfo.arguments.contains("-uitest") }

    /// `-screen list|detail|layout|settings|part`
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
