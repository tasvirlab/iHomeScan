import Foundation
import Testing
@testable import iHomeScan

@Suite("P1.4.4B structural properties")
struct StructuralPropertiesEditingTests {
    @Test("Column primary and secondary measurements update transactionally")
    func editsAllColumnProperties() throws {
        let committed = try planWithColumn(shape: .rectangular)
        var draft = StructuralPropertiesDraft.make(column: try #require(committed.columns.first))
        draft.widthMillimeters = "350"
        draft.depthMillimeters = "450"
        draft.positionXMillimeters = "1700"
        draft.positionYMillimeters = "1250"
        draft.rotationDegrees = "30"
        draft.heightMillimeters = "2800"
        draft.baseElevationMillimeters = "100"

        let preview = try StructuralPropertiesEngine().preview(draft: draft, in: committed).get()
        let column = try #require(preview.plan.columns.first)
        #expect(preview.changed)
        #expect(column.id == draft.id)
        #expect(column.width.value == 0.35)
        #expect(column.depth.value == 0.45)
        #expect(column.position == .init(x: 1.7, y: 1.25))
        #expect(abs(column.orientation - .pi / 6) < 0.0001)
        #expect(column.height?.value == 2.8)
        #expect(column.architecturalMetadata?.baseElevation?.value == 0.1)
        #expect(committed.columns.first?.width.value == 0.3)
    }

    @Test("Circular column diameter remains circular")
    func editsCircularDiameter() throws {
        let committed = try planWithColumn(shape: .circular)
        var draft = StructuralPropertiesDraft.make(column: try #require(committed.columns.first))
        draft.widthMillimeters = "420"
        let column = try #require(try StructuralPropertiesEngine().preview(draft: draft, in: committed).get().plan.columns.first)
        #expect(column.width.value == 0.42)
        #expect(column.depth.value == 0.42)
        #expect(column.architecturalMetadata?.measurements.contains { $0.kind == .diameter && $0.value.value == 0.42 } == true)
    }

    @Test("Only changed values receive user-declared laser provenance")
    func contextualLaserProvenance() throws {
        let committed = try planWithColumn(shape: .rectangular)
        let originalDepth = try #require(committed.columns.first?.depth.provenance)
        var draft = StructuralPropertiesDraft.make(column: try #require(committed.columns.first))
        draft.widthMillimeters = "360"
        draft.laserVerified = true
        let column = try #require(try StructuralPropertiesEngine().preview(draft: draft, in: committed).get().plan.columns.first)
        #expect(column.width.provenance.source == .laserVerified)
        #expect(column.width.provenance.verificationStatus == .verified)
        #expect(column.depth.provenance == originalDepth)
    }

    @Test("Beam endpoints, section and elevations update")
    func editsBeamProperties() throws {
        let committed = try planWithBeam()
        let existingBeam = try #require(committed.beams.first)
        var draft = try #require(StructuralPropertiesDraft.make(beam: existingBeam, in: committed))
        draft.startXMillimeters = "600"
        draft.startYMillimeters = "900"
        draft.endXMillimeters = "3600"
        draft.endYMillimeters = "1200"
        draft.widthMillimeters = "300"
        draft.depthMillimeters = "500"
        draft.bottomElevationMillimeters = "2300"
        draft.topElevationMillimeters = "2800"
        let preview = try StructuralPropertiesEngine().preview(draft: draft, in: committed).get()
        let beam = try #require(preview.plan.beams.first)
        #expect(beam.width.value == 0.3)
        #expect(beam.depth.value == 0.5)
        #expect(beam.bottomElevation?.value == 2.3)
        let top = beam.architecturalMetadata?.measurements.first { $0.kind == .topElevation }
        #expect(top?.value.value == 2.8)
        #expect(preview.plan.vertices == committed.vertices)
        #expect(preview.plan.openings == committed.openings)
        #expect(preview.plan.derivedFloorArea == committed.derivedFloorArea)
    }

    @Test("Contradictory beam vertical chain is rejected")
    func rejectsVerticalConflict() throws {
        let committed = try planWithBeam()
        let existingBeam = try #require(committed.beams.first)
        var draft = try #require(StructuralPropertiesDraft.make(beam: existingBeam, in: committed))
        draft.depthMillimeters = "400"
        draft.bottomElevationMillimeters = "2300"
        draft.topElevationMillimeters = "2900"
        if case .failure(.verticalConflict) = StructuralPropertiesEngine().preview(draft: draft, in: committed) {
        } else {
            Issue.record("Contradictory vertical measurements must be rejected")
        }
    }

    @Test("Unchanged draft does not create a revision")
    func unchangedDraft() throws {
        let committed = try planWithColumn(shape: .square)
        let draft = StructuralPropertiesDraft.make(column: try #require(committed.columns.first))
        let preview = try StructuralPropertiesEngine().preview(draft: draft, in: committed).get()
        #expect(!preview.changed)
        #expect(preview.plan.revision == committed.revision)
    }

    @Test("Edited structural data survives JSON reopen")
    func roundTrip() throws {
        let committed = try planWithColumn(shape: .rectangular)
        var draft = StructuralPropertiesDraft.make(column: try #require(committed.columns.first))
        draft.widthMillimeters = "375"
        let edited = try StructuralPropertiesEngine().preview(draft: draft, in: committed).get().plan
        let document = PrecisionPlanDocument(baselinePlan: basePlan(), currentPlan: edited, constraints: [], revisions: [])
        let reopened = try PrecisionPlanDocument.decode(from: document.encoded())
        #expect(reopened.currentPlan.columns.first?.width.value == 0.375)
    }

    private func planWithColumn(shape: ColumnShape) throws -> ParametricFloorPlan {
        var draft = StructuralCreationDraft()
        draft.beginColumn(shape: shape)
        draft.place(.init(x: 1.2, y: 1.1))
        draft.widthMillimeters = "300"
        draft.depthMillimeters = "400"
        return try StructuralCreationEngine().candidate(from: draft, in: basePlan()).get().plan
    }

    private func planWithBeam() throws -> ParametricFloorPlan {
        var draft = StructuralCreationDraft()
        draft.beginBeam()
        draft.place(.init(x: 0.5, y: 1))
        draft.place(.init(x: 3.5, y: 1))
        draft.widthMillimeters = "250"
        draft.depthMillimeters = "400"
        return try StructuralCreationEngine().candidate(from: draft, in: basePlan()).get().plan
    }

    private func basePlan() -> ParametricFloorPlan {
        let source = GeometrySourceMetadata(sourceElementID: UUID(), confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
        let ids = (0..<4).map { _ in UUID() }
        let points: [PlanPoint2D] = [.init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 4, y: 3), .init(x: 0, y: 3)]
        let vertices = zip(ids, points).map { PlanVertex(id: $0.0, position: $0.1, source: source, mergedEndpointKeys: []) }
        let walls = (0..<4).map { ParametricWall(id: UUID(), startVertexID: ids[$0], endVertexID: ids[($0 + 1) % 4], height: nil, thickness: nil, source: source) }
        return .init(id: UUID(), projectID: UUID(), roomID: UUID(), sourceScanID: UUID(), coordinateSystem: "test", completeness: .complete, vertices: vertices, walls: walls, openings: [], columns: [], beams: [], floorBoundary: [points], endpointMerges: [], revision: .init(number: 1, createdAt: .distantPast, source: .lidarEstimated))
    }
}
