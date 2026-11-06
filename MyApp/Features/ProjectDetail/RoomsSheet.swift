import SwiftUI
import SwiftData

/// Bottom sheet listing a floor's rooms, with add, edit (tap), and swipe-to-delete.
struct RoomsSheet: View {
    let floor: Floor
    @Binding var selectedRoomID: String?

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    private enum Destination: Hashable {
        case edit(Room)
        case create
    }

    @State private var path: [Destination] = []
    @State private var deleting: Room?

    private var rooms: [Room] { floor.sortedRooms }

    private var totalArea: Double? {
        let areas = rooms.compactMap(\.effectiveArea)
        return areas.isEmpty ? nil : areas.reduce(0, +)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if rooms.isEmpty {
                        Text(settings.t("rooms.empty"))
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .listRowBackground(Palette.card)
                    }
                    ForEach(rooms) { room in
                        Button {
                            selectedRoomID = room.geometryIdentifier
                            path.append(.edit(room))
                        } label: {
                            RoomRow(room: room, isSelected: room.geometryIdentifier != nil
                                    && room.geometryIdentifier == selectedRoomID)
                        }
                        .listRowBackground(Palette.card)
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.titleEdge, bottom: 0, trailing: Spacing.titleEdge))
                        .swipeActions(edge: .trailing) {
                            Button(settings.t("common.delete"), systemImage: "trash", role: .destructive) {
                                deleting = room
                            }
                            .tint(Palette.error)
                            Button(settings.t("common.edit"), systemImage: "pencil") {
                                path.append(.edit(room))
                            }
                            .tint(Palette.inkTertiary)
                        }
                    }
                } header: {
                    header
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(Palette.line)
            .background(Palette.card)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(.create) } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(settings.t("room.add"))
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .edit(let room): RoomEditorView(mode: .edit(room))
                case .create: RoomEditorView(mode: .create(floor))
                }
            }
        }
        .tint(Palette.accentText)
        .confirmationDialog(
            settings.t("room.delete.title"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { room in
            Button(settings.t("room.delete"), role: .destructive) {
                do { try RoomRepository(context: context, files: files).deleteRoom(room) } catch { model.showError(error) }
                deleting = nil
            }
            Button(settings.t("common.cancel"), role: .cancel) { deleting = nil }
        } message: { room in
            Text(room.name)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.card)
        .presentationCornerRadius(28)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t("project.rooms"))
                    .font(Typography.sheetTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(settings.floorName(floor))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            if let totalArea {
                Text(settings.area(totalArea))
                    .font(.callout.monospaced().weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .textCase(nil)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.titleEdge, bottom: 0, trailing: Spacing.titleEdge))
    }
}

private struct RoomRow: View {
    let room: Room
    let isSelected: Bool
    @Environment(AppSettings.self) private var settings

    private var subtitle: String {
        var parts: [String] = []
        if let type = room.type { parts.append(settings.t(type.titleKey)) }
        if let dims = settings.dimensions(width: room.width, length: room.length) {
            parts.append(dims)
        } else if !room.isMeasured {
            parts.append(settings.t("room.notScanned"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.name)
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typography.measurement)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            if let area = room.effectiveArea {
                Text(settings.area(area))
                    .font(Typography.measurementEmphasis)
                    .foregroundStyle(isSelected ? Palette.accentText : Palette.ink)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
