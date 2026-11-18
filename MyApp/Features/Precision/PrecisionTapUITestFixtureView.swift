#if DEBUG
import SwiftUI

/// Deterministic UI-test-only floor plan. It is never presented without the explicit launch argument.
struct PrecisionTapUITestFixtureView: View {
    private static let persistedMetersKey = "precision.uiTest.persistedMeters"
    private static let persistedDoorOffsetKey = "precision.uiTest.persistedDoorOffset"
    private static let persistedColumnKey = "precision.uiTest.persistedColumn"
    private static let persistedBeamKey = "precision.uiTest.persistedBeam"
    private static let wallID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    private static let doorID = UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
    private static let columnID = UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!
    private static let beamID = UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!
    @State private var selectedRoomID: String?
    @State private var selectedWallID: UUID?
    @State private var selectedOpeningID: UUID?
    @State private var showsMeasurementPanel = false
    @State private var input = ""
    @State private var laserVerified = false
    @State private var anchor: WallLengthAnchorStrategy?
    @State private var plan: ParametricFloorPlan
    @State private var openingDraft: OpeningMeasurementDraft?
    @State private var openingPreview: OpeningEditPreview?
    @State private var showsOpeningPanel = false
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

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-precision-ui-test") {
            UserDefaults.standard.removeObject(forKey: Self.persistedMetersKey)
            UserDefaults.standard.removeObject(forKey: Self.persistedDoorOffsetKey)
            UserDefaults.standard.removeObject(forKey: Self.persistedColumnKey)
            UserDefaults.standard.removeObject(forKey: Self.persistedBeamKey)
        }
        _plan = State(initialValue: Self.fixtureParametricPlan())
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("DEBUG TEST FIXTURE")
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityIdentifier("precision.fixture.label")
            FloorPlanViewer(
                plan: Self.fixtureFloorPlan,
                labels: ["fixture-room": .init(name: "Fixture room", area: 12)],
                selectedRoomID: $selectedRoomID,
                precisionPlan: openingPreview?.candidatePlan ?? plan,
                selectedPrecisionWallID: $selectedWallID,
                selectedPrecisionOpeningID: $selectedOpeningID,
                selectedPrecisionColumnID: $selectedColumnID,
                selectedPrecisionBeamID: $selectedBeamID,
                onPrecisionWallSelected: selectWall,
                onPrecisionOpeningSelected: selectOpening,
                onPrecisionColumnSelected: beginColumnProperties,
                onPrecisionBeamSelected: beginBeamProperties,
                onAddStructuralElement: { showsStructuralChooser = true },
                structuralPlacementActive: structuralDraft.isPlacing,
                onStructuralPointSelected: placeStructuralPoint,
                onCancelStructuralPlacement: cancelStructural,
                structuralDraftPreview: structuralDraft.kind == nil ? nil : structuralDraft,
                onStructuralDrag: handleStructuralDrag
            )
        }
        .sheet(isPresented: $showsOpeningPanel, onDismiss: closeOpeningPanel) {
            if let draft = openingDraft {
                InlineOpeningMeasurementSheet(
                    openingKind: .door,
                    ordinal: 1,
                    draft: Binding(get: { openingDraft ?? draft }, set: {
                        openingDraft = $0
                        openingPreview = OpeningEditEngine.preview(draft: $0, in: plan)
                    }),
                    preview: openingPreview,
                    isSaving: false,
                    onConfirm: confirmOpening,
                    onClose: closeOpeningPanel
                )
            }
        }
        .background(Palette.background)
        .sheet(isPresented: $showsStructuralChooser) {
            StructuralCreationSheet(
                draft: $structuralDraft, showsChooser: true, errorKey: nil,
                onBeginColumn: beginColumn, onBeginBeam: beginBeam,
                onConfirm: {}, onClose: cancelStructural
            )
        }
        .sheet(isPresented: $showsStructuralDimensions) {
            StructuralCreationSheet(
                draft: $structuralDraft, showsChooser: false, errorKey: structuralErrorKey,
                onBeginColumn: { _ in }, onBeginBeam: {},
                onConfirm: confirmStructural, onClose: cancelStructural
            )
        }
        .sheet(isPresented: $showsStructuralProperties, onDismiss: closeStructuralProperties) {
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
        .sheet(isPresented: $showsMeasurementPanel, onDismiss: closeMeasurementPanel) {
            InlinePrecisionMeasurementSheet(
                    currentMillimeters: PrecisionMeasurementInput.millimeters(fromMeters: plan.walls.first?.length(in: plan)),
                    currentLabelKey: "precision.inline.current",
                    input: $input,
                    laserVerified: $laserVerified,
                    anchor: $anchor,
                    requiresAnchorChoice: false,
                    hasValidPreview: PrecisionMeasurementInput.meters(fromMillimeters: input) != nil,
                    hasConflict: false,
                    isSaving: false,
                    onConfirm: confirm,
                    onClose: closeMeasurementPanel
                )
                .presentationDetents([.height(460), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func selectWall(_ id: UUID) {
        closeOpeningPanel()
        selectedWallID = id
        input = PrecisionMeasurementInput.millimeters(fromMeters: plan.wall(id: id)?.length(in: plan))
        Task { @MainActor in
            await Task.yield()
            guard selectedWallID == id else { return }
            showsMeasurementPanel = true
        }
    }

    private func selectOpening(_ id: UUID) {
        guard let opening = plan.openings.first(where: { $0.id == id }) else { return }
        selectedWallID = nil
        selectedOpeningID = id
        openingDraft = OpeningMeasurementDraft.make(opening: opening, plan: plan)
        openingPreview = openingDraft.flatMap { OpeningEditEngine.preview(draft: $0, in: plan) }
        showsOpeningPanel = true
    }

    private func closeOpeningPanel() {
        showsOpeningPanel = false
        selectedOpeningID = nil
        openingDraft = nil
        openingPreview = nil
    }

    private func confirmOpening() {
        guard let preview = openingPreview, preview.isValid,
              let placement = preview.resolution.placements.first(where: { $0.openingID == Self.doorID }) else { return }
        plan = preview.candidatePlan
        UserDefaults.standard.set(placement.startOffset, forKey: Self.persistedDoorOffsetKey)
        closeOpeningPanel()
    }

    private func beginColumn(_ shape: ColumnShape) {
        structuralDraft.beginColumn(shape: shape)
        showsStructuralChooser = false
    }

    private func beginBeam() {
        structuralDraft.beginBeam()
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

    private func confirmStructural() {
        let stableID = structuralDraft.kind == .column ? Self.columnID : Self.beamID
        switch StructuralCreationEngine().candidate(from: structuralDraft, in: plan, id: stableID) {
        case .failure:
            structuralErrorKey = "precision.structural.invalidDimension"
        case .success(let candidate):
            plan = candidate.plan
            selectedColumnID = candidate.kind == .column ? candidate.createdID : nil
            selectedBeamID = candidate.kind == .beam ? candidate.createdID : nil
            UserDefaults.standard.set(true, forKey: candidate.kind == .column
                                      ? Self.persistedColumnKey : Self.persistedBeamKey)
            structuralDraft = .init()
            showsStructuralDimensions = false
        }
    }

    private func cancelStructural() {
        showsStructuralChooser = false
        showsStructuralDimensions = false
        structuralDraft = .init()
        structuralErrorKey = nil
    }

    private func handleStructuralDrag(_ event: StructuralDragEvent) {
        guard let candidate = StructuralDragResolver.candidate(event: event, in: plan) else { return }
        plan = candidate.plan
    }

    private func beginColumnProperties(_ id: UUID) {
        guard let column = plan.columns.first(where: { $0.id == id }) else { return }
        structuralPropertiesDraft = .make(column: column)
        structuralPropertiesPreview = nil
        structuralPropertiesErrorKey = nil
        showsStructuralProperties = true
    }

    private func beginBeamProperties(_ id: UUID) {
        guard let beam = plan.beams.first(where: { $0.id == id }) else { return }
        structuralPropertiesDraft = .make(beam: beam, in: plan)
        structuralPropertiesPreview = nil
        structuralPropertiesErrorKey = nil
        showsStructuralProperties = true
    }

    private func updateStructuralProperties(_ draft: StructuralPropertiesDraft) {
        structuralPropertiesDraft = draft
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
        guard let preview = structuralPropertiesPreview, preview.changed else { return }
        plan = preview.plan
        closeStructuralProperties()
    }

    private func closeStructuralProperties() {
        showsStructuralProperties = false
        structuralPropertiesDraft = nil
        structuralPropertiesPreview = nil
        structuralPropertiesErrorKey = nil
    }

    private func closeMeasurementPanel() {
        showsMeasurementPanel = false
        selectedWallID = nil
    }

    private func confirm() {
        guard let meters = PrecisionMeasurementInput.meters(fromMillimeters: input),
              let wall = plan.walls.first,
              let startIndex = plan.vertices.firstIndex(where: { $0.id == wall.startVertexID }),
              let endIndex = plan.vertices.firstIndex(where: { $0.id == wall.endVertexID }) else { return }
        let start = plan.vertices[startIndex].position
        let end = plan.vertices[endIndex].position
        let length = max(start.distance(to: end), 0.001)
        plan.vertices[endIndex].position = .init(
            x: start.x + (end.x - start.x) / length * meters,
            y: start.y + (end.y - start.y) / length * meters
        )
        UserDefaults.standard.set(meters, forKey: Self.persistedMetersKey)
        closeMeasurementPanel()
    }

    private static let fixtureFloorPlan = FloorPlan(
        bounds: CGRect(x: 0, y: 0, width: 4, height: 3),
        rooms: [.init(id: "fixture-room", rect: CGRect(x: 0, y: 0, width: 4, height: 3), labelCenter: CGPoint(x: 2, y: 1.5))],
        outerWalls: [[CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 0)]],
        innerWalls: [], doors: [], windows: [],
        dimensions: [.init(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 4, y: 0), value: 4,
                           labelPosition: CGPoint(x: 2, y: -0.4), labelRotation: 0)]
    )

    private static func fixtureParametricPlan() -> ParametricFloorPlan {
        let source = GeometrySourceMetadata(sourceElementID: nil, confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
        let startID = UUID(uuidString: "A2000000-0000-0000-0000-000000000001")!
        let endID = UUID(uuidString: "A2000000-0000-0000-0000-000000000002")!
        let persisted = UserDefaults.standard.double(forKey: persistedMetersKey)
        let length = persisted > 0 ? persisted : 4
        let persistedDoorOffset = UserDefaults.standard.double(forKey: persistedDoorOffsetKey)
        let doorOffset = persistedDoorOffset > 0 ? persistedDoorOffset : 0.65
        let provenance = MeasurementProvenance(source: .manualEntered, verificationStatus: .unverified, timestamp: nil, uncertainty: nil)
        let opening = WallOpening(
            id: doorID, hostWallID: wallID, kind: .door,
            width: .init(value: 0.9, provenance: provenance),
            height: .init(value: 2.1, provenance: provenance), verticalOffset: nil,
            horizontalAnchor: .distanceFromStart(.init(value: doorOffset + 0.45, provenance: provenance)),
            source: source,
            architecturalMetadata: .init(measurements: [
                .init(id: UUID(uuidString: "A4000000-0000-0000-0000-000000000001")!, openingID: doorID,
                      kind: .offsetFromStart, value: .init(value: doorOffset, provenance: provenance),
                      reference: .init(endpoint: .wallStart, vertexID: startID, reliability: .verified), relatedConstraintIDs: []),
                .init(id: UUID(uuidString: "A4000000-0000-0000-0000-000000000002")!, openingID: doorID,
                      kind: .width, value: .init(value: 0.9, provenance: provenance), reference: nil, relatedConstraintIDs: [])
            ], completeness: .partial, doorSwing: nil)
        )
        var plan = ParametricFloorPlan(
            id: UUID(uuidString: "A3000000-0000-0000-0000-000000000001")!,
            projectID: UUID(), roomID: UUID(), sourceScanID: UUID(),
            coordinateSystem: "DEBUG fixture; meters", completeness: .partial,
            vertices: [
                .init(id: startID, position: .init(x: 0, y: 0), source: source, mergedEndpointKeys: []),
                .init(id: endID, position: .init(x: length, y: 0), source: source, mergedEndpointKeys: [])
            ],
            walls: [.init(id: wallID, startVertexID: startID, endVertexID: endID, height: nil, thickness: nil, source: source)],
            openings: [opening], columns: [], beams: [], floorBoundary: nil, endpointMerges: [],
            revision: .init(number: 1, createdAt: .init(timeIntervalSince1970: 0), source: .manualEntered)
        )
        if UserDefaults.standard.bool(forKey: persistedColumnKey) {
            var draft = StructuralCreationDraft()
            draft.beginColumn(shape: .rectangular)
            draft.place(.init(x: 2, y: 1.5))
            draft.widthMillimeters = "300"
            draft.depthMillimeters = "400"
            if case .success(let candidate) = StructuralCreationEngine().candidate(
                from: draft, in: plan, id: columnID
            ) {
                plan = candidate.plan
            }
        }
        if UserDefaults.standard.bool(forKey: persistedBeamKey) {
            var draft = StructuralCreationDraft()
            draft.beginBeam()
            draft.place(.init(x: 0.5, y: 1.5))
            draft.place(.init(x: 3.5, y: 1.5))
            draft.widthMillimeters = "250"
            draft.depthMillimeters = "400"
            if case .success(let candidate) = StructuralCreationEngine().candidate(
                from: draft, in: plan, id: beamID
            ) {
                plan = candidate.plan
            }
        }
        return plan
    }
}
#endif
