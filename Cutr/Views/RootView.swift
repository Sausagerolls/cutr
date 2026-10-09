import SwiftUI
import SwiftData

/// What the cut list column shows: everything, ungrouped cut lists, or one project.
enum LibraryFilter: Hashable {
    case all
    case ungrouped
    case folder(Folder)

    var title: String {
        switch self {
        case .all: String(localized: "All Cut Lists")
        case .ungrouped: String(localized: "Not in a Project")
        case .folder(let folder): folder.name.isEmpty ? String(localized: "Untitled Project") : folder.name
        }
    }

    func contains(_ cutList: Project) -> Bool {
        switch self {
        case .all: true
        case .ungrouped: cutList.folder == nil
        case .folder(let folder): cutList.folder == folder
        }
    }

    /// The project new cut lists created in this view belong to.
    var folder: Folder? {
        if case .folder(let folder) = self { folder } else { nil }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone starts on the projects sidebar; iPad shows all cut lists alongside it.
    @State private var filter: LibraryFilter?
    @State private var selection: Project?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showSettings = false
    @AppStorage(SettingsKey.unit) private var unit: LengthUnit = Locale.current.measurementSystem == .us ? .inches : .millimetres

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(filter: $filter, showSettings: $showSettings)
        } content: {
            if let filter {
                ProjectListView(filter: filter, selection: $selection)
            } else {
                ContentUnavailableView("Choose a Project", systemImage: "folder",
                                       description: Text("Pick a project or All Cut Lists from the sidebar."))
            }
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
        .onChange(of: filter) {
            if let selection, let filter, !filter.contains(selection) {
                self.selection = nil
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.lengthUnit, unit)
        }
        .task {
            if sizeClass == .regular && filter == nil { filter = .all }
            applyScreenshotState()
        }
    }

    private func applyScreenshotState() {
        guard LaunchOptions.isDemo, let screen = LaunchOptions.screen else { return }
        let projects = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        switch screen {
        case "projects":
            columnVisibility = .all
        case "list":
            filter = .all
        case "detail", "layout", "part":
            filter = .all
            selection = projects.first
        case "shape":
            filter = .all
            selection = projects.first { $0.name == "Bird Box" }
        case "split":
            filter = .all
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
