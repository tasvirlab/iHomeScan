import SwiftUI
import SwiftData

struct ScanSaveSheet: View {
    let output: RoomScanOutput
    let scannerContext: ScannerContext
    let onSaved: (SavedScanAssociation) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fileStorage) private var files
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var selectedProjectID: UUID?
    @State private var selectedFloorID: UUID?
    @State private var selectedRoomID: UUID?
    @State private var roomName = ""
    @State private var isSaving = false
    @State private var errorKey: String?
    @State private var didInitialize = false

    private var projects: [Project] {
        allProjects.filter { !$0.isSample }
    }

    private var selectedProject: Project? {
        projects.first { $0.id == selectedProjectID }
    }

    private var floors: [Floor] {
        selectedProject?.sortedFloors ?? []
    }

    private var selectedFloor: Floor? {
        floors.first { $0.id == selectedFloorID }
    }

    private var rooms: [Room] {
        selectedFloor?.sortedRooms ?? []
    }

    private var selectedRoom: Room? {
        rooms.first { $0.id == selectedRoomID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScanSaveDestinationSection(
                        projects: projects,
                        floors: floors,
                        selectedProjectID: $selectedProjectID,
                        selectedFloorID: $selectedFloorID
                    )

                    ScanSaveRoomSection(
                        rooms: rooms,
                        selectedRoomID: $selectedRoomID,
                        roomName: $roomName
                    )

                    if let errorKey {
                        Label(settings.t(errorKey), systemImage: "exclamationmark.triangle")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.error)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.accentTint, in: .rect(cornerRadius: Radius.small))
                    }

                    if projects.isEmpty {
                        Text(settings.t("scan.save.noProjects"))
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(16)
                            .cardSurface()
                    }
                }
                .padding(Spacing.screenEdge)
            }
            .background(Palette.background)
            .navigationTitle(settings.t("scan.save.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("common.cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(settings.t("common.save"))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear(perform: initializeSelection)
            .onChange(of: selectedProjectID) { _, _ in projectDidChange() }
            .onChange(of: selectedFloorID) { _, _ in floorDidChange() }
            .onChange(of: selectedRoomID) { _, _ in roomDidChange() }
        }
    }

    private var canSave: Bool {
        selectedProject != nil && selectedFloor != nil && roomName.nilIfBlank != nil
    }

    private func initializeSelection() {
        guard !didInitialize else { return }
        didInitialize = true
        selectedProjectID = scannerContext.projectID.flatMap { id in
            projects.contains { $0.id == id } ? id : nil
        } ?? projects.first?.id

        if let contextFloorID = scannerContext.floorID,
           floors.contains(where: { $0.id == contextFloorID }) {
            selectedFloorID = contextFloorID
        } else {
            selectedFloorID = floors.first?.id
        }
        floorDidChange()
    }

    private func projectDidChange() {
        guard didInitialize else { return }
        if !floors.contains(where: { $0.id == selectedFloorID }) {
            selectedFloorID = floors.first?.id
        }
        floorDidChange()
    }

    private func floorDidChange() {
        if !rooms.contains(where: { $0.id == selectedRoomID }) {
            selectedRoomID = nil
            roomName = ""
        }
    }

    private func roomDidChange() {
        if let selectedRoom {
            roomName = selectedRoom.name
        } else if selectedRoomID == nil {
            roomName = ""
        }
    }

    private func save() {
        guard let project = selectedProject, let floor = selectedFloor else { return }
        isSaving = true
        errorKey = nil

        Task { @MainActor in
            await Task.yield()
            do {
                let result = try ScanPersistenceService(
                    context: modelContext,
                    files: files
                ).save(
                    output: output,
                    project: project,
                    floor: floor,
                    existingRoom: selectedRoom,
                    roomName: roomName
                )
                isSaving = false
                onSaved(result)
                dismiss()
            } catch ScanPersistenceError.duplicateScan {
                isSaving = false
                errorKey = "scan.save.error.duplicate"
            } catch {
                isSaving = false
                errorKey = "scan.save.error.generic"
            }
        }
    }
}

private struct ScanSaveDestinationSection: View {
    let projects: [Project]
    let floors: [Floor]
    @Binding var selectedProjectID: UUID?
    @Binding var selectedFloorID: UUID?

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("scan.save.destination"))
                .font(Typography.settingsHeader)
                .foregroundStyle(Palette.inkSecondary)

            Picker(settings.t("scan.save.project"), selection: $selectedProjectID) {
                Text(settings.t("scan.save.selectProject")).tag(UUID?.none)
                ForEach(projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }

            Picker(settings.t("scan.save.floor"), selection: $selectedFloorID) {
                Text(settings.t("scan.save.selectFloor")).tag(UUID?.none)
                ForEach(floors) { floor in
                    Text(settings.floorName(floor)).tag(UUID?.some(floor.id))
                }
            }
        }
        .padding(16)
        .cardSurface()
    }
}

private struct ScanSaveRoomSection: View {
    let rooms: [Room]
    @Binding var selectedRoomID: UUID?
    @Binding var roomName: String

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("scan.save.room"))
                .font(Typography.settingsHeader)
                .foregroundStyle(Palette.inkSecondary)

            Picker(settings.t("scan.save.room"), selection: $selectedRoomID) {
                Text(settings.t("scan.save.newRoom")).tag(UUID?.none)
                ForEach(rooms) { room in
                    Text(room.name).tag(UUID?.some(room.id))
                }
            }

            FormField(
                title: settings.t("room.field.name"),
                text: $roomName,
                prompt: settings.t("room.field.namePrompt"),
                hasError: roomName.nilIfBlank == nil
            )
        }
        .padding(16)
        .cardSurface()
    }
}
