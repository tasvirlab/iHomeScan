import SwiftUI
import SwiftData

/// Rename alert and delete confirmation for projects, shared by every screen that lists projects.
struct ProjectActionsModifier: ViewModifier {
    @Binding var renaming: Project?
    @Binding var deleting: Project?
    var onDeleted: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    @State private var newName = ""

    private var repository: ProjectRepository { ProjectRepository(context: context, files: files) }

    func body(content: Content) -> some View {
        content
            .alert(
                settings.t("project.rename"),
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField(settings.t("project.field.name"), text: $newName)
                Button(settings.t("common.cancel"), role: .cancel) { renaming = nil }
                Button(settings.t("common.save")) {
                    if let project = renaming {
                        do { try repository.rename(project, to: newName) } catch { model.showError(error) }
                    }
                    renaming = nil
                }
            }
            .onChange(of: renaming) { _, project in
                if let project { newName = project.name }
            }
            .confirmationDialog(
                settings.t("project.delete.title"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { project in
                Button(settings.t("project.delete"), role: .destructive) {
                    do {
                        try repository.delete(project)
                        onDeleted()
                        model.showToast("toast.projectDeleted")
                    } catch {
                        model.showError(error)
                    }
                    deleting = nil
                }
                Button(settings.t("common.cancel"), role: .cancel) { deleting = nil }
            } message: { project in
                Text(settings.t("project.delete.message", project.name))
            }
    }
}

extension View {
    func projectActions(renaming: Binding<Project?>, deleting: Binding<Project?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(ProjectActionsModifier(renaming: renaming, deleting: deleting, onDeleted: onDeleted))
    }
}

/// Context menu items for a project card or row.
struct ProjectContextMenu: View {
    let project: Project
    @Binding var renaming: Project?
    @Binding var deleting: Project?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Button(settings.t("project.rename"), systemImage: "pencil") { renaming = project }
        Button(settings.t("project.delete"), systemImage: "trash", role: .destructive) { deleting = project }
    }
}

/// Shared text for project metadata lines.
enum ProjectMeta {
    /// "59.3 m² · 5 rooms · Today" — the area is omitted until rooms have measurements.
    static func list(_ project: Project, settings: AppSettings) -> String {
        var parts: [String] = []
        if let area = project.totalArea { parts.append(settings.area(area)) }
        parts.append(settings.roomCount(project.allRooms.count))
        parts.append(settings.shortDate(project.updatedAt))
        return parts.joined(separator: " · ")
    }

    /// "59.3 m² · Today", or "Not scanned · Today" for projects without measurements.
    static func card(_ project: Project, settings: AppSettings) -> String {
        let lead = project.totalArea.map(settings.area) ?? settings.t("projects.notScanned")
        return [lead, settings.shortDate(project.updatedAt)].joined(separator: " · ")
    }
}
