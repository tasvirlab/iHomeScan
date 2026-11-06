import SwiftUI
import SwiftData

/// Creates a project with a name and optional description, then opens it.
struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var details = ""
    @State private var triedToSave = false
    @FocusState private var nameFocused: Bool

    private var nameIsEmpty: Bool { name.nilIfBlank == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormField(
                        title: settings.t("project.field.name"),
                        text: $name,
                        prompt: settings.t("project.field.namePrompt"),
                        hasError: triedToSave && nameIsEmpty
                    )
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(create)

                    FormField(
                        title: settings.t("project.field.description"),
                        text: $details,
                        prompt: settings.t("common.optional"),
                        axis: .vertical
                    )

                    Text(settings.t("project.new.note"))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(Spacing.titleEdge)
            }
            .background(Palette.background)
            .navigationTitle(settings.t("projects.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("common.create"), action: create)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accentText)
        .presentationDetents([.medium, .large])
        .onAppear { nameFocused = true }
    }

    private func create() {
        triedToSave = true
        guard !nameIsEmpty else { return }
        do {
            let project = try ProjectRepository(context: context, files: files).create(name: name, description: details)
            dismiss()
            model.selectedTab = .projects
            model.open(project)
        } catch {
            model.showError(error)
        }
    }
}
