import SwiftUI
import SwiftData
#if canImport(QuickLook) && canImport(UIKit)
import QuickLook
import UIKit
#endif

struct SavedScanViewerScreen: View {
    private enum Mode: Hashable { case plan2D, model3D }

    let projectID: UUID
    let roomID: UUID
    @Query private var scans: [SavedScan]
    @Query private var rooms: [Room]

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    @State private var selectedScanID: UUID?
    @State private var mode: Mode = .plan2D
    @State private var content: SavedScanContent?
    @State private var contentCache: [UUID: SavedScanContent] = [:]
    @State private var loadError: SavedScanLoadingError?
    @State private var selectedPlanRoomID: String?
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

    init(projectID: UUID, roomID: UUID, scanID: UUID? = nil) {
        self.projectID = projectID
        self.roomID = roomID
        _scans = Query(
            filter: #Predicate<SavedScan> { $0.roomID == roomID && $0.projectID == projectID },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        _rooms = Query(filter: #Predicate<Room> { $0.id == roomID })
        _selectedScanID = State(initialValue: scanID)
    }

    private var room: Room? { rooms.first }
    private var selectedScan: SavedScan? {
        scans.first { $0.id == selectedScanID } ?? scans.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if scans.isEmpty {
                SavedScanEmptyState()
            } else {
                SavedScanVersionHeader(
                    scans: scans,
                    selectedScanID: Binding(
                        get: { selectedScan?.id },
                        set: { selectedScanID = $0 }
                    )
                )
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.vertical, 12)

                SegmentedPill(
                    options: [
                        .init(value: .plan2D, title: settings.t("project.plan2d")),
                        .init(value: .model3D, title: settings.t("project.model3d")),
                    ],
                    selection: $mode,
                    height: 34
                )
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.bottom, 12)

                viewerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: Radius.large))
                    .overlay(RoundedRectangle(cornerRadius: Radius.large).strokeBorder(Palette.line, lineWidth: 0.5))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Palette.background)
        .navigationTitle(room?.name ?? settings.t("scan.viewer.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedScanID == nil { selectedScanID = scans.first?.id }
        }
        .task(id: selectedScan?.id) { loadSelectedScan() }
        .task(id: PrecisionInlinePreviewRequest(input: measurementInput, wallID: selectedWallID, anchor: selectedAnchor, laserVerified: laserVerified)) {
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
                draft: $structuralDraft, showsChooser: true, errorKey: nil,
                onBeginColumn: beginColumnCreation, onBeginBeam: beginBeamCreation,
                onConfirm: {}, onClose: cancelStructuralCreation
            )
        }
        .sheet(isPresented: $showsStructuralDimensions, onDismiss: structuralDimensionsDismissed) {
            StructuralCreationSheet(
                draft: $structuralDraft, showsChooser: false, errorKey: structuralErrorKey,
                onBeginColumn: { _ in }, onBeginBeam: {},
                onConfirm: confirmStructuralCreation, onClose: cancelStructuralCreation
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
            Button(settings.t("scanner.retry")) {
                if let selectedScan, let content { loadPrecisionDocument(for: selectedScan, floorPlan: content.floorPlan) }
            }
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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var viewerContent: some View {
        if let content {
            switch mode {
            case .plan2D:
                FloorPlanViewer(
                    plan: content.floorPlan,
                    labels: planLabels,
                    selectedRoomID: $selectedPlanRoomID,
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
                if let modelURL = content.modelURL {
                    SavedUSDZViewer(url: modelURL, showsOriginalScanNotice: !(precisionSession?.document.revisions.isEmpty ?? true))
                } else {
                    SavedScanLoadErrorView(error: content.modelError ?? .invalidModel) {
                        if let scanID = selectedScan?.id { contentCache.removeValue(forKey: scanID) }
                        loadSelectedScan()
                    }
                }
            }
        } else if let loadError {
            SavedScanLoadErrorView(error: loadError) { loadSelectedScan() }
        } else {
            ProgressView(settings.t("scan.viewer.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.planBackground)
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

    private var planLabels: [String: PlanRoomLabel] {
        guard let room, let identifier = room.geometryIdentifier else { return [:] }
        let area = precisionSession?.displayedPlan.derivedFloorArea ?? selectedScan?.floorArea
        return [identifier: PlanRoomLabel(name: room.name, area: area)]
    }

    private func loadSelectedScan() {
        cancelStructuralCreation()
        content = nil
        loadError = nil
        guard let selectedScan else { return }
        if let cached = contentCache[selectedScan.id] {
            content = cached
            loadPrecisionDocument(for: selectedScan, floorPlan: cached.floorPlan)
            return
        }
        do {
            let loaded = try SavedScanContentLoader(context: context, files: files).load(selectedScan)
            contentCache[selectedScan.id] = loaded
            content = loaded
            loadPrecisionDocument(for: selectedScan, floorPlan: loaded.floorPlan)
        } catch let error as SavedScanLoadingError {
            loadError = error
        } catch {
            loadError = .invalidGeometry
        }
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

    private func loadPrecisionDocument(for scan: SavedScan, floorPlan: FloorPlan) {
        do {
            let document = try ParametricPlanRepository(files: files).loadPrecisionDocument(scan: scan, floorPlan: floorPlan)
            precisionSession = GeometryRevisionSession(document: document)
            synchronizeStoredArea(document.currentPlan, scan: scan)
            precisionLoadError = false
        } catch {
            precisionSession = nil
            precisionLoadError = true
        }
    }

    private func beginMeasurement(_ wallID: UUID) {
        guard let plan = precisionSession?.document.currentPlan, let wall = plan.wall(id: wallID) else { return }
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
                provenance: .init(source: source, verificationStatus: status, timestamp: Date(), uncertainty: nil),
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
            try ParametricPlanRepository(files: files).savePrecisionDocument(candidate.document, scan: selectedScan)
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

    private func persistHistoryChange(isUndo: Bool) {
        guard !isSavingMeasurement, var candidate = precisionSession, let selectedScan else { return }
        let changed = isUndo ? candidate.undo() : candidate.redo()
        guard changed else { return }
        isSavingMeasurement = true
        do {
            try ParametricPlanRepository(files: files).savePrecisionDocument(candidate.document, scan: selectedScan)
            synchronizeStoredArea(candidate.document.currentPlan, scan: selectedScan)
            precisionSession = candidate
            isSavingMeasurement = false
            closeMeasurementPanel()
        } catch {
            isSavingMeasurement = false
            precisionSaveError = true
        }
    }

    private func synchronizeStoredArea(_ plan: ParametricFloorPlan, scan: SavedScan) {
        guard let area = plan.derivedFloorArea,
              let room = rooms.first(where: { $0.id == scan.roomID }),
              room.area != area else { return }
        room.area = area
        room.updatedAt = .now
        try? context.save()
    }
}

struct PrecisionInlinePreviewRequest: Equatable {
    let input: String
    let wallID: UUID?
    let anchor: WallLengthAnchorStrategy?
    let laserVerified: Bool
}

private struct SavedScanVersionHeader: View {
    let scans: [SavedScan]
    @Binding var selectedScanID: UUID?
    @Environment(AppSettings.self) private var settings

    private var selectedScan: SavedScan? { scans.first { $0.id == selectedScanID } ?? scans.first }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("scan.viewer.version"))
                    .font(Typography.settingsHeader)
                    .foregroundStyle(Palette.inkSecondary)
                if let scan = selectedScan {
                    Text(scan.createdAt, format: .dateTime.day().month(.abbreviated).year().hour().minute().locale(settings.locale))
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.ink)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Picker(settings.t("scan.viewer.version"), selection: $selectedScanID) {
                    ForEach(scans) { scan in
                        Text(scan.createdAt, format: .dateTime.day().month().year().hour().minute().locale(settings.locale))
                            .tag(UUID?.some(scan.id))
                    }
                }
            } label: {
                Label(settings.t("scan.viewer.versions", scans.count), systemImage: "clock.arrow.circlepath")
                    .font(Typography.control)
                    .foregroundStyle(Palette.accentText)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Palette.accentTint, in: .capsule)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SavedScanEmptyState: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ContentUnavailableView(
            settings.t("scan.viewer.empty.title"),
            systemImage: "viewfinder",
            description: Text(settings.t("scan.viewer.empty.body"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SavedScanLoadErrorView: View {
    let error: SavedScanLoadingError
    let retry: () -> Void
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ContentUnavailableView {
            Label(settings.t("scan.viewer.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(settings.t(error == .missingModel || error == .invalidModel
                            ? "scan.viewer.error.model" : "scan.viewer.error.geometry"))
        } actions: {
            Button(settings.t("scanner.retry"), action: retry).buttonStyle(.borderedProminent).tint(Palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.planBackground)
    }
}

private struct SavedUSDZViewer: View {
    let url: URL
    let showsOriginalScanNotice: Bool
    @Environment(AppSettings.self) private var settings
    @State private var loadState: ArchitecturalModelLoadState = .loading
    @State private var resetID = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if loadState == .failed {
                quickLookFallback
            } else {
                RealityKitArchitecturalViewer(url: url, resetID: resetID, loadState: $loadState)
                if loadState == .loading {
                    ProgressView(settings.t("scan.viewer.loading"))
                        .padding(14)
                        .background(.regularMaterial, in: .rect(cornerRadius: Radius.medium))
                }
            }
            if loadState == .ready {
                Button {
                    resetID += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: .circle)
                        .overlay(Circle().strokeBorder(Palette.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("plan.reset"))
                .padding(12)
            }
            if showsOriginalScanNotice {
                Text(settings.t("precision.editor.original3D"))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
        .background(Palette.planBackground)
    }

    @ViewBuilder
    private var quickLookFallback: some View {
        #if canImport(QuickLook) && canImport(UIKit)
        if QLPreviewController.canPreview(url as NSURL) {
            EmbeddedQuickLookPreview(url: url)
        } else {
            modelUnavailable
        }
        #else
        modelUnavailable
        #endif
    }

    private var modelUnavailable: some View {
        ContentUnavailableView(
            settings.t("scan.viewer.3d.unavailable"),
            systemImage: "cube.transparent"
        )
    }
}

#if canImport(QuickLook) && canImport(UIKit)
private struct EmbeddedQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
        controller.currentPreviewItemIndex = 0
    }

    static func dismantleUIViewController(_ controller: QLPreviewController, coordinator: Coordinator) {
        controller.dataSource = nil
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
