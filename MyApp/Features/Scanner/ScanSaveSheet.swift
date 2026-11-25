import SwiftUI
import SwiftData

struct ScanSaveSheet: View {
    let output: RoomScanOutput
    let scannerContext: ScannerContext
    let onSaved: (SavedScanAssociation) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.fileStorage) private var files

    var body: some View {
        ScanDestinationSheet(scannerContext: scannerContext) { request in
            let result = try ScanPersistenceService(context: modelContext, files: files)
                .save(output: output, request: request)
            onSaved(result)
        }
    }
}

struct ScanDestinationSheet: View {
    let scannerContext: ScannerContext
    var isPhotoDraft = false
    var onSaveWithoutLocation: (() throws -> Void)? = nil
    let onSave: (ScanSaveRequest) throws -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var projectChoice: ProjectChoice = .new
    @State private var projectName = ""
    @State private var selectedProjectID: UUID?
    @State private var floorChoice: FloorChoice = .existing
    @State private var selectedFloorID: UUID?
    @State private var roomChoice: RoomChoice = .new
    @State private var selectedRoomID: UUID?
    @State private var roomName = ""
    @State private var isSaving = false
    @State private var errorKey: String?
    @State private var didInitialize = false

    private var projects: [Project] { allProjects.filter { !$0.isSample } }
    private var selectedProject: Project? { projects.first { $0.id == selectedProjectID } }
    private var floors: [Floor] { selectedProject?.sortedFloors ?? [] }
    private var selectedFloor: Floor? { floors.first { $0.id == selectedFloorID } }
    private var rooms: [Room] { selectedFloor?.sortedRooms ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: isPhotoDraft ? 21 : 24) {
                    ScanSaveProjectSection(
                        projects: projects,
                        choice: editing($projectChoice, projectChoiceDidChange),
                        projectName: $projectName,
                        selectedProjectID: editing($selectedProjectID, projectDidChange)
                    )
                    ScanSaveFloorSection(
                        isNewProject: projectChoice == .new,
                        floors: floors,
                        choice: editing($floorChoice, floorChoiceDidChange),
                        selectedFloorID: editing($selectedFloorID, floorDidChange)
                    )
                    ScanSaveRoomSection(
                        rooms: rooms,
                        choice: editing($roomChoice, roomChoiceDidChange),
                        selectedRoomID: $selectedRoomID,
                        roomName: $roomName
                    )
                    if isPhotoDraft && (projectChoice == .new || floorChoice == .new || roomChoice == .new) {
                        Text(settings.t("photoscan.location.pending"))
                            .font(Typography.meta)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let onSaveWithoutLocation {
                        Button(settings.t("photoscan.location.later")) { performSave(onSaveWithoutLocation) }
                            .font(Typography.control)
                            .frame(minHeight: 44, alignment: .leading)
                            .disabled(isSaving)
                            .accessibilityIdentifier("photoscan.location.later")
                    }
                    if let errorKey { ScanSaveError(message: settings.t(errorKey)) }
                }
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.top, 20)
                .padding(.bottom, 112)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(settings.t(isPhotoDraft ? "photoscan.save" : "scan.save.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("common.cancel")) { dismiss() }.disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ScanSaveActionBar(isSaving: isSaving, isEnabled: canSave,
                                  titleKey: isPhotoDraft ? "photoscan.save" : "scan.save.saveAndView", action: save)
                    .accessibilityIdentifier(isPhotoDraft ? "photoscan.destination.save" : "scan.destination.save")
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: initialize)
        }
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        let hasProject = projectChoice == .new ? projectName.nilIfBlank != nil : selectedProject != nil
        let hasFloor = projectChoice == .new || floorChoice == .new || selectedFloor != nil
        let hasRoom = roomChoice == .new ? roomName.nilIfBlank != nil : selectedRoomID != nil
        return hasProject && hasFloor && hasRoom
    }

    private func initialize() {
        guard !didInitialize else { return }
        didInitialize = true
        let date = Date.now.formatted(.dateTime.day().month(.abbreviated).year().locale(settings.locale))
        projectName = settings.t("scan.save.defaultProjectName", date)
        roomName = settings.t("scan.save.defaultRoomName", 1)

        if let id = scannerContext.projectID, projects.contains(where: { $0.id == id }) {
            projectChoice = .existing
            selectedProjectID = id
        } else if projects.isEmpty {
            projectChoice = .new
        } else {
            projectChoice = .existing
            selectedProjectID = projects.first?.id
        }
        projectDidChange()
    }

    private func editing<Value: Equatable>(_ value: Binding<Value>, _ update: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { value.wrappedValue }, set: { next in
            guard next != value.wrappedValue else { return }
            value.wrappedValue = next
            update()
        })
    }

    private func projectChoiceDidChange() {
        guard didInitialize else { return }
        if projectChoice == .existing {
            selectedProjectID = selectedProjectID ?? projects.first?.id
            projectDidChange()
        } else {
            roomChoice = .new
            selectedRoomID = nil
            refreshSuggestedRoomName(existingNames: [])
        }
    }

    private func projectDidChange() {
        guard projectChoice == .existing else { return }
        if let id = scannerContext.floorID, floors.contains(where: { $0.id == id }) {
            selectedFloorID = id
        } else if !floors.contains(where: { $0.id == selectedFloorID }) {
            selectedFloorID = floors.first?.id
        }
        floorChoice = floors.isEmpty ? .new : .existing
        floorDidChange()
    }

    private func floorChoiceDidChange() {
        if floorChoice == .new {
            roomChoice = .new
            selectedRoomID = nil
            refreshSuggestedRoomName(existingNames: [])
        } else { floorDidChange() }
    }

    private func floorDidChange() {
        roomChoice = .new
        selectedRoomID = nil
        refreshSuggestedRoomName(existingNames: rooms.map(\.name))
    }

    private func roomChoiceDidChange() {
        if roomChoice == .existing {
            selectedRoomID = selectedRoomID ?? rooms.first?.id
        } else {
            selectedRoomID = nil
            refreshSuggestedRoomName(existingNames: rooms.map(\.name))
        }
    }

    private func refreshSuggestedRoomName(existingNames: [String]) {
        roomName = ScanSaveDefaults.nextRoomName(existingNames: existingNames) {
            settings.t("scan.save.defaultRoomName", $0)
        }
    }

    private func save() {
        guard canSave, let request = makeRequest() else { return }
        performSave { try onSave(request) }
    }

    private func performSave(_ action: @escaping () throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        errorKey = nil
        Task { @MainActor in
            await Task.yield()
            do {
                try action()
                isSaving = false
                dismiss()
            } catch ScanPersistenceError.duplicateScan {
                isSaving = false
                errorKey = "scan.save.error.duplicate"
            } catch {
                isSaving = false
                errorKey = isPhotoDraft ? "photoscan.saveError" : "scan.save.error.generic"
            }
        }
    }

    private func makeRequest() -> ScanSaveRequest? {
        let project: ScanProjectDestination
        if projectChoice == .new {
            project = .new(name: projectName)
        } else {
            guard let selectedProjectID else { return nil }
            project = .existing(projectID: selectedProjectID)
        }
        let floor: ScanFloorDestination
        if projectChoice == .new { floor = .automatic }
        else if floorChoice == .new { floor = .new }
        else {
            guard let selectedFloorID else { return nil }
            floor = .existing(floorID: selectedFloorID)
        }
        let room: ScanRoomDestination
        if roomChoice == .new {
            room = .new(name: roomName)
        } else {
            guard let selectedRoomID else { return nil }
            room = .existing(roomID: selectedRoomID)
        }
        return ScanSaveRequest(project: project, floor: floor, room: room)
    }
}

private enum ProjectChoice: String, CaseIterable, Identifiable { case new, existing; var id: String { rawValue } }
private enum FloorChoice: String, CaseIterable, Identifiable { case existing, new; var id: String { rawValue } }
private enum RoomChoice: String, CaseIterable, Identifiable { case new, existing; var id: String { rawValue } }

private struct ScanSaveProjectSection: View {
    let projects: [Project]
    @Binding var choice: ProjectChoice
    @Binding var projectName: String
    @Binding var selectedProjectID: UUID?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScanSaveSection(title: settings.t("scan.save.project"), number: 1) {
            ScanChoiceControl(
                firstTitle: settings.t("scan.save.createProject"),
                secondTitle: settings.t("scan.save.existingProject"),
                selectsFirst: choice == .new,
                secondDisabled: projects.isEmpty,
                onFirst: { choice = .new }, onSecond: { choice = .existing }
            )
            if choice == .new {
                FormField(title: settings.t("project.field.name"), text: $projectName,
                          prompt: settings.t("project.field.namePrompt"), hasError: false)
            } else {
                ScanEntityPicker(title: settings.t("scan.save.project"), selection: $selectedProjectID,
                                 values: projects.map { ($0.id, $0.name) })
            }
        }
    }
}

private struct ScanSaveFloorSection: View {
    let isNewProject: Bool
    let floors: [Floor]
    @Binding var choice: FloorChoice
    @Binding var selectedFloorID: UUID?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScanSaveSection(title: settings.t("scan.save.floor"), number: 2) {
            if isNewProject {
                ScanAutomaticValue(title: settings.t("floor.defaultName", 1),
                                   subtitle: settings.t("scan.save.floorAutomatic"))
            } else {
                ScanChoiceControl(
                    firstTitle: settings.t("scan.save.existingFloor"),
                    secondTitle: settings.t("scan.save.createFloor"),
                    selectsFirst: choice == .existing, secondDisabled: false,
                    onFirst: { choice = .existing }, onSecond: { choice = .new }
                )
                if choice == .existing {
                    ScanEntityPicker(title: settings.t("scan.save.floor"), selection: $selectedFloorID,
                                     values: floors.map { ($0.id, settings.floorName($0)) })
                } else {
                    ScanAutomaticValue(
                        title: settings.t("floor.defaultName", (floors.map(\.level).max() ?? 0) + 1),
                        subtitle: settings.t("scan.save.floorAutomatic")
                    )
                }
            }
        }
    }
}

private struct ScanSaveRoomSection: View {
    let rooms: [Room]
    @Binding var choice: RoomChoice
    @Binding var selectedRoomID: UUID?
    @Binding var roomName: String
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScanSaveSection(title: settings.t("scan.save.room"), number: 3) {
            ScanChoiceControl(
                firstTitle: settings.t("scan.save.newRoom"), secondTitle: settings.t("scan.save.existingRoom"),
                selectsFirst: choice == .new, secondDisabled: rooms.isEmpty,
                onFirst: { choice = .new }, onSecond: { choice = .existing }
            )
            if choice == .new {
                FormField(title: settings.t("room.field.name"), text: $roomName,
                          prompt: settings.t("room.field.namePrompt"), hasError: false)
            } else {
                ScanEntityPicker(title: settings.t("scan.save.room"), selection: $selectedRoomID,
                                 values: rooms.map { ($0.id, $0.name) })
            }
        }
    }
}

private struct ScanSaveSection<Content: View>: View {
    let title: String
    let number: Int
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(number.formatted()).font(.caption.weight(.bold)).foregroundStyle(Palette.accentText)
                    .frame(width: 28, height: 28).background(Palette.accentTint, in: .circle)
                Text(title).font(Typography.rowTitle).foregroundStyle(Palette.ink)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScanChoiceControl: View {
    let firstTitle: String
    let secondTitle: String
    let selectsFirst: Bool
    let secondDisabled: Bool
    let onFirst: () -> Void
    let onSecond: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            choiceButton(firstTitle, selected: selectsFirst, action: onFirst)
            choiceButton(secondTitle, selected: !selectsFirst, disabled: secondDisabled, action: onSecond)
        }
        .padding(4).background(Palette.surface, in: .rect(cornerRadius: Radius.small))
    }
    private func choiceButton(_ title: String, selected: Bool, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Typography.meta.weight(.semibold))
                .foregroundStyle(selected ? Palette.accentText : Palette.inkSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Palette.accentTint : .clear,
                            in: .rect(cornerRadius: Radius.small - 2))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ScanEntityPicker: View {
    let title: String
    @Binding var selection: UUID?
    let values: [(UUID, String)]
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(values, id: \.0) { id, name in Text(name).tag(UUID?.some(id)) }
        }
        .pickerStyle(.menu).tint(Palette.accentText).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
    }
}

private struct ScanAutomaticValue: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.rowTitle).foregroundStyle(Palette.ink)
                Text(subtitle).font(Typography.meta).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
    }
}

private struct ScanSaveError: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle").font(Typography.meta)
            .foregroundStyle(Palette.error).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentTint, in: .rect(cornerRadius: Radius.small))
    }
}

private struct ScanSaveActionBar: View {
    let isSaving: Bool
    let isEnabled: Bool
    let titleKey: String
    let action: () -> Void
    @Environment(AppSettings.self) private var settings
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isSaving { ProgressView().tint(.white) }
                Text(settings.t(titleKey)).font(.headline)
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.accent, in: .rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain).disabled(!isEnabled).opacity(isEnabled ? 1 : 0.55)
        .padding(.horizontal, Spacing.screenEdge).padding(.vertical, 12).background(.ultraThinMaterial)
    }
}
