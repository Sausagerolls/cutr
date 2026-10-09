import SwiftUI
import SwiftData

/// Lists projects (groups of cut lists) plus the All and Not in a Project views.
struct SidebarView: View {
    @Binding var filter: LibraryFilter?
    @Binding var showSettings: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.lengthUnit) private var unit
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query private var cutLists: [Project]

    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var pendingDelete: Folder?

    private enum Naming: Identifiable {
        case new
        case rename(Folder)

        var id: String {
            switch self {
            case .new: "new"
            case .rename(let folder): "rename-\(folder.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        List(selection: $filter) {
            Section {
                NavigationLink(value: LibraryFilter.all) {
                    Label("All Cut Lists", systemImage: "tray.full")
                        .badge(cutLists.count)
                }
                NavigationLink(value: LibraryFilter.ungrouped) {
                    Label("Not in a Project", systemImage: "tray")
                        .badge(cutLists.filter { $0.folder == nil }.count)
                }
            }

            Section("Projects") {
                ForEach(folders) { folder in
                    NavigationLink(value: LibraryFilter.folder(folder)) {
                        Label(folder.name.isEmpty ? String(localized: "Untitled Project") : folder.name,
                              systemImage: "folder")
                            .badge(folder.cutListCount)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { startRename(folder) }
                        ShareLink(item: CutSheetPDF(folder: folder, unit: unit),
                                  preview: SharePreview(folder.name, image: Image(systemName: "doc.richtext"))) {
                            Label("Export Project PDF", systemImage: "doc.richtext")
                        }
                        .disabled(folder.cutListCount == 0)
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = folder }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = folder }
                        Button("Rename", systemImage: "pencil") { startRename(folder) }
                            .tint(.indigo)
                    }
                }
                Button("New Project", systemImage: "folder.badge.plus", action: startNew)
            }
        }
        .navigationTitle("Cutr")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Project", systemImage: "folder.badge.plus", action: startNew)
            }
        }
        .alert(naming.map { if case .new = $0 { "New Project" } else { "Rename Project" } } ?? "",
               isPresented: .init(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name, e.g. Kitchen Renovation", text: $nameText)
            Button("Cancel", role: .cancel) { naming = nil }
            Button(naming.map { if case .new = $0 { "Create" } else { "Save" } } ?? "Save", action: commitName)
        } message: {
            Text("Projects group related cut lists together.")
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "")?", isPresented: .init(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible
        ) {
            if let folder = pendingDelete {
                Button("Delete Project Only") { delete(folder, includingCutLists: false) }
                if folder.cutListCount > 0 {
                    Button("Delete Project and \(folder.cutListCount) Cut Lists", role: .destructive) {
                        delete(folder, includingCutLists: true)
                    }
                }
            }
        } message: {
            Text("Deleting only the project keeps its cut lists under Not in a Project.")
        }
    }

    private func startNew() {
        nameText = ""
        naming = .new
    }

    private func startRename(_ folder: Folder) {
        nameText = folder.name
        naming = .rename(folder)
    }

    private func commitName() {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { naming = nil }
        guard !name.isEmpty else { return }
        switch naming {
        case .new:
            let folder = Folder(name: name)
            context.insert(folder)
            filter = .folder(folder)
        case .rename(let folder):
            folder.name = name
            folder.touch()
        case nil:
            break
        }
    }

    private func delete(_ folder: Folder, includingCutLists: Bool) {
        if filter == .folder(folder) { filter = .all }
        if includingCutLists {
            for cutList in folder.cutLists ?? [] { context.delete(cutList) }
        }
        context.delete(folder)
        pendingDelete = nil
    }
}
