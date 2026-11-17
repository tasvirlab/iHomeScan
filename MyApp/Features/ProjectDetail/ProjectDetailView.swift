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
        if let area = project.totalArea { parts.append(settings.area(area)) }
        parts.append(settings.roomCount(project.allRooms.count))
        if let height = project.ceilingHeight {
            parts.append(settings.t("project.ceiling", settings.ceilingHeight(height)))
        }
        return parts.joined(separator: " · ")
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled(isSavingMeasurement)
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
                    labels: floor.planLabels,
                    selectedRoomID: $selectedRoomID,
                    precisionPlan: precisionSession?.displayedPlan,
                    selectedPrecisionWallID: $selectedWallID,
                    onPrecisionWallSelected: beginMeasurement
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
            if case .solved = candidate.propose(command, allowsReplacingVerifiedMeasurement: true) {
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
