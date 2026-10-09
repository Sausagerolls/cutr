import Foundation
import SwiftData

/// A group of cut lists, shown to users as a "Project" (for example "Kitchen
/// Renovation" holding the base units, wall units and worktop cut lists).
/// The cut list model keeps its original `Project` name so existing stores
/// and iCloud data stay compatible.
@Model
final class Folder {
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Deleting a folder keeps its cut lists; they become ungrouped.
    @Relationship(deleteRule: .nullify, inverse: \Project.folder)
    var cutLists: [Project]? = []

    init(name: String) {
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }

    var sortedCutLists: [Project] {
        (cutLists ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var cutListCount: Int { cutLists?.count ?? 0 }

    func touch() {
        updatedAt = .now
    }
}
