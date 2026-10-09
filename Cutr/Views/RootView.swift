import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selection: Project?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showSettings = false
    @AppStorage(SettingsKey.unit) private var unit: LengthUnit = Locale.current.measurementSystem == .us ? .inches : .millimetres

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectListView(selection: $selection, showSettings: $showSettings)
        } detail: {
            NavigationStack {
                if let selection {
                    ProjectDetailView(project: selection)
                        .id(selection.persistentModelID)
                } else {
                    ContentUnavailableView {
                        Label("No Cut List Selected", systemImage: "square.split.2x2")
                    } description: {
                        Text("Choose a cut list or create a new one to plan your cuts.")
                    }
                }
            }
        }
        .environment(\.lengthUnit, unit)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.lengthUnit, unit)
        }
        .task {
            applyScreenshotState()
        }
    }

    private func applyScreenshotState() {
        guard LaunchOptions.isDemo, let screen = LaunchOptions.screen else { return }
        let projects = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        switch screen {
        case "detail", "layout", "part":
            selection = projects.first
        case "split":
            selection = projects.first
            columnVisibility = .all
        case "settings":
            showSettings = true
        default:
            break
        }
    }
}

private struct LengthUnitKey: EnvironmentKey {
    static let defaultValue: LengthUnit = .millimetres
}

extension EnvironmentValues {
    var lengthUnit: LengthUnit {
        get { self[LengthUnitKey.self] }
        set { self[LengthUnitKey.self] = newValue }
    }
}

enum Currency {
    static var code: String { Locale.current.currency?.identifier ?? "GBP" }
}
