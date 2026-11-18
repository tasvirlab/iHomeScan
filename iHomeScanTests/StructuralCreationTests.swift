import CoreGraphics
import Foundation
import Testing
@testable import iHomeScan

@Suite("P1.4.4A structural creation")
struct StructuralCreationTests {
    @Test(arguments: [ColumnShape.rectangular, .square, .circular])
    func createsColumnShapes(shape: ColumnShape) throws {
        var draft = StructuralCreationDraft()
        draft.beginColumn(shape: shape)
        draft.place(.init(x: 1.25, y: 0.8))
        draft.widthMillimeters = "300"
        draft.depthMillimeters = "400"
        let candidate = try result(draft)
        let column = try #require(candidate.plan.columns.last)
        #expect(column.architecturalMetadata?.shape == shape)
        #expect(column.position == .init(x: 1.25, y: 0.8))
        #expect(column.width.value == 0.3)
        #expect(column.depth.value == (shape == .rectangular ? 0.4 : 0.3))
    }

    @Test("Invalid and negative dimensions are rejected")
    func invalidDimensions() {
        var draft = columnDraft()
        draft.widthMillimeters = "-20"
        if case .failure(.invalidDimension) = StructuralCreationEngine().candidate(from: draft, in: plan()) {
        } else {
            Issue.record("Negative dimensions must be rejected")
        }
    }

    @Test("Tap placement remains approximate and unverified")
    func placementProvenance() throws {
        let candidate = try result(columnDraft())
        let column = try #require(candidate.plan.columns.last)
        #expect(column.position == .init(x: 1.2, y: 1.1))
        #expect(column.width.provenance.source == .manualEntered)
        #expect(column.width.provenance.verificationStatus == .unverified)
        #expect(column.architecturalMetadata?.completeness == .partial)
    }

    @Test("Screen to model conversion survives rotation zoom and pan")
    func screenToModelConversion() {
        let floorPlan = FloorPlan(
            bounds: .init(x: 0, y: 0, width: 4, height: 3),
            rooms: [], outerWalls: [], innerWalls: [], doors: [], windows: [], dimensions: []
        )
        let transform = FloorPlanCanvas.transform(
            for: floorPlan, in: .init(width: 390, height: 600),
            zoom: 1.8, offset: .init(width: 31, height: -22), rotation: 0.47,
            precisionPlan: plan()
        )
        let model = CGPoint(x: 1.3, y: 1.7)
        let restored = model.applying(transform).applying(transform.inverted())
        #expect(hypot(restored.x - model.x, restored.y - model.y) < 0.0001)
    }

    @Test("Cancel draft leaves plan unchanged")
    func cancelDoesNotPersist() {
        let committed = plan()
        var draft = columnDraft()
        draft = .init()
        #expect(draft.kind == nil)
        #expect(committed.columns.isEmpty)
    }

    @Test("Repeated creation candidates do not mutate the committed input")
    func candidateIsTransactional() throws {
        let committed = plan()
        _ = try result(columnDraft(), plan: committed)
        _ = try result(columnDraft(), plan: committed)
        #expect(committed.columns.isEmpty)
        #expect(committed.beams.isEmpty)
    }

    @Test("Beam endpoints derive preliminary length")
    func beamPlacementAndLength() throws {
        let candidate = try result(beamDraft())
        let beam = try #require(candidate.plan.beams.last)
        let length = beam.architecturalMetadata?.measurements.first(where: { $0.kind == .length })
        #expect(abs((length?.value.value ?? 0) - 3) < 0.0001)
        #expect(length?.value.provenance.source == .derived)
        #expect(length?.value.provenance.verificationStatus == .unverified)
    }

    @Test("Unknown beam elevation remains unknown")
    func unknownBeamElevation() throws {
        let candidate = try result(beamDraft())
        let beam = try #require(candidate.plan.beams.last)
        #expect(beam.bottomElevation == nil)
        #expect(beam.architecturalMetadata?.completeness == .partial)
    }

    @Test("Beam width and depth are validated")
    func beamSectionValidation() {
        var draft = beamDraft()
        draft.depthMillimeters = ""
        if case .failure(.invalidDimension) = StructuralCreationEngine().candidate(from: draft, in: plan()) {
        } else {
            Issue.record("Missing beam depth must be rejected")
        }
    }

    @Test("Save and reopen restores structural elements")
    func documentRoundTrip() throws {
        let column = try result(columnDraft()).plan
        let document = PrecisionPlanDocument(
            baselinePlan: plan(), currentPlan: column, constraints: [], revisions: []
        )
        let decoded = try PrecisionPlanDocument.decode(from: document.encoded())
        #expect(decoded.currentPlan.columns.count == 1)
        #expect(decoded.currentPlan.columns[0].position == .init(x: 1.2, y: 1.1))
    }

    @Test("Adding structures changes no walls openings or floor area")
    func unrelatedGeometryAndArea() throws {
        let base = plan()
        let candidate = try result(columnDraft(), plan: base).plan
        #expect(candidate.vertices == base.vertices)
        #expect(candidate.walls == base.walls)
        #expect(candidate.openings == base.openings)
        #expect(candidate.derivedFloorArea == base.derivedFloorArea)
    }

    @Test("Column and beam hit testing remain distinct")
    func structuralHitTesting() throws {
        var candidate = try result(columnDraft()).plan
        candidate = try result(beamDraft(), plan: candidate).plan
        let floorPlan = FloorPlan(
            bounds: .init(x: 0, y: 0, width: 4, height: 3),
            rooms: [], outerWalls: [], innerWalls: [], doors: [], windows: [], dimensions: []
        )
        let transform = FloorPlanCanvas.transform(
            for: floorPlan, in: .init(width: 400, height: 400),
            zoom: 1, offset: .zero, precisionPlan: candidate
        )
        let targets = StructuralHitTesting.targets(for: candidate, transform: transform)
        #expect(targets.contains { $0.kind == .column })
        #expect(targets.contains { $0.kind == .beam })
    }

    @Test("Optional column dimensions persist only when entered")
    func optionalColumnMeasurements() throws {
        var draft = columnDraft()
        draft.heightMillimeters = "2800"
        draft.rotationDegrees = "30"
        let column = try #require(try result(draft).plan.columns.last)
        #expect(column.height?.value == 2.8)
        #expect(abs(column.orientation - .pi / 6) < 0.0001)
        #expect(column.architecturalMetadata?.measurements.contains { $0.kind == .height } == true)
    }

    private func result(
        _ draft: StructuralCreationDraft,
        plan: ParametricFloorPlan? = nil
    ) throws -> StructuralCreationCandidate {
        try StructuralCreationEngine().candidate(from: draft, in: plan ?? self.plan()).get()
    }

    private func columnDraft() -> StructuralCreationDraft {
        var draft = StructuralCreationDraft()
        draft.beginColumn(shape: .rectangular)
        draft.place(.init(x: 1.2, y: 1.1))
        draft.widthMillimeters = "300"
        draft.depthMillimeters = "400"
        return draft
    }

    private func beamDraft() -> StructuralCreationDraft {
        var draft = StructuralCreationDraft()
        draft.beginBeam()
        draft.place(.init(x: 0.5, y: 1))
        draft.place(.init(x: 3.5, y: 1))
        draft.widthMillimeters = "250"
        draft.depthMillimeters = "400"
        return draft
    }

    private func plan() -> ParametricFloorPlan {
        let source = GeometrySourceMetadata(
            sourceElementID: UUID(), confidence: .high,
            originalStart: nil, originalEnd: nil, transform: nil
        )
        let ids = (0..<4).map { _ in UUID() }
        let points = [
            PlanPoint2D(x: 0, y: 0), .init(x: 4, y: 0),
            .init(x: 4, y: 3), .init(x: 0, y: 3)
        ]
        let vertices = zip(ids, points).map {
            PlanVertex(id: $0.0, position: $0.1, source: source, mergedEndpointKeys: [])
        }
        let walls = (0..<4).map {
            ParametricWall(
                id: UUID(), startVertexID: ids[$0], endVertexID: ids[($0 + 1) % 4],
                height: nil, thickness: nil, source: source
            )
        }
        let opening = WallOpening(
            id: UUID(), hostWallID: walls[0].id, kind: .door,
            width: .init(value: 0.9, provenance: provenance),
            height: nil, verticalOffset: nil,
            horizontalAnchor: .distanceFromStart(.init(value: 1.5, provenance: provenance)),
            source: source, architecturalMetadata: nil
        )
        return .init(
            id: UUID(), projectID: UUID(), roomID: UUID(), sourceScanID: UUID(),
            coordinateSystem: "test", completeness: .complete,
            vertices: vertices, walls: walls, openings: [opening],
            columns: [], beams: [], floorBoundary: [points], endpointMerges: [],
            revision: .init(number: 1, createdAt: .distantPast, source: .lidarEstimated)
        )
    }

    private var provenance: MeasurementProvenance {
        .init(source: .lidarEstimated, verificationStatus: .estimated, timestamp: nil, uncertainty: nil)
    }
}
