import CoreGraphics
import Foundation
import Testing
@testable import iHomeScan

@MainActor
@Suite("Parametric geometry foundation")
struct ParametricGeometryTests {
    private let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let roomID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let scanID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func wall(
        _ id: UUID,
        _ start: CGPoint,
        _ end: CGPoint,
        parent: UUID? = nil,
        kind: RoomGeometrySource.SurfaceKind = .wall
    ) -> RoomPlanGeometryMetadata.Surface {
        let length = hypot(end.x - start.x, end.y - start.y)
        return RoomPlanGeometryMetadata.Surface(
            id: id, parentIdentifier: parent, kind: kind,
            dimensions: .init(x: length, y: kind == .wall ? 2.8 : 2.1, z: kind == .wall ? 0.12 : 0),
            transform: RoomGeometrySource.Transform.identity.values,
            localPolygon: [],
            projectedPolygon: [],
            projectedSegment: FloorPlan.Segment(start: start, end: end),
            confidence: .high,
            story: 0
        )
    }

    private func floorSurface(_ points: [CGPoint]) -> RoomPlanGeometryMetadata.Surface {
        RoomPlanGeometryMetadata.Surface(
            id: UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!,
            parentIdentifier: nil, kind: .floor,
            dimensions: .init(x: 1, y: 0, z: 1),
            transform: RoomGeometrySource.Transform.identity.values,
            localPolygon: [], projectedPolygon: points, projectedSegment: nil,
            confidence: .high, story: 0
        )
    }

    private func floorPlan(
        walls: [RoomPlanGeometryMetadata.Surface],
        extras: [RoomPlanGeometryMetadata.Surface] = [],
        completeness: RoomPlanGeometryMetadata.Completeness = .complete,
        floor: [CGPoint]? = nil
    ) -> FloorPlan {
        let segments = walls.compactMap(\.projectedSegment)
        let points = segments.flatMap { [$0.start, $0.end] }
        let bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let floorSurfaces = floor.map { [floorSurface($0)] } ?? []
        return FloorPlan(
            bounds: bounds.isNull ? .zero : bounds,
            rooms: [],
            outerWalls: segments.map { [$0.start, $0.end] },
            innerWalls: [], doors: [], windows: [], dimensions: [],
            roomPlanMetadata: RoomPlanGeometryMetadata(
                formatVersion: 1,
                roomIdentifier: roomID,
                roomPlanVersion: 1,
                coordinateSystem: "meters; x=worldX; y=-worldZ",
                completeness: completeness,
                floorArea: nil,
                surfaces: walls + extras + floorSurfaces,
                objects: [],
                rejectedElementIdentifiers: []
            )
        )
    }

    private func convert(_ floorPlan: FloorPlan) throws -> ParametricFloorPlan {
        try RoomPlanToParametricAdapter().convert(
            floorPlan, scanID: scanID, projectID: projectID, roomID: roomID, createdAt: date
        )
    }

    private func id(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "A0000000-0000-0000-0000-%012d", suffix))!
    }

    @Test("Simple rectangle shares four vertices and forms a closed topology")
    func rectangle() throws {
        let surfaces = [
            wall(id(1), .init(x: 0, y: 0), .init(x: 4, y: 0)),
            wall(id(2), .init(x: 4, y: 0), .init(x: 4, y: 3)),
            wall(id(3), .init(x: 4, y: 3), .init(x: 0, y: 3)),
            wall(id(4), .init(x: 0, y: 3), .init(x: 0, y: 0)),
        ]
        let plan = try convert(floorPlan(walls: surfaces, floor: [
            .init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 4, y: 3), .init(x: 0, y: 3),
        ]))
        #expect(plan.vertices.count == 4)
        #expect(plan.walls.count == 4)
        #expect(ParametricGeometryValidator().validate(plan).warnings.allSatisfy { $0.code != .openChain })
    }

    @Test("L-shaped room keeps irregular closed topology")
    func lShape() throws {
        let points = [
            CGPoint(x: 0, y: 0), .init(x: 3, y: 0), .init(x: 3, y: 2),
            .init(x: 1, y: 2), .init(x: 1, y: 4), .init(x: 0, y: 4),
        ]
        let surfaces = points.indices.map {
            wall(id($0 + 1), points[$0], points[($0 + 1) % points.count])
        }
        let plan = try convert(floorPlan(walls: surfaces, floor: points))
        #expect(plan.vertices.count == 6)
        #expect(plan.floorBoundary?.first?.count == 6)
    }

    @Test("Rotated rectangle preserves lengths and angles")
    func rotatedRectangle() throws {
        let angle = Double.pi / 5
        func rotate(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x * cos(angle) - point.y * sin(angle),
                y: point.x * sin(angle) + point.y * cos(angle)
            )
        }
        let points = [
            CGPoint(x: 0, y: 0), .init(x: 5, y: 0), .init(x: 5, y: 2), .init(x: 0, y: 2),
        ].map(rotate)
        let plan = try convert(floorPlan(walls: points.indices.map {
            wall(id($0 + 1), points[$0], points[($0 + 1) % points.count])
        }))
        let lengths = plan.walls.compactMap { $0.length(in: plan) }.sorted()
        #expect(abs(lengths[0] - 2) < 0.000_001)
        #expect(abs(lengths[3] - 5) < 0.000_001)
    }

    @Test("Nonorthogonal walls preserve their derived orientation")
    func nonorthogonal() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 1)),
            wall(id(2), .init(x: 2, y: 1), .init(x: 3, y: 3)),
        ], completeness: .incomplete))
        let orientation = try #require(plan.walls.first?.orientation(in: plan))
        #expect(abs(orientation - atan2(1.0, 2.0)) < 0.000_001)
    }

    @Test("Connected walls reference the same reconciled vertex")
    func connectedWalls() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
            wall(id(2), .init(x: 2, y: 0), .init(x: 2, y: 2)),
        ], completeness: .incomplete))
        let shared = Set([plan.walls[0].startVertexID, plan.walls[0].endVertexID])
            .intersection([plan.walls[1].startVertexID, plan.walls[1].endVertexID])
        #expect(shared.count == 1)
    }

    @Test("Separated walls retain four independent endpoints")
    func unconnectedWalls() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 1, y: 0)),
            wall(id(2), .init(x: 2, y: 0), .init(x: 3, y: 0)),
        ], completeness: .incomplete))
        #expect(plan.vertices.count == 4)
    }

    @Test("Slightly misaligned perpendicular endpoints reconcile conservatively")
    func misalignedEndpoints() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
            wall(id(2), .init(x: 2.02, y: 0.01), .init(x: 2.02, y: 2)),
        ], completeness: .incomplete))
        #expect(plan.vertices.count == 3)
        #expect(plan.endpointMerges.count == 1)
        #expect((plan.endpointMerges.first?.maximumSeparation ?? 1) < 0.04)
    }

    @Test("Nearby parallel endpoints without evidence remain separate")
    func closeButUnconnected() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
            wall(id(2), .init(x: 2.02, y: 0.01), .init(x: 4, y: 0.01)),
        ], completeness: .incomplete))
        #expect(plan.vertices.count == 4)
        #expect(plan.endpointMerges.isEmpty)
    }

    @Test("Two-wall partial scan stays partial and open")
    func partialScan() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
            wall(id(2), .init(x: 2, y: 0), .init(x: 2, y: 2)),
        ], completeness: .incomplete))
        #expect(plan.completeness == .partial)
        #expect(ParametricGeometryValidator().validate(plan).issues.contains { $0.code == .openChain })
    }

    @Test("Missing openings do not create fabricated entities")
    func missingOpenings() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 3, y: 0)),
        ], completeness: .incomplete))
        #expect(plan.openings.isEmpty)
    }

    @Test("Door remains anchored to its source parent wall")
    func hostedDoor() throws {
        let hostID = id(1)
        let doorID = id(2)
        let plan = try convert(floorPlan(
            walls: [wall(hostID, .zero, .init(x: 4, y: 0))],
            extras: [wall(doorID, .init(x: 1, y: 0), .init(x: 2, y: 0), parent: hostID, kind: .door)],
            completeness: .incomplete
        ))
        let opening = try #require(plan.openings.first)
        #expect(opening.kind == .door)
        #expect(opening.hostWallID == plan.walls.first?.id)
        if case .distanceFromStart(let anchor) = opening.horizontalAnchor {
            #expect(abs(anchor.value - 1.5) < 0.000_001)
        }
    }

    @Test("Validator reports an invalid opening host")
    func invalidOpeningHost() throws {
        var plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 3, y: 0)),
        ], completeness: .incomplete))
        plan.openings = [WallOpening(
            id: id(90), hostWallID: id(91), kind: .door, width: nil, height: nil,
            verticalOffset: nil,
            horizontalAnchor: .distanceFromStart(.init(
                value: 1,
                provenance: .init(source: .manualEntered, verificationStatus: .unverified,
                                  timestamp: nil, uncertainty: nil)
            )),
            source: .init(sourceElementID: nil, confidence: .unknown,
                          originalStart: nil, originalEnd: nil, transform: nil)
        )]
        #expect(ParametricGeometryValidator().validate(plan).errors.contains { $0.code == .invalidOpeningHost })
    }

    @Test("Validator rejects zero-length wall geometry")
    func zeroLengthWall() throws {
        var plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
        ], completeness: .incomplete))
        plan.vertices[1].position = plan.vertices[0].position
        #expect(ParametricGeometryValidator().validate(plan).errors.contains { $0.code == .zeroLengthWall })
    }

    @Test("Validator rejects nonfinite vertex coordinates")
    func nonfiniteCoordinate() throws {
        var plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
        ], completeness: .incomplete))
        plan.vertices[0].position.x = .nan
        #expect(ParametricGeometryValidator().validate(plan).errors.contains { $0.code == .nonfiniteCoordinate })
    }

    @Test("Versioned JSON round-trips without geometry loss")
    func serialization() throws {
        let plan = try convert(floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
        ], completeness: .incomplete))
        #expect(try ParametricFloorPlan.decode(from: plan.encoded()) == plan)
    }

    @Test("Saved scan lazily creates and reopens a parametric artifact")
    func savedScanConversion() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ParametricTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = LocalFileStorageService(rootURL: root)
        let sourcePlan = floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
        ], completeness: .incomplete)
        let modelURL = root.appending(path: "fixture.usdz")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("usdz".utf8).write(to: modelURL)
        _ = try files.saveScanBundle(
            sourceData: Data("{}".utf8), geometryData: try sourcePlan.encoded(),
            modelURL: modelURL, projectID: projectID, scanID: scanID
        )
        let scan = SavedScan(
            id: scanID, projectID: projectID, floorID: id(80), roomID: roomID,
            createdAt: date, completeness: .incomplete, floorArea: nil,
            sourceAssetID: id(81), geometryAssetID: id(82), modelAssetID: id(83)
        )
        let repository = ParametricPlanRepository(files: files)
        let created = try repository.loadOrCreate(scan: scan, floorPlan: sourcePlan)
        #expect(files.parametricPlanExists(projectID: projectID, scanID: scanID))
        #expect(try repository.load(scan: scan) == created)

        var edited = created
        edited.vertices[1].position.x += 0.2
        let document = PrecisionPlanDocument(
            baselinePlan: created,
            currentPlan: edited,
            constraints: [],
            revisions: []
        )
        try repository.savePrecisionDocument(document, scan: scan)
        let reopened = try repository.loadPrecisionDocument(scan: scan, floorPlan: sourcePlan)
        #expect(reopened.currentPlan == edited)
        #expect(reopened.baselinePlan == created)
    }

    @Test("Existing scan artifacts remain byte-for-byte compatible")
    func existingScanCompatibility() throws {
        let source = floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
        ], completeness: .incomplete)
        let encoded = try source.encoded()
        _ = try convert(try FloorPlan.decode(from: encoded))
        #expect(try source.encoded() == encoded)
    }

    @Test("Repeated conversion produces stable geometry identifiers")
    func stableIdentity() throws {
        let source = floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
            wall(id(2), .init(x: 2, y: 0), .init(x: 2, y: 2)),
        ], completeness: .incomplete)
        let first = try convert(source)
        let second = try convert(source)
        #expect(first.vertices.map(\.id) == second.vertices.map(\.id))
        #expect(first.walls.map(\.id) == second.walls.map(\.id))
    }

    @Test("Adapter never mutates original FloorPlan geometry")
    func originalGeometryPreservation() throws {
        let source = floorPlan(walls: [
            wall(id(1), .zero, .init(x: 2, y: 0)),
        ], completeness: .incomplete)
        let before = try source.encoded()
        _ = try convert(source)
        #expect(try source.encoded() == before)
    }

    @Test("Wall selection identity resolves complete metadata")
    func wallMetadataLookup() throws {
        let sourceID = id(1)
        let plan = try convert(floorPlan(walls: [
            wall(sourceID, .zero, .init(x: 2.5, y: 0)),
        ], completeness: .incomplete))
        let selectedID = try #require(plan.walls.first?.id)
        let selected = try #require(plan.wall(id: selectedID))
        #expect(abs((selected.length(in: plan) ?? 0) - 2.5) < 0.000_001)
        #expect(selected.source.sourceElementID == sourceID)
        #expect(selected.height?.provenance.source == .lidarEstimated)
        #expect(selected.height?.provenance.verificationStatus == .estimated)
    }
}
