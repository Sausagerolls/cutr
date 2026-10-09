import SwiftUI
import SwiftData

enum ProjectSort: String, CaseIterable, Identifiable {
    case modified, created, name, parts

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .modified: "Date Modified"
        case .created: "Date Created"
        case .name: "Name"
        case .parts: "Number of Parts"
        }
    }

    /// The natural direction for each key: newest first, A–Z, most parts first.
    var defaultAscending: Bool { self == .name }
}

struct ProjectListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.lengthUnit) private var unit
    @Query private var allProjects: [Project]
    @Query(sort: \Folder.name) private var folders: [Folder]
    let filter: LibraryFilter
    @Binding var selection: Project?

    @AppStorage(SettingsKey.projectSort) private var sort: ProjectSort = .modified
    @AppStorage(SettingsKey.projectSortAscending) private var ascending = false
    @AppStorage(SettingsKey.defaultKerf) private var defaultKerf = 3.0
    @AppStorage(SettingsKey.defaultEdgeTrim) private var defaultEdgeTrim = 0.0
    @AppStorage(SettingsKey.defaultSheetLength) private var defaultSheetLength = 2440.0
    @AppStorage(SettingsKey.defaultSheetWidth) private var defaultSheetWidth = 1220.0
    @AppStorage(SettingsKey.defaultSheetThickness) private var defaultSheetThickness = 18.0
    @State private var search = ""
    @State private var pendingDelete: Project?

    private var projects: [Project] {
        allProjects.filter { filter.contains($0) }
    }

    private var visibleProjects: [Project] {
        let filtered = search.isEmpty ? projects : projects.filter {
            $0.name.localizedStandardContains(search) || $0.notes.localizedStandardContains(search)
                || ($0.parts ?? []).contains { $0.name.localizedStandardContains(search) }
        }
        let sorted = filtered.sorted { a, b in
            switch sort {
            case .modified: a.updatedAt < b.updatedAt
            case .created: a.createdAt < b.createdAt
            case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .parts: a.totalPartCount < b.totalPartCount
            }
        }
        return ascending ? sorted : sorted.reversed()
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(visibleProjects) { project in
                NavigationLink(value: project) {
                    ProjectRow(project: project, sort: sort, showFolder: filter == .all)
                }
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        selection = project.duplicate(in: context)
                    }
                    moveMenu(for: project)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDelete = project
                    }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDelete = project
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        selection = project.duplicate(in: context)
                    }
                    .tint(.indigo)
                }
            }
        }
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("No Cut Lists", systemImage: "rectangle.split.3x3")
                } description: {
                    if filter.folder != nil {
                        Text("Add a cut list to this project for each piece of furniture or job.")
                    } else {
                        Text("Add your sheet sizes and the parts you need. Cutr works out the most efficient way to cut them.")
                    }
                } actions: {
                    Button("New Cut List", action: addProject)
                        .buttonStyle(.borderedProminent)
                }
            } else if visibleProjects.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle(filter.title)
        .searchable(text: $search, prompt: "Search cut lists")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let folder = filter.folder, !projects.isEmpty {
                    Menu("Export Project", systemImage: "square.and.arrow.up") {
                        let pdf = CutSheetPDF(folder: folder, unit: unit)
                        ShareLink(item: pdf, preview: SharePreview(pdf.fileName, image: Image(systemName: "doc.richtext"))) {
                            Label("Export Project PDF", systemImage: "doc.richtext")
                        }
                        Button("Print Project", systemImage: "printer") { PrintService.print(pdf) }
                    }
                }
                sortMenu
                Button("New Cut List", systemImage: "plus", action: addProject)
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "")?", isPresented: .init(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible
        ) {
            Button("Delete Cut List", role: .destructive) {
                if let project = pendingDelete {
                    if selection == project { selection = nil }
                    context.delete(project)
                }
                pendingDelete = nil
            }
        } message: {
            Text("This removes it from all your devices.")
        }
    }

    private var sortMenu: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Sort By", selection: Binding(get: { sort }, set: { newValue in
                if newValue == sort {
                    ascending.toggle()
                } else {
                    sort = newValue
                    ascending = newValue.defaultAscending
                }
            })) {
                ForEach(ProjectSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            Picker("Order", selection: $ascending) {
                Text(sort == .name ? "A to Z" : sort == .parts ? "Fewest First" : "Oldest First").tag(true)
                Text(sort == .name ? "Z to A" : sort == .parts ? "Most First" : "Newest First").tag(false)
            }
            .pickerStyle(.inline)
        }
    }

    @ViewBuilder
    private func moveMenu(for project: Project) -> some View {
        Menu("Move to Project", systemImage: "folder") {
            Picker("Project", selection: Binding(get: { project.folder }, set: { newValue in
                project.folder = newValue
                project.touch()
            })) {
                Text("None").tag(Folder?.none)
                ForEach(folders) { folder in
                    Text(folder.name).tag(Optional(folder))
                }
            }
        }
    }

    private func addProject() {
        let project = Project(name: String(localized: "New Cut List"), kerf: defaultKerf, edgeTrim: defaultEdgeTrim)
        context.insert(project)
        project.folder = filter.folder
        let thickness = unit.format(defaultSheetThickness, includeSymbol: true)
        let stock = StockSheet(name: String(localized: "Plywood \(thickness)"), length: defaultSheetLength,
                               width: defaultSheetWidth, thickness: defaultSheetThickness)
        context.insert(stock)
        stock.project = project
        selection = project
    }
}

private struct ProjectRow: View {
    let project: Project
    let sort: ProjectSort
    let showFolder: Bool
    @Environment(\.lengthUnit) private var unit

    var body: some View {
        HStack(spacing: 12) {
            ProjectThumbnail(project: project)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name.isEmpty ? String(localized: "Untitled") : project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let parts = project.totalPartCount
        let partsText = String(localized: "\(parts) parts")
        let date = sort == .created ? project.createdAt : project.updatedAt
        let base = "\(partsText) · \(date.formatted(.relative(presentation: .named)))"
        if showFolder, let folder = project.folder, !folder.name.isEmpty {
            return "\(folder.name) · \(base)"
        }
        return base
    }
}

/// A small coloured mosaic of the project's parts.
private struct ProjectThumbnail: View {
    let project: Project

    var body: some View {
        let parts = Array(project.sortedParts.prefix(4))
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(red: 0.93, green: 0.87, blue: 0.76))
            .overlay {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        tile(parts, 0)
                        tile(parts, 1)
                    }
                    GridRow {
                        tile(parts, 2)
                        tile(parts, 3)
                    }
                }
                .padding(5)
            }
    }

    @ViewBuilder
    private func tile(_ parts: [Part], _ i: Int) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(i < parts.count ? Color(uiColor: SheetDrawing.color(i)) : Color.black.opacity(0.06))
    }
}
