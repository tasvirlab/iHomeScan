import SwiftUI
import SwiftData

/// Creates or edits a room: name, type and optional measurements (entered in the selected unit,
/// stored in meters). Measurements stay empty until the user enters them or a scan provides them.
struct RoomEditorView: View {
    enum Mode {
        case create(Floor)
        case edit(Room)
    }

    let mode: Mode

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: RoomType?
    @State private var width = ""
    @State private var length = ""
    @State private var height = ""
    @State private var area = ""
    @State private var invalidFields: Set<String> = []
    @State private var triedToSave = false
    @State private var confirmsDelete = false
    @State private var loaded = false

    private var repository: RoomRepository { RoomRepository(context: context, files: files) }

    private var existingRoom: Room? {
        if case .edit(let room) = mode { return room }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FormField(
                    title: settings.t("room.field.name"),
                    text: $name,
                    prompt: settings.t("room.field.namePrompt"),
                    hasError: triedToSave && name.nilIfBlank == nil
                )

                typePicker

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: settings.t("room.measurements"), font: Typography.settingsHeader)
                        .padding(.horizontal, -Spacing.titleEdge)
                    if let room = existingRoom, !room.isMeasured {
                        Text(settings.t("room.notScanned.body"))
                            .font(Typography.meta)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    HStack(spacing: 12) {
                        measurementField("width", key: "room.field.width", text: $width, unit: settings.lengthUnitSymbol)
                        measurementField("length", key: "room.field.length", text: $length, unit: settings.lengthUnitSymbol)
                    }
                    HStack(spacing: 12) {
                        measurementField("height", key: "room.field.height", text: $height, unit: settings.lengthUnitSymbol)
                        measurementField("area", key: "room.field.area", text: $area, unit: settings.t("unit.sqm"))
                    }
                    Text(settings.t("room.measurements.note"))
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(16)
                .cardSurface()

                if existingRoom != nil {
                    ActionButton(title: settings.t("room.delete"), systemImage: "trash", kind: .destructive) {
                        confirmsDelete = true
                    }
                    .padding(.top, 8)
                }
            }
            .padding(Spacing.titleEdge)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.card)
        .navigationTitle(settings.t(existingRoom == nil ? "room.add" : "room.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(settings.t("common.save"), action: save)
                    .fontWeight(.semibold)
            }
        }
        .confirmationDialog(settings.t("room.delete.title"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(settings.t("room.delete"), role: .destructive, action: delete)
            Button(settings.t("common.cancel"), role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("room.field.type"))
                .font(Typography.settingsHeader)
                .foregroundStyle(Palette.inkSecondary)
            Menu {
                Picker(settings.t("room.field.type"), selection: $type) {
                    Text(settings.t("roomType.none")).tag(RoomType?.none)
                    ForEach(RoomType.allCases) { type in
                        Text(settings.t(type.titleKey)).tag(RoomType?.some(type))
                    }
                }
            } label: {
                HStack {
                    Text(type.map { settings.t($0.titleKey) } ?? settings.t("roomType.none"))
                        .foregroundStyle(type == nil ? Palette.inkTertiary : Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
            }
        }
    }

    private func measurementField(_ id: String, key: String, text: Binding<String>, unit: String) -> some View {
        FormField(title: settings.t(key), text: text, prompt: "—", unit: unit,
                  isNumeric: true, hasError: invalidFields.contains(id))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let room = existingRoom else { return }
        name = room.name
        type = room.type
        width = settings.editableLength(room.width)
        length = settings.editableLength(room.length)
        height = settings.editableLength(room.height)
        area = settings.editableArea(room.area)
    }

    private func save() {
        triedToSave = true
        var invalid: Set<String> = []
        func parse(_ id: String, _ result: Result<Double?, RepositoryError>) -> Double? {
            switch result {
            case .success(let value): return value
            case .failure: invalid.insert(id); return nil
            }
        }
        let draft = RoomDraft(
            name: name,
            type: type,
            width: parse("width", settings.parseLength(width)),
            length: parse("length", settings.parseLength(length)),
            height: parse("height", settings.parseLength(height)),
            area: parse("area", settings.parseArea(area))
        )
        invalidFields = invalid
        guard invalid.isEmpty else {
            model.showError(RepositoryError.invalidMeasurement)
            return
        }
        guard draft.name.nilIfBlank != nil else { return }
        do {
            switch mode {
            case .create(let floor): try repository.addRoom(to: floor, draft: draft)
            case .edit(let room): try repository.updateRoom(room, with: draft)
            }
            dismiss()
        } catch {
            model.showError(error)
        }
    }

    private func delete() {
        guard let room = existingRoom else { return }
        do {
            try repository.deleteRoom(room)
            dismiss()
        } catch {
            model.showError(error)
        }
    }
}
