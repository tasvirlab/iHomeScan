import Foundation
import Testing
@testable import iHomeScan

@MainActor
@Suite("P1.4.1 opening measurement resolution")
struct OpeningMeasurementResolverTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "B0000000-0000-0000-0000-%012d", value))!
    }

    private var source: GeometrySourceMetadata {
        .init(sourceElementID: id(999), confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
    }

    private func provenance(
        _ source: GeometrySourceKind = .manualEntered,
        _ status: GeometryVerificationStatus = .unverified,
        uncertainty: Double? = nil
    ) -> MeasurementProvenance {
        .init(source: source, verificationStatus: status, timestamp: date, uncertainty: uncertainty)
    }

    private func measurement(
        _ index: Int,
        openingID: UUID,
        kind: OpeningMeasurementKind,
        value: Double,
        source: GeometrySourceKind = .manualEntered,
        status: GeometryVerificationStatus = .unverified,
        reference: OpeningMeasurementReference? = nil,
        uncertainty: Double? = nil
    ) -> OpeningMeasurement {
        .init(
            id: id(500 + index), openingID: openingID, kind: kind,
            value: .init(value: value, provenance: provenance(source, status, uncertainty: uncertainty)),
            reference: reference, relatedConstraintIDs: []
        )
    }

    private func opening(
        _ index: Int = 0,
        hostWallID: UUID? = nil,
        kind: WallOpeningKind = .door,
        center: Double = 1.1,
        width: Double? = 0.9,
        height: Double? = nil,
        verticalOffset: Double? = nil,
        measurements: [OpeningMeasurement] = [],
        completeness: OpeningGeometryCompleteness = .complete,
        swing: DoorSwingMetadata? = nil
    ) -> WallOpening {
        let openingID = id(200 + index)
        return WallOpening(
            id: openingID, hostWallID: hostWallID ?? id(100), kind: kind,
            width: width.map { .init(value: $0, provenance: provenance(.lidarEstimated, .estimated)) },
            height: height.map { .init(value: $0, provenance: provenance(.lidarEstimated, .estimated)) },
            verticalOffset: verticalOffset.map { .init(value: $0, provenance: provenance(.lidarEstimated, .estimated)) },
            horizontalAnchor: .distanceFromStart(.init(value: center, provenance: provenance(.lidarEstimated, .estimated))),
            source: source,
            architecturalMetadata: .init(measurements: measurements, completeness: completeness, doorSwing: swing)
        )
    }

    private func replacingMeasurements(_ opening: WallOpening, _ measurements: [OpeningMeasurement]) -> WallOpening {
        WallOpening(
            id: opening.id, hostWallID: opening.hostWallID, kind: opening.kind,
            width: opening.width, height: opening.height, verticalOffset: opening.verticalOffset,
            horizontalAnchor: opening.horizontalAnchor, source: opening.source,
            architecturalMetadata: .init(
                measurements: measurements,
                completeness: opening.architecturalMetadata?.completeness ?? .partial,
                doorSwing: opening.architecturalMetadata?.doorSwing
            )
        )
    }

    private func plan(
        length: Double = 4.25,
        start: PlanPoint2D = .init(x: 0, y: 0),
        direction: PlanPoint2D = .init(x: 1, y: 0),
        openings: [WallOpening],
        completeness: ParametricGeometryCompleteness = .complete,
        wallHeight: Double? = 2.8
    ) -> ParametricFloorPlan {
        let end = PlanPoint2D(x: start.x + direction.x * length, y: start.y + direction.y * length)
        return ParametricFloorPlan(
            id: id(1), projectID: id(2), roomID: id(3), sourceScanID: id(4),
            coordinateSystem: "meters", completeness: completeness,
            vertices: [
                .init(id: id(10), position: start, source: source, mergedEndpointKeys: []),
                .init(id: id(11), position: end, source: source, mergedEndpointKeys: [])
            ],
            walls: [.init(
                id: id(100), startVertexID: id(10), endVertexID: id(11),
                height: wallHeight.map { .init(value: $0, provenance: provenance(.lidarEstimated, .estimated)) },
                thickness: .init(value: 0.18, provenance: provenance(.lidarEstimated, .estimated)), source: source
            )],
            openings: openings, columns: [], beams: [], floorBoundary: nil, endpointMerges: [],
            revision: .init(number: 7, createdAt: date, source: .manualEntered)
        )
    }

    private func resolved(_ plan: ParametricFloorPlan) throws -> (OpeningMeasurementResolution, ResolvedOpeningPlacement) {
        let result = OpeningMeasurementResolver().resolve(plan: plan)
        #expect(result.conflicts.isEmpty)
        return (result, try #require(result.placements.first))
    }

    private func wallCommand(wallID: UUID, target: Double) -> SetWallLengthCommand {
        .init(
            id: id(800), wallID: wallID, targetLength: target, anchor: .keepStart,
            provenance: provenance(.manualEntered, .unverified), createdAt: date
        )
    }

    @Test("01. Wall with one door resolves")
    func oneDoor() throws { #expect(try resolved(plan(openings: [opening()])).1.width == 0.9) }

    @Test("02. Start offset locates near edge")
    func startOffset() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65)])
        #expect(abs(try resolved(plan(openings: [item])).1.startOffset - 0.65) < 0.000_1)
    }

    @Test("03. End offset locates opening")
    func endOffset() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromEnd, value: 2.7)])
        #expect(abs(try resolved(plan(openings: [item])).1.startOffset - 0.65) < 0.000_1)
    }

    @Test("04. Manual width replaces LiDAR width")
    func widthRevision() throws {
        var item = opening(width: 0.88)
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .width, value: 0.9)])
        #expect(try resolved(plan(openings: [item])).1.width == 0.9)
    }

    @Test("05. Remaining distance is derived")
    func derivedRemaining() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65)])
        #expect(abs(try resolved(plan(openings: [item])).1.endOffset - 2.7) < 0.000_1)
    }

    @Test("06. Horizontal chain equals wall length")
    func chainSum() throws {
        let placement = try resolved(plan(openings: [opening()])).1
        #expect(abs(placement.startOffset + placement.width + placement.endOffset - 4.25) < 0.000_1)
    }

    @Test("07. Two windows share one wall")
    func twoWindows() throws {
        let a = opening(0, kind: .window, center: 1, width: 0.8)
        let b = opening(1, kind: .window, center: 3, width: 0.8)
        #expect(OpeningMeasurementResolver().resolve(plan: plan(openings: [a, b])).placements.count == 2)
    }

    @Test("08. Door and window coexist")
    func doorAndWindow() {
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [opening(0), opening(1, kind: .window, center: 3)]))
        #expect(result.conflicts.isEmpty)
    }

    @Test("09. Gap between openings is geometric")
    func openingGap() throws {
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [opening(0, center: 1), opening(1, center: 3)]))
        #expect(abs((try #require(result.gaps.first)).distance - 1.1) < 0.000_1)
        #expect(result.derivedMeasurements.contains {
            $0.kind == .gapToNextOpening && $0.relatedOpeningID == id(201)
        })
    }

    @Test("10. Openings resolve in physical order")
    func ordering() {
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [opening(1, center: 3), opening(0, center: 1)]))
        #expect(result.placements.sorted { $0.startOffset < $1.startOffset }.map(\.openingID) == [id(200), id(201)])
    }

    @Test("11. Overlap is rejected")
    func overlap() {
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [opening(0, center: 1), opening(1, center: 1.4)]))
        #expect(result.conflicts.contains { $0.code == .overlappingOpenings })
    }

    @Test("12. Rotated host wall uses local distance")
    func rotatedWall() throws {
        let direction = PlanPoint2D(x: cos(.pi / 6), y: sin(.pi / 6))
        #expect(abs(try resolved(plan(direction: direction, openings: [opening()])).1.centerOffset - 1.1) < 0.000_1)
    }

    @Test("13. Diagonal host wall uses local distance")
    func diagonalWall() throws {
        let unit = 1 / sqrt(2.0)
        #expect(try resolved(plan(direction: .init(x: unit, y: unit), openings: [opening()])).1.width == 0.9)
    }

    @Test("14. Reversed host transforms start/end semantics")
    func endReference() throws {
        var item = opening()
        let reference = OpeningMeasurementReference(endpoint: .wallStart, vertexID: id(10), reliability: .verified)
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, status: .verified, reference: reference)])
        let reversed = OpeningMeasurementResolver().reversingHostDirection(of: item, wallLength: 4.25)
        #expect(reversed.architecturalMetadata?.measurements.first?.kind == .offsetFromEnd)
        #expect(reversed.architecturalMetadata?.measurements.first?.reference?.endpoint == .wallEnd)
        if case .distanceFromStart(let center) = reversed.horizontalAnchor {
            #expect(abs(center.value - 3.15) < 0.000_1)
        }
    }

    @Test("15. Partial scan remains supported")
    func partialScan() { #expect(OpeningMeasurementResolver().resolve(plan: plan(openings: [opening()], completeness: .partial)).isValid) }

    @Test("16. Host resolution is independent of room shape")
    func irregularRoomHost() throws { #expect(try resolved(plan(start: .init(x: 2, y: 3), openings: [opening()])).1.hostWallID == id(100)) }

    @Test("17. Longer wall preserves verified start offset")
    func wallGrowth() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, source: .laserVerified, status: .verified)])
        #expect(try resolved(plan(length: 5, openings: [item])).1.startOffset == 0.65)
    }

    @Test("18. Wall correction recalculates derived end")
    func wallCorrectionDerivedEnd() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65)])
        #expect(abs(try resolved(plan(length: 5, openings: [item])).1.endOffset - 3.45) < 0.000_1)
    }

    @Test("19. Short wall rejects layout")
    func shortenedWall() {
        let result = OpeningMeasurementResolver().resolve(plan: plan(length: 1, openings: [opening(center: 0.8, width: 0.9)]))
        #expect(result.conflicts.contains {
            $0.code == .contradictoryMeasurements || $0.code == .outsideHostWall || $0.code == .invalidMeasurement
        })
    }

    @Test("20. Resolver never changes wall vertices")
    func unrelatedGeometry() {
        let input = plan(openings: [opening()])
        let result = OpeningMeasurementResolver().resolve(plan: input)
        #expect(result.candidatePlan.vertices == input.vertices)
    }

    @Test("21. Manual measurement outranks LiDAR")
    func manualReplacesLidar() throws {
        var item = opening()
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .width, value: 0.88, source: .lidarEstimated, status: .estimated),
            measurement(2, openingID: item.id, kind: .width, value: 0.91)
        ])
        #expect(try resolved(plan(openings: [item])).1.width == 0.91)
    }

    @Test("22. User declared laser verification survives")
    func laserVerification() throws {
        var item = opening()
        let laser = measurement(1, openingID: item.id, kind: .width, value: 0.9, source: .laserVerified, status: .verified)
        item = replacingMeasurements(item, [laser])
        let candidate = try resolved(plan(openings: [item])).0.candidatePlan.openings[0]
        #expect(candidate.width?.provenance == laser.value.provenance)
    }

    @Test("23. Verified offset is preserved")
    func verifiedOffset() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, status: .verified)])
        #expect(try resolved(plan(openings: [item])).1.startOffset == 0.65)
    }

    @Test("24. Verified width is preserved")
    func verifiedWidth() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .width, value: 0.9, status: .verified)])
        #expect(try resolved(plan(openings: [item])).1.width == 0.9)
    }

    @Test("25. Derived distance is never verified")
    func derivedNotVerified() throws {
        let result = try resolved(plan(openings: [opening()])).0
        #expect(result.derivedMeasurements.allSatisfy { $0.value.provenance.verificationStatus != .verified })
    }

    @Test("26. Conflicting verified chain is reported")
    func verifiedChainConflict() {
        var item = opening()
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, status: .verified),
            measurement(2, openingID: item.id, kind: .width, value: 0.9, status: .verified),
            measurement(3, openingID: item.id, kind: .offsetFromEnd, value: 2.75, status: .verified)
        ])
        #expect(OpeningMeasurementResolver().resolve(plan: plan(openings: [item])).conflicts.contains { $0.code == .contradictoryMeasurements })
    }

    @Test("27. Missing width and one edge stays unresolved")
    func underdetermined() {
        let item = opening(width: nil)
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [item]))
        #expect(result.unresolvedOpeningIDs == [item.id])
        #expect(result.conflicts.isEmpty)
    }

    @Test("28. Negative measurement is rejected")
    func negativeMeasurement() {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .offsetFromStart, value: -1)])
        #expect(OpeningMeasurementResolver().resolve(plan: plan(openings: [item])).conflicts.contains { $0.code == .invalidMeasurement })
    }

    @Test("29. Nonfinite measurement is rejected")
    func nonfiniteMeasurement() {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .width, value: .infinity)])
        #expect(!OpeningMeasurementResolver().resolve(plan: plan(openings: [item])).isValid)
    }

    @Test("30. Physical uncertainty remains metadata")
    func uncertainty() {
        let value = measurement(1, openingID: id(200), kind: .width, value: 0.9, uncertainty: 0.002)
        #expect(value.value.provenance.uncertainty == 0.002)
    }

    @Test("31. Window sill plus height derives top")
    func windowVerticalChain() throws {
        var item = opening(kind: .window, height: nil, verticalOffset: nil)
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .sillElevation, value: 0.9),
            measurement(2, openingID: item.id, kind: .height, value: 1.4)
        ])
        #expect(abs((try resolved(plan(openings: [item])).1.topElevation ?? 0) - 2.3) < 0.000_1)
    }

    @Test("32. Door threshold and height derive top")
    func doorVerticalChain() throws {
        var item = opening(height: nil, verticalOffset: nil)
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .thresholdElevation, value: 0),
            measurement(2, openingID: item.id, kind: .height, value: 2.1)
        ])
        #expect(try resolved(plan(openings: [item])).1.topElevation == 2.1)
    }

    @Test("33. Vertical contradiction is reported")
    func verticalConflict() {
        var item = opening(kind: .window, height: nil, verticalOffset: nil)
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .sillElevation, value: 0.9, status: .verified),
            measurement(2, openingID: item.id, kind: .height, value: 1.4, status: .verified),
            measurement(3, openingID: item.id, kind: .topElevation, value: 2.4, status: .verified)
        ])
        #expect(OpeningMeasurementResolver().resolve(plan: plan(openings: [item])).conflicts.contains { $0.code == .invalidVerticalChain })
    }

    @Test("34. Unknown vertical dimensions remain unknown")
    func unknownVertical() throws {
        let placement = try resolved(plan(openings: [opening(height: nil, verticalOffset: nil)])).1
        #expect(placement.lowerElevation == nil && placement.height == nil && placement.topElevation == nil)
    }

    @Test("35. Resolution leaves source evidence untouched")
    func sourceImmutability() {
        let input = plan(openings: [opening()])
        let output = OpeningMeasurementResolver().resolve(plan: input).candidatePlan
        #expect(output.openings[0].source == input.openings[0].source)
    }

    @Test("36. Version-1 opening JSON remains readable")
    func legacyJSON() throws {
        let item = opening()
        var data = try plan(openings: [item]).encoded()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 1
        var openings = try #require(object["openings"] as? [[String: Any]])
        openings[0].removeValue(forKey: "architecturalMetadata")
        object["openings"] = openings
        data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try ParametricFloorPlan.decode(from: data)
        #expect(decoded.formatVersion == 2)
        #expect(decoded.openings[0].architecturalMetadata == nil)
    }

    @Test("37. Measurement metadata survives round trip")
    func metadataRoundTrip() throws {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .width, value: 0.9, status: .verified)])
        let decoded = try ParametricFloorPlan.decode(from: plan(openings: [item]).encoded())
        #expect(decoded.openings[0].architecturalMetadata == item.architecturalMetadata)
    }

    @Test("38. Opening identifiers remain stable")
    func stableIdentifiers() throws {
        let item = opening()
        #expect(try ParametricFloorPlan.decode(from: plan(openings: [item]).encoded()).openings[0].id == item.id)
    }

    @Test("39. Failed resolution does not corrupt input")
    func failedTransactionPreservesInput() {
        var item = opening()
        item = replacingMeasurements(item, [measurement(1, openingID: item.id, kind: .width, value: -2)])
        let input = plan(openings: [item])
        _ = OpeningMeasurementResolver().resolve(plan: input)
        #expect(input.openings[0] == item)
    }

    @Test("40. Existing wall revision metadata remains intact")
    func wallRevisionPreserved() {
        let input = plan(openings: [opening()])
        #expect(OpeningMeasurementResolver().resolve(plan: input).candidatePlan.revision == input.revision)
    }

    @Test("41. Wall solver preserves verified opening offset")
    func wallSolverPreservesOpeningOffset() throws {
        var item = opening()
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, source: .laserVerified, status: .verified),
            measurement(2, openingID: item.id, kind: .width, value: 0.9, source: .laserVerified, status: .verified)
        ])
        let input = plan(length: 4.18, openings: [item])
        let result = GeometryConstraintSolver().preview(
            command: wallCommand(wallID: id(100), target: 4.25), plan: input, constraints: [],
            preservesUnrelatedGeometry: true
        )
        guard case .solved(let transaction, _) = result else {
            Issue.record("Expected compatible wall and opening revision")
            return
        }
        let placement = try #require(OpeningMeasurementResolver().resolve(plan: transaction.candidatePlan).placements.first)
        #expect(placement.startOffset == 0.65)
        #expect(abs(placement.endOffset - 2.7) < 0.000_1)
    }

    @Test("42. Wall solver rejects impossible verified opening layout")
    func wallSolverRejectsImpossibleLayout() {
        var item = opening()
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, status: .verified),
            measurement(2, openingID: item.id, kind: .width, value: 0.9, status: .verified)
        ])
        let input = plan(length: 4.25, openings: [item])
        let result = GeometryConstraintSolver().preview(
            command: wallCommand(wallID: id(100), target: 1.4), plan: input, constraints: [],
            preservesUnrelatedGeometry: true
        )
        guard case .conflict = result else { Issue.record("Expected opening layout conflict"); return }
    }

    @Test("43. Representative door chain resolves exactly")
    func representativeDoorScenario() throws {
        var door = opening(height: nil, verticalOffset: nil)
        door = replacingMeasurements(door, [
            measurement(1, openingID: door.id, kind: .offsetFromStart, value: 0.65, source: .laserVerified, status: .verified),
            measurement(2, openingID: door.id, kind: .width, value: 0.9, source: .laserVerified, status: .verified),
            measurement(3, openingID: door.id, kind: .height, value: 2.1, source: .laserVerified, status: .verified),
            measurement(4, openingID: door.id, kind: .thresholdElevation, value: 0, source: .manualEntered)
        ])
        let placement = try resolved(plan(length: 4.25, openings: [door])).1
        #expect(abs(placement.endOffset - 2.7) < 0.000_1)
        #expect(placement.topElevation == 2.1)
    }

    @Test("44. Representative window vertical chain resolves exactly")
    func representativeWindowScenario() throws {
        var window = opening(kind: .window, width: nil, height: nil, verticalOffset: nil)
        window = replacingMeasurements(window, [
            measurement(1, openingID: window.id, kind: .offsetFromStart, value: 0.8, status: .verified),
            measurement(2, openingID: window.id, kind: .width, value: 1.2, status: .verified),
            measurement(3, openingID: window.id, kind: .sillElevation, value: 0.9, status: .verified),
            measurement(4, openingID: window.id, kind: .height, value: 1.4, status: .verified)
        ])
        let placement = try resolved(plan(length: 3.1, openings: [window])).1
        #expect(placement.startOffset == 0.8)
        #expect(abs((placement.topElevation ?? 0) - 2.3) < 0.000_1)
    }

    @Test("45. Unresolved corner reference does not invent placement")
    func unresolvedCornerReference() {
        var item = opening(width: nil)
        let unresolved = OpeningMeasurementReference(endpoint: .wallStart, vertexID: nil, reliability: .unresolved)
        item = replacingMeasurements(item, [
            measurement(1, openingID: item.id, kind: .offsetFromStart, value: 0.65, reference: unresolved)
        ])
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [item]))
        #expect(result.unresolvedOpeningIDs == [item.id])
        #expect(result.placements.isEmpty)
    }

    @Test("46. Door hinge metadata reverses without fabrication")
    func hingeReversal() {
        let swing = DoorSwingMetadata(
            hingeSide: .start, direction: .unknown, angle: nil,
            leafWidth: nil, configuration: .unknown
        )
        let item = opening(swing: swing)
        let reversed = OpeningMeasurementResolver().reversingHostDirection(of: item, wallLength: 4.25)
        #expect(reversed.architecturalMetadata?.doorSwing?.hingeSide == .end)
        #expect(reversed.architecturalMetadata?.doorSwing?.direction == .unknown)
        #expect(reversed.architecturalMetadata?.doorSwing?.angle == nil)
    }

    @Test("47. Independently measured opening gap contradiction is reported")
    func measuredGapConflict() {
        var first = opening(0, center: 1)
        var gap = measurement(
            10, openingID: first.id, kind: .gapToNextOpening,
            value: 1.2, source: .laserVerified, status: .verified
        )
        gap.relatedOpeningID = id(201)
        first = replacingMeasurements(first, [gap])
        let result = OpeningMeasurementResolver().resolve(plan: plan(openings: [first, opening(1, center: 3)]))
        #expect(result.conflicts.contains { $0.code == .contradictoryMeasurements })
    }
}
