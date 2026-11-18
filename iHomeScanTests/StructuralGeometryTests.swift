import Foundation
import Testing
@testable import iHomeScan

@Suite("P1.4.3 structural parametric geometry")
struct StructuralGeometryTests {
    @Test("Rectangular, square and circular columns preserve explicit shape")
    func columnShapes() {
        for shape in [ColumnShape.rectangular, .square, .circular] {
            let plan = fixturePlan(columnShape: shape)
            #expect(plan.columns[0].architecturalMetadata?.shape == shape)
            #expect(ParametricGeometryValidator().validate(plan).isValid)
        }
    }

    @Test("Column width and depth measurements revise geometry")
    func columnDimensionRevision() {
        var plan = fixturePlan()
        let columnID = plan.columns[0].id
        plan.columns[0].architecturalMetadata?.measurements += [
            columnMeasurement(.width, 0.35, columnID: columnID),
            columnMeasurement(.depth, 0.45, columnID: columnID)
        ]
        let result = StructuralGeometryResolver().resolve(plan: plan)
        #expect(abs(result.candidatePlan.columns[0].width.value - 0.35) < 0.0001)
        #expect(abs(result.candidatePlan.columns[0].depth.value - 0.45) < 0.0001)
    }

    @Test("Circular diameter revises both plan dimensions")
    func diameterRevision() {
        var plan = fixturePlan(columnShape: .circular)
        let columnID = plan.columns[0].id
        plan.columns[0].architecturalMetadata?.measurements.append(
            columnMeasurement(.diameter, 0.5, columnID: columnID)
        )
        let column = StructuralGeometryResolver().resolve(plan: plan).candidatePlan.columns[0]
        #expect(column.width.value == 0.5)
        #expect(column.depth.value == 0.5)
    }

    @Test("Two nonparallel wall-face references locate a column")
    func twoWallReferences() {
        let result = StructuralGeometryResolver().resolve(plan: fixturePlan())
        let position = result.columnPlacements.first?.position
        #expect(abs((position?.x ?? 0) - 1.2) < 0.0001)
        #expect(abs((position?.y ?? 0) - 0.75) < 0.0001)
        #expect(result.conflicts.isEmpty)
    }

    @Test("Rotated references resolve in the wall local coordinate system")
    func rotatedReferences() {
        let angle = Double.pi / 5
        var plan = fixturePlan()
        plan.vertices = plan.vertices.map { vertex in
            var copy = vertex
            copy.position = rotate(vertex.position, angle: angle)
            return copy
        }
        let position = StructuralGeometryResolver().resolve(plan: plan).columnPlacements.first?.position
        let expected = rotate(.init(x: 1.2, y: 0.75), angle: angle)
        #expect((position?.distance(to: expected) ?? 1) < 0.0001)
    }

    @Test("Irregular room walls do not affect referenced placement")
    func irregularRoom() {
        var plan = fixturePlan()
        plan.floorBoundary = [[.init(x: 0, y: 0), .init(x: 4.25, y: 0), .init(x: 4, y: 2),
                               .init(x: 2, y: 2), .init(x: 2, y: 3.1), .init(x: 0, y: 3.1)]]
        let position = StructuralGeometryResolver().resolve(plan: plan).columnPlacements.first?.position
        #expect(position == .init(x: 1.2, y: 0.75))
    }

    @Test("Column rotation is preserved unless explicitly measured")
    func rotationPreservation() {
        var plan = fixturePlan()
        plan.columns[0].orientation = 0.37
        #expect(StructuralGeometryResolver().resolve(plan: plan).candidatePlan.columns[0].orientation == 0.37)
        let columnID = plan.columns[0].id
        plan.columns[0].architecturalMetadata?.measurements.append(
            columnMeasurement(.rotation, .pi / 4, unit: .radians, columnID: columnID)
        )
        #expect(abs(StructuralGeometryResolver().resolve(plan: plan).candidatePlan.columns[0].orientation - .pi / 4) < 0.0001)
    }

    @Test("Unknown reference remains unresolved")
    func unknownReference() {
        var plan = fixturePlan()
        let referenceID = plan.columns[0].architecturalMetadata!.references[0].id
        plan.columns[0].architecturalMetadata?.references[0] = .init(
            id: referenceID,
            entity: .unresolved,
            reliability: .unresolved
        )
        let result = StructuralGeometryResolver().resolve(plan: plan)
        #expect(result.unresolvedEntityIDs.contains(plan.columns[0].id))
        #expect(result.conflicts.isEmpty)
    }

    @Test("One reference is explicitly underdetermined")
    func underdeterminedPlacement() {
        var plan = fixturePlan()
        plan.columns[0].architecturalMetadata?.measurements.removeLast()
        let result = StructuralGeometryResolver().resolve(plan: plan)
        #expect(result.columnPlacements.isEmpty)
        #expect(result.unresolvedEntityIDs == [plan.columns[0].id])
    }

    @Test("Contradictory verified parallel offsets are reported")
    func contradictoryReferences() {
        var plan = fixturePlan()
        let firstReference = plan.columns[0].architecturalMetadata!.references[0]
        let duplicateReference = StructuralReference(
            id: UUID(), entity: firstReference.entity, reliability: .verified
        )
        plan.columns[0].architecturalMetadata?.references = [firstReference, duplicateReference]
        let columnID = plan.columns[0].id
        plan.columns[0].architecturalMetadata?.measurements = [
            columnMeasurement(.offset, 0.75, columnID: columnID, referenceID: firstReference.id, verified: true),
            columnMeasurement(.offset, 1.0, columnID: columnID, referenceID: duplicateReference.id, verified: true)
        ]
        #expect(StructuralGeometryResolver().resolve(plan: plan).conflicts.contains {
            $0.code == .contradictoryReferences
        })
    }

    @Test("Beam length, rotation and endpoint references are geometric")
    func beamGeometry() {
        let result = StructuralGeometryResolver().resolve(plan: fixturePlan())
        let beam = result.beamGeometries.first
        #expect(abs((beam?.length.value ?? 0) - 4.25) < 0.0001)
        #expect(abs((beam?.topElevation?.value ?? 0) - 2.7) < 0.0001)
        #expect(beam?.topElevation?.provenance.source == .derived)
    }

    @Test("Beam bottom plus depth derives top elevation")
    func beamVerticalChain() {
        let beam = StructuralGeometryResolver().resolve(plan: fixturePlan()).beamGeometries[0]
        #expect(abs((beam.topElevation?.value ?? 0) - (2.3 + 0.4)) < 0.0001)
    }

    @Test("Beam section and bottom elevation measurements revise geometry")
    func beamDimensionRevision() {
        var plan = fixturePlan()
        let beamID = plan.beams[0].id
        plan.beams[0].architecturalMetadata?.measurements += [
            beamMeasurement(.width, 0.3, beamID: beamID),
            beamMeasurement(.depth, 0.45, beamID: beamID),
            beamMeasurement(.bottomElevation, 2.2, beamID: beamID)
        ]
        let beam = StructuralGeometryResolver().resolve(plan: plan).candidatePlan.beams[0]
        #expect(beam.width.value == 0.3)
        #expect(beam.depth.value == 0.45)
        #expect(beam.bottomElevation?.value == 2.2)
    }

    @Test("Verified beam length conflict is protected")
    func verifiedBeamLengthConflict() {
        var plan = fixturePlan()
        let beamID = plan.beams[0].id
        plan.beams[0].architecturalMetadata?.measurements.append(
            beamMeasurement(.length, 4.0, beamID: beamID, verified: true)
        )
        #expect(StructuralGeometryResolver().resolve(plan: plan).conflicts.contains {
            $0.code == .verifiedMeasurementConflict
        })
    }

    @Test("Invalid beam vertical chain is rejected")
    func invalidVerticalChain() {
        var plan = fixturePlan()
        let beamID = plan.beams[0].id
        plan.beams[0].architecturalMetadata?.measurements.append(
            beamMeasurement(.topElevation, 2.9, beamID: beamID, verified: true)
        )
        #expect(StructuralGeometryResolver().resolve(plan: plan).conflicts.contains {
            $0.code == .invalidVerticalChain
        })
    }

    @Test("Unknown support relationship remains unknown")
    func unknownSupport() {
        let metadata = fixturePlan().beams[0].architecturalMetadata
        #expect(metadata?.verifiedSupportEntityIDs == nil)
    }

    @Test("Unresolved beam endpoint remains representable")
    func unresolvedBeamEndpoint() {
        var plan = fixturePlan()
        plan.beams[0].start = .unresolved
        plan.beams[0].architecturalMetadata?.startReference = .init(entity: .unresolved, reliability: .unresolved)
        let result = StructuralGeometryResolver().resolve(plan: plan)
        #expect(result.unresolvedEntityIDs.contains(plan.beams[0].id))
        #expect(ParametricGeometryValidator().validate(plan).warnings.contains { $0.code == .incompleteStructuralGeometry })
    }

    @Test("Wall length revision preserves verified column offsets")
    func wallRevisionIntegration() {
        let plan = fixturePlan()
        let original = StructuralGeometryResolver().resolve(plan: plan).columnPlacements[0].position
        let command = SetWallLengthCommand(
            id: UUID(), wallID: plan.walls[0].id, targetLength: 4.5, anchor: .keepStart,
            provenance: provenance(.manualEntered, .unverified), createdAt: .now
        )
        let result = GeometryConstraintSolver().preview(command: command, plan: plan, constraints: [])
        guard case .solved(let transaction, _) = result else {
            Issue.record("Compatible wall revision should solve")
            return
        }
        #expect(transaction.candidatePlan.columns[0].position.distance(to: original) < 0.0001)
    }

    @Test("Structural resolution changes no unrelated walls or openings")
    func unrelatedGeometry() {
        let plan = fixturePlan()
        let result = StructuralGeometryResolver().resolve(plan: plan)
        #expect(result.candidatePlan.vertices == plan.vertices)
        #expect(result.candidatePlan.walls == plan.walls)
        #expect(result.candidatePlan.openings == plan.openings)
    }

    @Test("Columns do not alter authoritative floor area")
    func floorAreaCompatibility() {
        let plan = fixturePlan()
        let area = plan.derivedFloorArea
        #expect(StructuralGeometryResolver().resolve(plan: plan).candidatePlan.derivedFloorArea == area)
        #expect(area == 13.175)
    }

    @Test("Valid wall/column overlap is not rejected")
    func structuralOverlap() {
        var plan = fixturePlan()
        plan.columns[0].position = .init(x: 0, y: 0.2)
        plan.columns[0].architecturalMetadata = nil
        #expect(ParametricGeometryValidator().validate(plan).isValid)
    }

    @Test("Structural metadata survives JSON save and reopen")
    func jsonRoundTrip() throws {
        let plan = fixturePlan()
        let decoded = try ParametricFloorPlan.decode(from: plan.encoded())
        #expect(decoded.columns == plan.columns)
        #expect(decoded.beams == plan.beams)
    }

    @Test("Precision document preserves structural metadata without a format bump")
    func precisionDocumentRoundTrip() throws {
        let plan = fixturePlan()
        let document = PrecisionPlanDocument(
            baselinePlan: plan, currentPlan: plan, constraints: [], revisions: []
        )
        let decoded = try PrecisionPlanDocument.decode(from: document.encoded())
        #expect(decoded.formatVersion == PrecisionPlanDocument.currentFormatVersion)
        #expect(decoded.currentPlan.columns == plan.columns)
        #expect(decoded.currentPlan.beams == plan.beams)
    }

    @Test("Legacy JSON without structural metadata remains readable")
    func legacyJSON() throws {
        let plan = fixturePlan()
        let object = try JSONSerialization.jsonObject(with: plan.encoded()) as! [String: Any]
        var legacy = object
        legacy["columns"] = (object["columns"] as! [[String: Any]]).map { value in
            var value = value; value.removeValue(forKey: "architecturalMetadata"); return value
        }
        legacy["beams"] = (object["beams"] as! [[String: Any]]).map { value in
            var value = value; value.removeValue(forKey: "architecturalMetadata"); return value
        }
        let decoded = try ParametricFloorPlan.decode(from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.columns[0].architecturalMetadata == nil)
        #expect(decoded.beams[0].architecturalMetadata == nil)
    }

    @Test("Invalid measurements do not mutate committed geometry")
    func atomicRollback() {
        var plan = fixturePlan()
        let committed = plan
        let beamID = plan.beams[0].id
        plan.beams[0].architecturalMetadata?.measurements.append(
            beamMeasurement(.topElevation, .nan, beamID: beamID, verified: true)
        )
        let result = StructuralGeometryResolver().resolve(plan: plan)
        #expect(!result.isValid)
        #expect(committed.beams[0].bottomElevation?.value == 2.3)
        #expect(committed.vertices == plan.vertices)
    }

    private func fixturePlan(columnShape: ColumnShape = .rectangular) -> ParametricFloorPlan {
        let source = GeometrySourceMetadata(sourceElementID: UUID(), confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
        let vertexIDs = (0..<4).map { _ in UUID() }
        let points = [PlanPoint2D(x: 0, y: 0), .init(x: 4.25, y: 0), .init(x: 4.25, y: 3.1), .init(x: 0, y: 3.1)]
        let vertices = zip(vertexIDs, points).map { PlanVertex(id: $0.0, position: $0.1, source: source, mergedEndpointKeys: []) }
        let walls = [
            ParametricWall(id: UUID(), startVertexID: vertexIDs[0], endVertexID: vertexIDs[1], height: nil, thickness: nil, source: source),
            ParametricWall(id: UUID(), startVertexID: vertexIDs[1], endVertexID: vertexIDs[2], height: nil, thickness: nil, source: source),
            ParametricWall(id: UUID(), startVertexID: vertexIDs[2], endVertexID: vertexIDs[3], height: nil, thickness: nil, source: source),
            ParametricWall(id: UUID(), startVertexID: vertexIDs[3], endVertexID: vertexIDs[0], height: nil, thickness: nil, source: source)
        ]
        let firstReference = StructuralReference(id: UUID(), entity: .wall(wallID: walls[0].id, face: .centerline, side: .positive), reliability: .verified)
        let secondReference = StructuralReference(id: UUID(), entity: .wall(wallID: walls[3].id, face: .centerline, side: .positive), reliability: .verified)
        let columnID = UUID()
        let size = columnShape == .circular ? 0.3 : 0.3
        let column = ParametricColumn(
            id: columnID, position: .init(x: 1.2, y: 0.75),
            width: length(size), depth: length(columnShape == .rectangular ? 0.4 : size),
            height: length(2.8), orientation: 0, referenceVertexIDs: [],
            architecturalMetadata: .init(
                shape: columnShape,
                measurements: [
                    columnMeasurement(.offset, 0.75, columnID: columnID, referenceID: firstReference.id, verified: true),
                    columnMeasurement(.offset, 1.2, columnID: columnID, referenceID: secondReference.id, verified: true)
                ],
                references: [firstReference, secondReference], baseElevation: nil,
                completeness: .partial, source: source
            )
        )
        let beamID = UUID()
        let beam = ParametricBeam(
            id: beamID, start: .vertex(vertexIDs[0]), end: .vertex(vertexIDs[1]),
            width: length(0.25), depth: length(0.4), bottomElevation: length(2.3),
            architecturalMetadata: .init(
                measurements: [], references: [],
                startReference: .init(entity: .vertex(vertexIDs[0]), reliability: .verified),
                endReference: .init(entity: .vertex(vertexIDs[1]), reliability: .verified),
                verifiedSupportEntityIDs: nil, completeness: .partial, source: source
            )
        )
        let opening = WallOpening(
            id: UUID(), hostWallID: walls[0].id, kind: .door,
            width: length(0.9), height: length(2.1), verticalOffset: length(0),
            horizontalAnchor: .distanceFromStart(length(2.0)), source: source,
            architecturalMetadata: nil
        )
        return ParametricFloorPlan(
            id: UUID(), projectID: UUID(), roomID: UUID(), sourceScanID: UUID(),
            coordinateSystem: "test", completeness: .complete,
            vertices: vertices, walls: walls, openings: [opening], columns: [column], beams: [beam],
            floorBoundary: [points], endpointMerges: [],
            revision: .init(number: 1, createdAt: .init(timeIntervalSince1970: 0), source: .manualEntered)
        )
    }

    private func columnMeasurement(
        _ kind: ColumnMeasurementKind,
        _ value: Double,
        unit: StructuralMeasurementUnit = .meters,
        columnID: UUID = UUID(),
        referenceID: UUID? = nil,
        verified: Bool = false
    ) -> ColumnMeasurement {
        .init(id: UUID(), columnID: columnID, kind: kind,
              value: .init(value: value, unit: unit,
                           provenance: provenance(verified ? .laserVerified : .manualEntered,
                                                  verified ? .verified : .unverified)),
              referenceID: referenceID)
    }

    private func beamMeasurement(
        _ kind: BeamMeasurementKind,
        _ value: Double,
        beamID: UUID,
        verified: Bool = false
    ) -> BeamMeasurement {
        .init(id: UUID(), beamID: beamID, kind: kind,
              value: .init(value: value, unit: .meters,
                           provenance: provenance(verified ? .laserVerified : .manualEntered,
                                                  verified ? .verified : .unverified)),
              referenceID: nil)
    }

    private func length(_ value: Double) -> LengthMeasurement {
        .init(value: value, provenance: provenance(.lidarEstimated, .estimated))
    }

    private func provenance(_ source: GeometrySourceKind, _ status: GeometryVerificationStatus) -> MeasurementProvenance {
        .init(source: source, verificationStatus: status, timestamp: nil, uncertainty: nil)
    }

    private func rotate(_ point: PlanPoint2D, angle: Double) -> PlanPoint2D {
        .init(x: point.x * cos(angle) - point.y * sin(angle),
              y: point.x * sin(angle) + point.y * cos(angle))
    }
}
