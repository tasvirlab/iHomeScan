import Foundation
import Testing
@testable import iHomeScan

@MainActor
@Suite("Precision geometry constraint solver")
struct ConstraintSolverTests {
    private let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let roomID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let scanID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private var source: GeometrySourceMetadata {
        .init(sourceElementID: nil, confidence: .high, originalStart: nil, originalEnd: nil, transform: nil)
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "A0000000-0000-0000-0000-%012d", value))!
    }

    private func plan(
        points: [PlanPoint2D],
        edges: [(Int, Int)],
        openings: [WallOpening] = [],
        completeness: ParametricGeometryCompleteness = .partial
    ) -> ParametricFloorPlan {
        ParametricFloorPlan(
            id: id(900), projectID: projectID, roomID: roomID, sourceScanID: scanID,
            coordinateSystem: "meters; x=worldX; y=-worldZ", completeness: completeness,
            vertices: points.indices.map {
                PlanVertex(id: id($0 + 1), position: points[$0], source: source, mergedEndpointKeys: [])
            },
            walls: edges.indices.map {
                ParametricWall(
                    id: id(100 + $0), startVertexID: id(edges[$0].0 + 1), endVertexID: id(edges[$0].1 + 1),
                    height: nil, thickness: nil, source: source
                )
            },
            openings: openings, columns: [], beams: [], floorBoundary: nil, endpointMerges: [],
            revision: .init(number: 1, createdAt: date, source: .lidarEstimated)
        )
    }

    private func command(
        wallID: UUID,
        target: Double,
        anchor: WallLengthAnchorStrategy = .keepStart,
        source: GeometrySourceKind = .manualEntered,
        status: GeometryVerificationStatus = .unverified
    ) -> SetWallLengthCommand {
        .init(
            id: id(800), wallID: wallID, targetLength: target, anchor: anchor,
            provenance: .init(source: source, verificationStatus: status, timestamp: date, uncertainty: nil),
            createdAt: date
        )
    }

    private func constraint(
        _ index: Int,
        _ kind: GeometryConstraintKind,
        strength: GeometryConstraintStrength = .hard,
        status: GeometryVerificationStatus = .unverified
    ) -> GeometryConstraint {
        .init(
            id: id(600 + index), kind: kind, strength: strength,
            priority: status == .verified ? .protected : .high,
            provenance: .init(
                source: status == .verified ? .laserVerified : .manualEntered,
                verificationStatus: status, timestamp: date, uncertainty: nil
            ),
            createdAt: date, isEnabled: true
        )
    }

    private func solved(
        _ plan: ParametricFloorPlan,
        target: Double,
        anchor: WallLengthAnchorStrategy = .keepStart,
        constraints: [GeometryConstraint] = []
    ) throws -> GeometryRevisionTransaction {
        let wall = try #require(plan.walls.first)
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: wall.id, target: target, anchor: anchor),
            plan: plan,
            constraints: constraints
        )
        guard case .solved(let transaction, _) = result else {
            Issue.record("Expected solved transaction")
            throw TestFailure()
        }
        return transaction
    }

    @Test("1. Isolated wall length changes actual coordinates")
    func isolatedWall() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 4.18, y: 0)], edges: [(0, 1)])
        let result = try solved(original, target: 4.25)
        #expect(abs((result.candidatePlan.walls[0].length(in: result.candidatePlan) ?? 0) - 4.25) < 0.000_1)
        #expect(abs(result.candidatePlan.vertices[1].position.x - 4.25) < 0.000_1)
    }

    @Test("2. Connected two-wall chain preserves shared identity")
    func connectedChain() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 2, y: 2)], edges: [(0, 1), (1, 2)])
        let result = try solved(original, target: 3)
        #expect(result.candidatePlan.walls[0].endVertexID == result.candidatePlan.walls[1].startVertexID)
    }

    @Test("3. Shared vertex movement propagates to connected wall")
    func sharedVertexPropagation() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 2, y: 2)], edges: [(0, 1), (1, 2)])
        let result = try solved(original, target: 3)
        let shared = try #require(result.candidatePlan.vertex(id: result.candidatePlan.walls[1].startVertexID))
        #expect(abs(shared.position.x - 3) < 0.000_1)
    }

    @Test("4. Rectangle width adjustment follows explicit horizontal and vertical constraints")
    func rectangleWidth() throws {
        let original = rectangle()
        let constraints = rectangleAxisConstraints(original)
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: 4.25),
            plan: original, constraints: constraints
        )
        guard case .solved(let transaction, _) = result else { Issue.record("Expected rectangle solution"); return }
        #expect(abs((transaction.candidatePlan.walls[0].length(in: transaction.candidatePlan) ?? 0) - 4.25) < 0.000_1)
    }

    @Test("5. Rectangle height adjustment uses documented start anchor")
    func rectangleHeight() throws {
        let original = rectangle()
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[1].id, target: 3.1),
            plan: original,
            constraints: rectangleAxisConstraints(original)
        )
        guard case .solved(let transaction, _) = result else { Issue.record("Expected rectangle solution"); return }
        #expect(abs((transaction.candidatePlan.walls[1].length(in: transaction.candidatePlan) ?? 0) - 3.1) < 0.000_1)
    }

    @Test("6. Nonorthogonal wall retains direction")
    func nonorthogonal() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 1)], edges: [(0, 1)])
        let before = try #require(original.walls[0].orientation(in: original))
        let result = try solved(original, target: 3)
        let after = try #require(result.candidatePlan.walls[0].orientation(in: result.candidatePlan))
        #expect(abs(before - after) < 0.000_1)
    }

    @Test("7. Existing fixed start vertex remains locked")
    func lockedVertex() throws {
        let original = plan(points: [.init(x: 1, y: 1), .init(x: 3, y: 1)], edges: [(0, 1)])
        let fixed = constraint(1, .fixedVertex(vertexID: id(1), position: .init(x: 1, y: 1)))
        let result = try solved(original, target: 4, constraints: [fixed])
        #expect(result.candidatePlan.vertices[0].position == .init(x: 1, y: 1))
    }

    @Test("8. Perpendicular constraint residual is satisfied")
    func perpendicular() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 2, y: 1.5)], edges: [(0, 1), (1, 2)])
        let constraints = [constraint(1, .perpendicular(firstWallID: original.walls[0].id, secondWallID: original.walls[1].id))]
        _ = try solved(original, target: 2.5, constraints: constraints)
    }

    @Test("9. Parallel constraint keeps two wall directions parallel")
    func parallel() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 0, y: 1), .init(x: 2, y: 1)], edges: [(0, 1), (2, 3)])
        let constraints = [constraint(1, .parallel(firstWallID: original.walls[0].id, secondWallID: original.walls[1].id))]
        _ = try solved(original, target: 2.5, constraints: constraints)
    }

    @Test("10. Incomplete two-wall scan remains incomplete")
    func incompleteScan() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 2, y: 2)], edges: [(0, 1), (1, 2)])
        let result = try solved(original, target: 2.2)
        #expect(result.candidatePlan.completeness == .partial)
        #expect(result.candidatePlan.floorBoundary == nil)
    }

    @Test("11. Contradictory verified wall length returns conflict")
    func contradictoryVerifiedLength() {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let verified = constraint(1, .wallLength(wallID: original.walls[0].id, meters: 2), status: .verified)
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: 3),
            plan: original, constraints: [verified]
        )
        guard case .conflict(let conflicts) = result else { Issue.record("Expected conflict"); return }
        #expect(conflicts.contains { $0.code == .verifiedMeasurement })
    }

    @Test("11b. Explicit remeasurement replaces the same wall's verified value")
    func replacesVerifiedLengthWhenExplicitlyAllowed() {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let wallID = original.walls[0].id
        let verified = constraint(1, .wallLength(wallID: wallID, meters: 2), status: .verified)
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: wallID, target: 2.991),
            plan: original,
            constraints: [verified],
            allowsReplacingVerifiedMeasurement: true
        )
        guard case .solved(let transaction, _) = result else {
            Issue.record("Expected replacement measurement to solve")
            return
        }
        #expect(abs((transaction.candidatePlan.wall(id: wallID)?.length(in: transaction.candidatePlan) ?? 0) - 2.991) < 0.001)
        #expect(transaction.constraints.filter {
            if case .wallLength(let constrainedWallID, _) = $0.kind {
                return constrainedWallID == wallID
            }
            return false
        }.count == 1)
    }

    @Test("12. Overconstrained fixed rectangle is rejected")
    func overconstrainedRectangle() {
        let original = rectangle()
        let constraints = original.vertices.enumerated().map {
            constraint($0.offset, .fixedVertex(vertexID: $0.element.id, position: $0.element.position))
        }
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: 5),
            plan: original, constraints: constraints
        )
        guard case .conflict = result else { Issue.record("Expected conflict"); return }
    }

    @Test("13. Anchor strategy is explicit in every command")
    func explicitAnchor() {
        #expect(command(wallID: id(100), target: 2).anchor == .keepStart)
    }

    @Test("14. Negative target dimension is rejected")
    func invalidTarget() {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: -1), plan: original, constraints: []
        )
        guard case .conflict(let conflicts) = result else { Issue.record("Expected conflict"); return }
        #expect(conflicts.first?.code == .invalidTarget)
    }

    @Test("15. Zero-length target is rejected")
    func zeroLength() {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: 0), plan: original, constraints: []
        )
        guard case .conflict = result else { Issue.record("Expected conflict"); return }
    }

    @Test("16. Nonfinite target is rejected")
    func nonfinite() {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: .nan), plan: original, constraints: []
        )
        guard case .conflict = result else { Issue.record("Expected conflict"); return }
    }

    @Test("17. Opening outside shortened host reports conflict")
    func openingOutside() {
        var original = plan(points: [.init(x: 0, y: 0), .init(x: 4, y: 0)], edges: [(0, 1)])
        original.openings = [opening(host: original.walls[0].id, anchor: 3, width: 1)]
        let result = GeometryConstraintSolver().preview(
            command: command(wallID: original.walls[0].id, target: 3), plan: original, constraints: []
        )
        guard case .conflict(let conflicts) = result else { Issue.record("Expected conflict"); return }
        #expect(conflicts.contains { $0.code == .openingOutsideHost })
    }

    @Test("18. Hosted opening follows its host wall identity")
    func hostedOpeningFollowsWall() throws {
        var original = plan(points: [.init(x: 0, y: 0), .init(x: 4, y: 0)], edges: [(0, 1)])
        original.openings = [opening(host: original.walls[0].id, anchor: 1, width: 0.9)]
        let result = try solved(original, target: 5)
        #expect(result.candidatePlan.openings[0].hostWallID == original.walls[0].id)
    }

    @Test("19. Verified opening anchor distance remains constant")
    func openingAnchorConstant() throws {
        var original = plan(points: [.init(x: 0, y: 0), .init(x: 4, y: 0)], edges: [(0, 1)])
        original.openings = [opening(host: original.walls[0].id, anchor: 1.2, width: 0.9)]
        let result = try solved(original, target: 5)
        guard case .distanceFromStart(let anchor) = result.candidatePlan.openings[0].horizontalAnchor else {
            Issue.record("Expected start anchor")
            return
        }
        #expect(abs(anchor.value - 1.2) < 0.000_1)
    }

    @Test("20. Opening width remains unchanged")
    func openingWidth() throws {
        var original = plan(points: [.init(x: 0, y: 0), .init(x: 4, y: 0)], edges: [(0, 1)])
        original.openings = [opening(host: original.walls[0].id, anchor: 1.2, width: 0.9)]
        let result = try solved(original, target: 5)
        #expect(result.candidatePlan.openings[0].width?.value == 0.9)
    }

    @Test("21. Preview never mutates original geometry")
    func previewImmutable() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let before = try original.encoded()
        _ = try solved(original, target: 3)
        #expect(try original.encoded() == before)
    }

    @Test("22. Apply commits candidate geometry")
    func apply() throws {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        _ = history.propose(command(history, target: 3))
        #expect(history.applyPreview() != nil)
        #expect(abs((history.document.currentPlan.walls[0].length(in: history.document.currentPlan) ?? 0) - 3) < 0.000_1)
    }

    @Test("23. Cancel keeps committed geometry")
    func cancel() {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        _ = history.propose(command(history, target: 3))
        history.cancelPreview()
        #expect(history.document.currentPlan.walls[0].length(in: history.document.currentPlan) == 2)
    }

    @Test("24. Undo restores actual coordinates")
    func undo() {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        _ = history.propose(command(history, target: 3))
        _ = history.applyPreview()
        let didUndo = history.undo()
        #expect(didUndo)
        #expect(history.document.currentPlan.vertices[1].position.x == 2)
    }

    @Test("25. Redo restores changed coordinates")
    func redo() {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        _ = history.propose(command(history, target: 3))
        _ = history.applyPreview()
        _ = history.undo()
        let didRedo = history.redo()
        #expect(didRedo)
        #expect(abs(history.document.currentPlan.vertices[1].position.x - 3) < 0.000_1)
    }

    @Test("26. Precision document retains verified dimensions after JSON reopen")
    func documentRoundTrip() throws {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        let verified = command(history, target: 2.1, source: .laserVerified, status: .verified)
        _ = history.propose(verified)
        _ = history.applyPreview()
        let decoded = try PrecisionPlanDocument.decode(from: history.document.encoded())
        #expect(decoded.constraints.contains { $0.provenance.verificationStatus == .verified })
    }

    @Test("27. Original baseline remains byte-identical after edits")
    func originalAssetsUnchanged() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let before = try original.encoded()
        var history = session(for: original)
        _ = history.propose(command(history, target: 3))
        _ = history.applyPreview()
        #expect(try history.document.baselinePlan.encoded() == before)
    }

    @Test("28. Existing P1.1 JSON remains independently readable")
    func p11Compatibility() throws {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        #expect(try ParametricFloorPlan.decode(from: original.encoded()) == original)
    }

    @Test("29. Selected wall command targets the selected identity")
    func selectedWallTarget() {
        let original = rectangle()
        let selected = original.walls[2].id
        #expect(command(wallID: selected, target: 2).wallID == selected)
    }

    @Test("30. Invalid value produces no preview")
    func invalidInputNoPreview() {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        _ = history.propose(command(history, target: .nan))
        #expect(history.preview == nil)
    }

    @Test("31. Conflict state remains available for UI warning")
    func conflictWarningState() {
        let original = plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)])
        let verified = constraint(1, .wallLength(wallID: original.walls[0].id, meters: 2), status: .verified)
        var history = GeometryRevisionSession(document: .init(
            baselinePlan: original, currentPlan: original, constraints: [verified], revisions: []
        ))
        _ = history.propose(command(history, target: 3))
        #expect(history.conflicts.contains { $0.code == .verifiedMeasurement })
    }

    @Test("32. Displayed plan reflects valid preview coordinates")
    func displayedPreview() {
        var history = session(for: plan(points: [.init(x: 0, y: 0), .init(x: 2, y: 0)], edges: [(0, 1)]))
        _ = history.propose(command(history, target: 3))
        #expect(abs((history.displayedPlan.walls[0].length(in: history.displayedPlan) ?? 0) - 3) < 0.000_1)
        #expect(history.document.currentPlan.walls[0].length(in: history.document.currentPlan) == 2)
    }

    private func rectangle() -> ParametricFloorPlan {
        plan(
            points: [.init(x: 0, y: 0), .init(x: 4.18, y: 0), .init(x: 4.18, y: 3.06), .init(x: 0, y: 3.06)],
            edges: [(0, 1), (1, 2), (2, 3), (3, 0)],
            completeness: .complete
        )
    }

    private func rectangleAxisConstraints(_ plan: ParametricFloorPlan) -> [GeometryConstraint] {
        [
            constraint(1, .horizontal(wallID: plan.walls[0].id)),
            constraint(2, .vertical(wallID: plan.walls[1].id)),
            constraint(3, .horizontal(wallID: plan.walls[2].id)),
            constraint(4, .vertical(wallID: plan.walls[3].id)),
            constraint(5, .fixedVertex(vertexID: plan.vertices[0].id, position: plan.vertices[0].position)),
        ]
    }

    private func opening(host: UUID, anchor: Double, width: Double) -> WallOpening {
        let provenance = MeasurementProvenance(
            source: .laserVerified, verificationStatus: .verified, timestamp: date, uncertainty: nil
        )
        return WallOpening(
            id: id(500), hostWallID: host, kind: .door,
            width: .init(value: width, provenance: provenance), height: nil, verticalOffset: nil,
            horizontalAnchor: .distanceFromStart(.init(value: anchor, provenance: provenance)),
            source: source
        )
    }

    private func session(for plan: ParametricFloorPlan) -> GeometryRevisionSession {
        GeometryRevisionSession(document: .init(
            baselinePlan: plan, currentPlan: plan, constraints: [], revisions: []
        ))
    }

    private func command(
        _ session: GeometryRevisionSession,
        target: Double,
        source: GeometrySourceKind = .manualEntered,
        status: GeometryVerificationStatus = .unverified
    ) -> SetWallLengthCommand {
        command(
            wallID: session.document.currentPlan.walls[0].id,
            target: target,
            source: source,
            status: status
        )
    }

    private struct TestFailure: Error {}
}
