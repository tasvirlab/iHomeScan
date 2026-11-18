import SwiftUI
import SwiftData

/// Resolves a project by ID so the screen stays valid while data changes underneath it.
struct ProjectDetailScreen: View {
    @Query private var results: [Project]

    init(projectID: UUID) {
        _results = Query(filter: #Predicate<Project> { $0.id == projectID })
    }

    var body: some View {
        if let project = results.first {
            ProjectDetailView(project: project)
        } else {
            MissingProjectView()
        }
    }
}

struct ProjectDetailView: View {
    let project: Project

    @Query private var scans: [SavedScan]

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.fileStorage) private var files
    @Environment(\.modelContext) private var context

    private enum Mode: Hashable { case plan2D, model3D }

    @State private var mode: Mode = .plan2D
    @State private var selectedFloorID: UUID?
    @State private var selectedRoomID: String?
    @State private var plan: FloorPlan?
    @State private var planError: Error?
    @State private var showsRooms = false
    @State private var renaming: Project?
    @State private var deleting: Project?
    @State private var precisionSession: GeometryRevisionSession?
    @State private var selectedWallID: UUID?
    @State private var selectedOpeningID: UUID?
    @State private var openingDraft: OpeningMeasurementDraft?
    @State private var openingPreview: OpeningEditPreview?
    @State private var showsOpeningPanel = false
    @State private var showsMeasurementPanel = false
    @State private var measurementInput = ""
    @State private var laserVerified = false
    @State private var selectedAnchor: WallLengthAnchorStrategy?
    @State private var requiresAnchorChoice = false
    @State private var precisionConflict = false
    @State private var isSavingMeasurement = false
    @State private var precisionSaveError = false
    @State private var precisionLoadError = false
    @State private var showsSavedConfirmation = false
    @State private var selectedColumnID: UUID?
    @State private var selectedBeamID: UUID?
    @State private var structuralDraft = StructuralCreationDraft()
    @State private var showsStructuralChooser = false
    @State private var showsStructuralDimensions = false
    @State private var structuralErrorKey: String?
    @State private var structuralPropertiesDraft: StructuralPropertiesDraft?
    @State private var structuralPropertiesPreview: StructuralPropertiesPreview?
    @State private var showsStructuralProperties = false
    @State private var structuralPropertiesErrorKey: String?
    @State private var structuralDragPreview: ParametricFloorPlan?

    init(project: Project) {
        self.project = project
        let projectID = project.id
        _scans = Query(
            filter: #Predicate<SavedScan> { $0.projectID == projectID },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    private var selectedFloor: Floor? {
        project.floors.first { $0.id == selectedFloorID } ?? project.sortedFloors.first
    }

    private var selectedScan: SavedScan? {
        guard let floorID = selectedFloor?.id else { return nil }
        return scans.first { $0.floorID == floorID }
    }

    private var metaText: String {
        var parts: [String] = []
        if let area = authoritativeProjectArea { parts.append(settings.area(area)) }
        parts.append(settings.roomCount(project.allRooms.count))
        if let height = project.ceilingHeight {
            parts.append(settings.t("project.ceiling", settings.ceilingHeight(height)))
        }
        return parts.joined(separator: " · ")
    }

    private var authoritativeProjectArea: Double? {
        PrecisionAreaPolicy.projectTotal(
            rooms: project.allRooms,
            replacingRoomID: selectedScan?.roomID,
            with: PrecisionAreaPolicy.authoritativeArea(
                precisionPlan: precisionSession?.displayedPlan,
                storedArea: selectedFloor?.rooms.first(where: { $0.id == selectedScan?.roomID })?.effectiveArea
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock

            FloorBar(project: project, selectedFloorID: $selectedFloorID)
                .padding(.bottom, 12)

            if plan != nil {
                SegmentedPill(
                    options: [
                        .init(value: .plan2D, title: settings.t("project.plan2d")),
                        .init(value: .model3D, title: settings.t("project.model3d")),
                    ],
                    selection: $mode,
                    height: 32
                )
                .padding(.horizontal, Spacing.titleEdge)
                .padding(.bottom, 12)
            }

            planArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: Radius.large))
                .overlay(RoundedRectangle(cornerRadius: Radius.large).strokeBorder(Palette.line, lineWidth: 0.5))
                .padding(.horizontal, 12)

            actionBar
        }
        .background(Palette.background)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .loadsFloorPlan(selectedFloor?.planAsset, into: $plan, error: $planError)
        .onAppear {
            if selectedFloorID == nil { selectedFloorID = project.sortedFloors.first?.id }
        }
        .onChange(of: selectedFloorID) {
            selectedRoomID = nil
            closeMeasurementPanel()
            closeOpeningPanel()
            cancelStructuralCreation()
            precisionSession = nil
            mode = .plan2D
        }
        .onChange(of: plan?.roomPlanMetadata?.roomIdentifier) {
            loadPrecisionDocumentIfAvailable()
        }
        .task(id: selectedScan?.id) {
            loadPrecisionDocumentIfAvailable()
        }
        .task(id: PrecisionInlinePreviewRequest(input: measurementInput, wallID: selectedWallID,
                                                anchor: selectedAnchor, laserVerified: laserVerified)) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            updatePrecisionPreview()
        }
        .task(id: openingDraft) {
            guard let openingDraft, let plan = precisionSession?.document.currentPlan else {
                openingPreview = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            openingPreview = OpeningEditEngine.preview(draft: openingDraft, in: plan)
        }
        .sheet(isPresented: $showsMeasurementPanel, onDismiss: closeMeasurementPanel) {
            InlinePrecisionMeasurementSheet(
                    currentMillimeters: currentMillimeters ?? measurementInput,
                    currentLabelKey: currentMeasurementLabelKey,
                    input: $measurementInput,
                    laserVerified: $laserVerified,
                    anchor: $selectedAnchor,
                    requiresAnchorChoice: requiresAnchorChoice,
                    hasValidPreview: precisionSession?.preview != nil,
                    hasConflict: precisionConflict,
                    isSaving: isSavingMeasurement,
                    onConfirm: confirmMeasurement,
                    onClose: closeMeasurementPanel
                )
                .presentationDetents([.height(460), .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled(isSavingMeasurement)
        }
        .sheet(isPresented: $showsOpeningPanel, onDismiss: closeOpeningPanel) {
            if let selectedOpeningID,
               let opening = precisionSession?.document.currentPlan.openings.first(where: { $0.id == selectedOpeningID }),
               let draft = openingDraft {
                InlineOpeningMeasurementSheet(
                    openingKind: opening.kind,
                    ordinal: openingOrdinal(opening),
                    draft: Binding(get: { openingDraft ?? draft }, set: { openingDraft = $0 }),
                    preview: openingPreview,
                    isSaving: isSavingMeasurement,
                    onConfirm: confirmOpeningMeasurement,
                    onClose: closeOpeningPanel
                )
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isSavingMeasurement)
            }
        }
        .sheet(isPresented: $showsStructuralChooser) {
            StructuralCreationSheet(
                draft: $structuralDraft,
                showsChooser: true,
                errorKey: nil,
                onBeginColumn: beginColumnCreation,
                onBeginBeam: beginBeamCreation,
                onConfirm: {},
                onClose: cancelStructuralCreation
            )
        }
        .sheet(isPresented: $showsStructuralDimensions, onDismiss: structuralDimensionsDismissed) {
            StructuralCreationSheet(
                draft: $structuralDraft,
                showsChooser: false,
                errorKey: structuralErrorKey,
                onBeginColumn: { _ in },
                onBeginBeam: {},
                onConfirm: confirmStructuralCreation,
                onClose: cancelStructuralCreation
            )
        }
        .sheet(isPresented: $showsStructuralProperties, onDismiss: closeStructuralProperties) {
            structuralPropertiesSheetContent
        }
        .alert(settings.t("precision.editor.saveError.title"), isPresented: $precisionSaveError) {
            Button(settings.t("scanner.retry"), action: confirmMeasurement)
            Button(settings.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("precision.editor.saveError.body"))
        }
        .alert(settings.t("precision.inline.unavailable.title"), isPresented: $precisionLoadError) {
            Button(settings.t("scanner.retry"), action: loadPrecisionDocumentIfAvailable)
            Button(settings.t("common.ok"), role: .cancel) {}
        } message: {
            Text(settings.t("precision.inline.unavailable.body"))
        }
        .overlay(alignment: .top) {
            if showsSavedConfirmation {
                Label(settings.t("precision.inline.saved"), systemImage: "checkmark.circle.fill")
                    .font(Typography.control)
                    .foregroundStyle(Palette.onGraphite)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.graphite, in: .capsule)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showsRooms) {
            if let floor = selectedFloor {
                RoomsSheet(floor: floor, selectedRoomID: $selectedRoomID)
                    .toastOverlay(model, settings: settings)
            }
        }
        .projectActions(renaming: $renaming, deleting: $deleting) {
            model.path.removeAll { $0 == .project(project.id) || $0 == .reports(project.id) }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(Typography.detailTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Text(metaText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                if project.isSample {
                    SampleBadge()
                }
            }
            if let description = project.projectDescription {
                Text(description)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Spacing.titleEdge)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var planArea: some View {
        if let plan, let floor = selectedFloor {
            switch mode {
            case .plan2D:
                FloorPlanViewer(
                    plan: plan,
                    labels: currentPlanLabels(for: floor),
                    selectedRoomID: $selectedRoomID,
                    precisionPlan: structuralDragPreview
                        ?? openingPreview?.candidatePlan
                        ?? structuralPropertiesPreview?.plan
                        ?? precisionSession?.displayedPlan,
                    selectedPrecisionWallID: $selectedWallID,
                    selectedPrecisionOpeningID: $selectedOpeningID,
                    selectedPrecisionColumnID: $selectedColumnID,
                    selectedPrecisionBeamID: $selectedBeamID,
                    onPrecisionWallSelected: beginMeasurement,
                    onPrecisionOpeningSelected: beginOpeningMeasurement,
                    onPrecisionColumnSelected: beginColumnProperties,
                    onPrecisionBeamSelected: beginBeamProperties,
                    onAddStructuralElement: { showsStructuralChooser = true },
                    structuralPlacementActive: structuralDraft.isPlacing,
                    onStructuralPointSelected: placeStructuralPoint,
                    onCancelStructuralPlacement: cancelStructuralCreation,
                    structuralDraftPreview: structuralDraft.kind == nil ? nil : structuralDraft,
                    onStructuralDrag: handleStructuralDrag,
                    onUndo: { persistHistoryChange(isUndo: true) },
                    onRedo: { persistHistoryChange(isUndo: false) },
                    canUndo: precisionSession?.canUndo ?? false,
                    canRedo: precisionSession?.canRedo ?? false
                )
            case .model3D:
                PlanPlaceholder(systemImage: "cube.transparent",
                                titleKey: "project.3d.title", bodyKey: "project.3d.body")
            }
        } else if planError != nil {
            PlanPlaceholder(systemImage: "exclamationmark.triangle",
                            titleKey: "plan.error.title", bodyKey: "plan.error.body")
        } else {
            PlanPlaceholder(systemImage: nil, titleKey: "plan.notScanned", bodyKey: "plan.notScanned.body",
                            actionKey: "plan.scanAction") {
                model.openScanner(projectID: project.id, floorID: selectedFloor?.id)
            }
        }
    }

    @ViewBuilder
    private var structuralPropertiesSheetContent: some View {
        if let draft = structuralPropertiesDraft {
            StructuralPropertiesSheet(
                draft: Binding(
                    get: { structuralPropertiesDraft ?? draft },
                    set: updateStructuralProperties
                ),
                canSave: structuralPropertiesPreview?.changed == true,
                errorKey: structuralPropertiesErrorKey,
                onConfirm: confirmStructuralProperties,
                onClose: closeStructuralProperties
            )
        }
    }

    private func currentPlanLabels(for floor: Floor) -> [String: PlanRoomLabel] {
        var labels = floor.planLabels
        guard let selectedScan,
              let room = floor.rooms.first(where: { $0.id == selectedScan.roomID }),
              let identifier = room.geometryIdentifier else { return labels }
        labels[identifier] = PlanRoomLabel(
            name: room.name,
            area: precisionSession?.displayedPlan.derivedFloorArea ?? room.effectiveArea
        )
        return labels
    }

    private var currentMillimeters: String? {
        guard let wallID = selectedWallID,
              let plan = precisionSession?.document.currentPlan,
              let wall = plan.wall(id: wallID) else { return nil }
        return PrecisionMeasurementInput.millimeters(fromMeters: wall.length(in: plan))
    }

    private var currentMeasurementLabelKey: String {
        guard let wallID = selectedWallID else { return "precision.inline.lidarCurrent" }
        for revision in precisionSession?.document.revisions.reversed() ?? [] {
            guard case .setWallLength(let command) = revision.command, command.wallID == wallID else { continue }
            return command.provenance.source == .laserVerified
                ? "precision.inline.laserCurrent" : "precision.inline.current"
        }
        return "precision.inline.lidarCurrent"
    }

    private func loadPrecisionDocumentIfAvailable() {
        guard let selectedScan, let plan else { return }
        do {
            let document = try ParametricPlanRepository(files: files)
                .loadPrecisionDocument(scan: selectedScan, floorPlan: plan)
            precisionSession = GeometryRevisionSession(document: document)
            synchronizeStoredArea(document.currentPlan, scan: selectedScan)
            precisionLoadError = false
        } catch {
            precisionSession = nil
            precisionLoadError = true
        }
    }

    private func beginMeasurement(_ wallID: UUID) {
        guard let plan = precisionSession?.document.currentPlan,
              let wall = plan.wall(id: wallID) else { return }
        precisionSession?.cancelPreview()
        closeOpeningPanel()
        selectedWallID = wallID
        measurementInput = PrecisionMeasurementInput.millimeters(fromMeters: wall.length(in: plan))
        selectedAnchor = nil
        requiresAnchorChoice = false
        precisionConflict = false
        laserVerified = false
        Task { @MainActor in
            await Task.yield()
            guard selectedWallID == wallID else { return }
            showsMeasurementPanel = true
        }
    }

    private func beginOpeningMeasurement(_ openingID: UUID) {
        guard let plan = precisionSession?.document.currentPlan,
              let opening = plan.openings.first(where: { $0.id == openingID }) else { return }
        precisionSession?.cancelPreview()
        selectedWallID = nil
        selectedOpeningID = openingID
        openingDraft = OpeningMeasurementDraft.make(opening: opening, plan: plan)
        openingPreview = OpeningEditEngine.preview(draft: openingDraft!, in: plan)
        Task { @MainActor in
            await Task.yield()
            guard selectedOpeningID == openingID else { return }
            showsOpeningPanel = true
        }
    }

    private func beginColumnCreation(_ shape: ColumnShape) {
        structuralDraft.beginColumn(shape: shape)
        structuralErrorKey = nil
        showsStructuralChooser = false
    }

    private func beginBeamCreation() {
        structuralDraft.beginBeam()
        structuralErrorKey = nil
        showsStructuralChooser = false
    }

    private func placeStructuralPoint(_ point: PlanPoint2D) {
        structuralDraft.place(point)
        if structuralDraft.placementStep == .dimensions {
            Task { @MainActor in
                await Task.yield()
                showsStructuralDimensions = true
            }
        }
    }

    private func confirmStructuralCreation() {
        guard !structuralDraft.isSaving,
              let plan = precisionSession?.document.currentPlan,
              var document = precisionSession?.document,
              let selectedScan else { return }
        structuralDraft.isSaving = true
        switch StructuralCreationEngine().candidate(from: structuralDraft, in: plan) {
        case .failure(let error):
            structuralDraft.isSaving = false
            structuralErrorKey = error == .missingPlacement
                ? "precision.structural.placeRequired" : "precision.structural.invalidDimension"
        case .success(let candidate):
            document.recordPlanReplacement(
                candidate.plan,
                reason: .structuralCreation,
                geometryID: candidate.createdID
            )
            do {
                try ParametricPlanRepository(files: files).savePrecisionDocument(document, scan: selectedScan)
                synchronizeStoredArea(document.currentPlan, scan: selectedScan)
                var updatedSession = precisionSession
                updatedSession?.acceptPersistedDocument(document)
                precisionSession = updatedSession
                selectedColumnID = candidate.kind == .column ? candidate.createdID : nil
                selectedBeamID = candidate.kind == .beam ? candidate.createdID : nil
                structuralDraft = .init()
                showsStructuralDimensions = false
                withAnimation { showsSavedConfirmation = true }
                dismissSavedConfirmationLater()
            } catch {
                structuralDraft.isSaving = false
                structuralErrorKey = "precision.structural.saveFailed"
            }
        }
    }

    private func structuralDimensionsDismissed() {
        if structuralDraft.placementStep == .dimensions, !structuralDraft.isSaving {
            structuralDraft = .init()
        }
    }

    private func cancelStructuralCreation() {
        showsStructuralChooser = false
        showsStructuralDimensions = false
        structuralDraft = .init()
        structuralErrorKey = nil
    }

    private func beginColumnProperties(_ id: UUID) {
        guard let column = precisionSession?.document.currentPlan.columns.first(where: { $0.id == id }) else { return }
        selectedColumnID = id
        selectedBeamID = nil
        structuralPropertiesDraft = .make(column: column)
        structuralPropertiesPreview = nil
        structuralPropertiesErrorKey = nil
        showsStructuralProperties = true
    }

    private func beginBeamProperties(_ id: UUID) {
        guard let plan = precisionSession?.document.currentPlan,
              let beam = plan.beams.first(where: { $0.id == id }) else { return }
        selectedBeamID = id
        selectedColumnID = nil
        structuralPropertiesDraft = .make(beam: beam, in: plan)
        structuralPropertiesPreview = nil
        structuralPropertiesErrorKey = nil
        showsStructuralProperties = true
    }

    private func updateStructuralProperties(_ draft: StructuralPropertiesDraft) {
        structuralPropertiesDraft = draft
        guard let plan = precisionSession?.document.currentPlan else { return }
        switch StructuralPropertiesEngine().preview(draft: draft, in: plan) {
        case .success(let preview):
            structuralPropertiesPreview = preview
            structuralPropertiesErrorKey = preview.changed ? nil : "precision.structural.noChanges"
        case .failure(let error):
            structuralPropertiesPreview = nil
            structuralPropertiesErrorKey = error == .verticalConflict
                ? "precision.structural.verticalConflict" : "precision.structural.invalidDimension"
        }
    }

    private func confirmStructuralProperties() {
        guard var draft = structuralPropertiesDraft,
              !draft.isSaving,
              let preview = structuralPropertiesPreview,
              preview.changed,
              var document = precisionSession?.document,
              let selectedScan else { return }
        draft.isSaving = true
        structuralPropertiesDraft = draft
        document.recordPlanReplacement(
            preview.plan,
            reason: .structuralProperties,
            geometryID: draft.id
        )
        do {
            try ParametricPlanRepository(files: files).savePrecisionDocument(document, scan: selectedScan)
            synchronizeStoredArea(document.currentPlan, scan: selectedScan)
            var updatedSession = precisionSession
            updatedSession?.acceptPersistedDocument(document)
            precisionSession = updatedSession
            showsStructuralProperties = false
            withAnimation { showsSavedConfirmation = true }
            dismissSavedConfirmationLater()
        } catch {
            draft.isSaving = false
            structuralPropertiesDraft = draft
            structuralPropertiesErrorKey = "precision.structural.saveFailed"
        }
    }

    private func closeStructuralProperties() {
        showsStructuralProperties = false
        structuralPropertiesDraft = nil
        structuralPropertiesPreview = nil
        structuralPropertiesErrorKey = nil
    }

    private func dismissSavedConfirmationLater() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showsSavedConfirmation = false }
        }
    }

    private func handleStructuralDrag(_ event: StructuralDragEvent) {
        guard !isSavingMeasurement,
              let plan = precisionSession?.document.currentPlan,
              let candidate = StructuralDragResolver.candidate(event: event, in: plan) else { return }
        structuralDragPreview = candidate.plan
        guard event.phase == .ended, var document = precisionSession?.document, let selectedScan else { return }
        document.recordPlanReplacement(candidate.plan, reason: .structuralDrag, geometryID: event.id)
        do {
            try ParametricPlanRepository(files: files).savePrecisionDocument(document, scan: selectedScan)
            var session = precisionSession
            session?.acceptPersistedDocument(document)
            precisionSession = session
            structuralDragPreview = nil
            withAnimation { showsSavedConfirmation = true }
            dismissSavedConfirmationLater()
        } catch {
            structuralDragPreview = nil
            precisionSaveError = true
        }
    }

    private func persistHistoryChange(isUndo: Bool) {
        guard !isSavingMeasurement, var candidate = precisionSession, let selectedScan else { return }
        let changed = isUndo ? candidate.undo() : candidate.redo()
        guard changed else { return }
        do {
            try ParametricPlanRepository(files: files).savePrecisionDocument(candidate.document, scan: selectedScan)
            synchronizeStoredArea(candidate.document.currentPlan, scan: selectedScan)
            precisionSession = candidate
            structuralDragPreview = nil
            closeMeasurementPanel()
            closeOpeningPanel()
            closeStructuralProperties()
        } catch {
            precisionSaveError = true
        }
    }

    private func closeOpeningPanel() {
        showsOpeningPanel = false
        selectedOpeningID = nil
        openingDraft = nil
        openingPreview = nil
    }

    private func openingOrdinal(_ opening: WallOpening) -> Int {
        let matching = precisionSession?.document.currentPlan.openings.filter { $0.kind == opening.kind } ?? []
        return (matching.firstIndex(where: { $0.id == opening.id }) ?? 0) + 1
    }

    private func confirmOpeningMeasurement() {
        guard !isSavingMeasurement, let preview = openingPreview, preview.isValid,
              var document = precisionSession?.document, let selectedScan else { return }
        isSavingMeasurement = true
        document.currentPlan = preview.candidatePlan
        do {
            try ParametricPlanRepository(files: files).savePrecisionDocument(document, scan: selectedScan)
            synchronizeStoredArea(document.currentPlan, scan: selectedScan)
            precisionSession = GeometryRevisionSession(document: document)
            isSavingMeasurement = false
            closeOpeningPanel()
            withAnimation { showsSavedConfirmation = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { showsSavedConfirmation = false }
            }
        } catch {
            isSavingMeasurement = false
            precisionSaveError = true
        }
    }

    private func closeMeasurementPanel() {
        precisionSession?.cancelPreview()
        showsMeasurementPanel = false
        selectedWallID = nil
        measurementInput = ""
        selectedAnchor = nil
        requiresAnchorChoice = false
        precisionConflict = false
    }

    private func updatePrecisionPreview() {
        guard var base = precisionSession, let wallID = selectedWallID,
              let target = PrecisionMeasurementInput.meters(fromMillimeters: measurementInput) else {
            precisionSession?.cancelPreview()
            precisionConflict = false
            return
        }
        base.cancelPreview()
        let source: GeometrySourceKind = laserVerified ? .laserVerified : .manualEntered
        let status: GeometryVerificationStatus = laserVerified ? .verified : .unverified
        func proposed(_ anchor: WallLengthAnchorStrategy) -> GeometryRevisionSession? {
            var candidate = base
            let command = SetWallLengthCommand(
                id: UUID(), wallID: wallID, targetLength: target, anchor: anchor,
                provenance: .init(source: source, verificationStatus: status,
                                  timestamp: Date(), uncertainty: nil),
                createdAt: Date()
            )
            if case .solved = candidate.propose(
                command,
                allowsReplacingVerifiedMeasurement: true,
                preservesUnrelatedGeometry: true
            ) {
                return candidate
            }
            return nil
        }
        if let selectedAnchor {
            if let candidate = proposed(selectedAnchor) {
                precisionSession = candidate
                precisionConflict = false
            } else {
                precisionSession?.cancelPreview()
                precisionConflict = true
            }
            return
        }
        let start = proposed(.keepStart)
        let end = proposed(.keepEnd)
        switch (start, end) {
        case let (.some(start), .some(end)) where start.displayedPlan == end.displayedPlan:
            selectedAnchor = .keepStart
            precisionSession = start
            requiresAnchorChoice = false
            precisionConflict = false
        case let (.some(start), .some(end)):
            let preferred = PrecisionAutomaticAnchor.preferred(
                from: base.document.currentPlan, start: start, end: end
            )
            selectedAnchor = preferred.0
            precisionSession = preferred.1
            requiresAnchorChoice = false
            precisionConflict = false
        case let (.some(candidate), nil):
            selectedAnchor = .keepStart
            precisionSession = candidate
            requiresAnchorChoice = false
            precisionConflict = false
        case let (nil, .some(candidate)):
            selectedAnchor = .keepEnd
            precisionSession = candidate
            requiresAnchorChoice = false
            precisionConflict = false
        case (nil, nil):
            precisionSession?.cancelPreview()
            requiresAnchorChoice = false
            precisionConflict = true
        }
    }

    private func confirmMeasurement() {
        guard !isSavingMeasurement, var candidate = precisionSession,
              candidate.applyPreview() != nil, let selectedScan else { return }
        isSavingMeasurement = true
        do {
            try ParametricPlanRepository(files: files)
                .savePrecisionDocument(candidate.document, scan: selectedScan)
            synchronizeStoredArea(candidate.document.currentPlan, scan: selectedScan)
            precisionSession = candidate
            isSavingMeasurement = false
            closeMeasurementPanel()
            withAnimation { showsSavedConfirmation = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { showsSavedConfirmation = false }
            }
        } catch {
            isSavingMeasurement = false
            precisionSaveError = true
        }
    }

    private func synchronizeStoredArea(_ plan: ParametricFloorPlan, scan: SavedScan) {
        guard let area = plan.derivedFloorArea,
              let room = project.allRooms.first(where: { $0.id == scan.roomID }),
              room.area != area else { return }
        room.area = area
        room.updatedAt = .now
        try? context.save()
    }

    private var moreMenu: some View {
        Menu {
            Button(settings.t("project.pdf"), systemImage: "doc.text") {
                model.path.append(.reports(project.id))
            }
            Button(settings.t(plan == nil ? "plan.scanAction" : "project.rescan"), systemImage: "viewfinder") {
                model.openScanner(projectID: project.id, floorID: selectedFloor?.id)
            }
            Button(settings.t("project.rename"), systemImage: "pencil") {
                renaming = project
            }
            Divider()
            Button(settings.t("project.delete"), systemImage: "trash", role: .destructive) {
                deleting = project
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(settings.t("project.more"))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { showsRooms = true } label: {
                Text(verbatim: "\(settings.t("project.rooms")) · \(selectedFloor?.rooms.count ?? 0)")
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Palette.surface, in: .rect(cornerRadius: Radius.medium))
            }
            .buttonStyle(.pressable)

            Button { model.path.append(.reports(project.id)) } label: {
                Label(settings.t("project.pdf"), systemImage: "doc.text")
                    .font(Typography.button)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Palette.accent, in: .rect(cornerRadius: Radius.medium))
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

/// Centered icon + message inside the plan area (not scanned, 3D placeholder, load error).
private struct PlanPlaceholder: View {
    let systemImage: String?
    let titleKey: String
    let bodyKey: String
    var actionKey: String?
    var action: (() -> Void)?
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.inkTertiary)
            } else {
                ScanFrameGlyph(cornerColor: Palette.inkTertiary, lineWidth: 2)
                    .frame(width: 44, height: 44)
            }
            Text(settings.t(titleKey))
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(settings.t(bodyKey))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: 270)
            if let actionKey, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        ScanFrameGlyph(showsCenterLine: true, cornerColor: Palette.onAccent,
                                       lineColor: Palette.onAccent, lineWidth: 2.3)
                            .frame(width: 20, height: 20)
                        Text(settings.t(actionKey))
                    }
                    .font(Typography.control)
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Palette.accent, in: .capsule)
                }
                .buttonStyle(.pressable)
                .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.planBackground)
    }
}

/// Shown if a pushed project no longer exists (e.g. deleted elsewhere).
struct MissingProjectView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Text(settings.t("project.missing"))
            .font(Typography.body)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
    }
}
