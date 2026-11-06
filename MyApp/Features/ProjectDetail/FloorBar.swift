import SwiftUI
import SwiftData

/// Horizontal floor selector with add, rename and delete actions.
struct FloorBar: View {
    let project: Project
    @Binding var selectedFloorID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    @State private var renaming: Floor?
    @State private var deleting: Floor?
    @State private var newName = ""

    private var repository: RoomRepository { RoomRepository(context: context, files: files) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(project.sortedFloors) { floor in
                    chip(for: floor)
                }
                Button(action: addFloor) {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 34, height: 34)
                        .background(Palette.accentTint, in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(settings.t("floor.add"))
            }
            .padding(.horizontal, Spacing.titleEdge)
        }
        .scrollIndicators(.hidden)
        .alert(
            settings.t("floor.rename"),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(settings.t("floor.field.name"), text: $newName)
            Button(settings.t("common.cancel"), role: .cancel) { renaming = nil }
            Button(settings.t("common.save")) {
                if let floor = renaming {
                    do { try repository.renameFloor(floor, to: newName) } catch { model.showError(error) }
                }
                renaming = nil
            }
        }
        .confirmationDialog(
            settings.t("floor.delete.title"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { floor in
            Button(settings.t("floor.delete"), role: .destructive) { delete(floor) }
            Button(settings.t("common.cancel"), role: .cancel) { deleting = nil }
        } message: { floor in
            Text(settings.t("floor.delete.message", settings.floorName(floor), settings.roomCount(floor.rooms.count)))
        }
    }

    private func chip(for floor: Floor) -> some View {
        let isSelected = floor.id == selectedFloorID
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selectedFloorID = floor.id }
        } label: {
            Text(settings.floorName(floor))
                .font(Typography.control)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Palette.accentText : Palette.inkSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(isSelected ? Palette.accentTint : Palette.surface, in: .capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(settings.t("floor.rename"), systemImage: "pencil") {
                newName = settings.floorName(floor)
                renaming = floor
            }
            Button(settings.t("floor.delete"), systemImage: "trash", role: .destructive) {
                if project.floors.count > 1 { deleting = floor } else { model.showError(RepositoryError.lastFloor) }
            }
        }
    }

    private func addFloor() {
        do {
            let floor = try repository.addFloor(to: project)
            withAnimation(.snappy(duration: 0.25)) { selectedFloorID = floor.id }
        } catch {
            model.showError(error)
        }
    }

    private func delete(_ floor: Floor) {
        let wasSelected = floor.id == selectedFloorID
        do {
            try repository.deleteFloor(floor)
            if wasSelected { selectedFloorID = project.sortedFloors.first?.id }
        } catch {
            model.showError(error)
        }
        deleting = nil
    }
}
