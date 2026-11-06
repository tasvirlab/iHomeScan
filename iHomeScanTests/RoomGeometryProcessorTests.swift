import CoreGraphics
import Foundation
import Testing
@testable import iHomeScan

@MainActor
@Suite("RoomPlan geometry conversion")
struct RoomGeometryProcessorTests {
    private let processor = RoomGeometryProcessor()

    private func transform(
        translationX: Double = 0,
        translationZ: Double = 0,
        yawDegrees: Double = 0
    ) -> RoomGeometrySource.Transform {
        let radians = yawDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return RoomGeometrySource.Transform(values: [
            cosine, 0, -sine, 0,
            0, 1, 0, 0,
            sine, 0, cosine, 0,
            translationX, 0, translationZ, 1,
        ])
    }

    private func surface(
        id: UUID = UUID(),
        parent: UUID? = nil,
        kind: RoomGeometrySource.SurfaceKind,
        width: Double,
        height: Double = 2.5,
        transform: RoomGeometrySource.Transform = .identity,
        polygon: [RoomGeometrySource.Vector3] = []
    ) -> RoomGeometrySource.Surface {
        RoomGeometrySource.Surface(
            identifier: id,
            parentIdentifier: parent,
            kind: kind,
            dimensions: .init(x: width, y: height, z: 0),
            transform: transform,
            polygonCorners: polygon,
            confidence: .high,
            story: 0
        )
    }

    private func source(
        surfaces: [RoomGeometrySource.Surface],
        roomID: UUID = UUID()
    ) -> RoomGeometrySource {
        RoomGeometrySource(
            roomIdentifier: roomID,
            roomPlanVersion: 1,
            surfaces: surfaces,
            objects: []
        )
    }

    @Test("Meters and world X/Z coordinates become normalized x-right/y-down coordinates")
    func coordinatesAndUnits() throws {
        let wall = surface(
            kind: .wall,
            width: 4,
            transform: transform(translationX: 10, translationZ: -3)
        )
        let plan = try processor.process(source(surfaces: [wall]))

        let segment = try #require(plan.roomPlanMetadata?.surfaces.first?.projectedSegment)
        #expect(abs(segment.start.x - 0) < 0.0001)
        #expect(abs(segment.end.x - 4) < 0.0001)
        #expect(abs(segment.start.y - segment.end.y) < 0.0001)
        #expect(plan.dimensions.first?.value == 4)
    }

    @Test("Rotated non-axis-aligned walls preserve their angle and length")
    func rotatedWall() throws {
        let wall = surface(
            kind: .wall,
            width: 5,
            transform: transform(yawDegrees: 37)
        )
        let plan = try processor.process(source(surfaces: [wall]))
        let segment = try #require(plan.outerWalls.first)
        let start = try #require(segment.first)
        let end = try #require(segment.last)

        #expect(abs(hypot(end.x - start.x, end.y - start.y) - 5) < 0.0001)
        #expect(abs(end.x - start.x) > 0.1)
        #expect(abs(end.y - start.y) > 0.1)
        #expect(abs((plan.dimensions.first?.labelRotation ?? 0)) > 0.1)
    }

    @Test("Surface identifiers and parent relationships survive conversion")
    func relationships() throws {
        let wallID = UUID()
        let doorID = UUID()
        let plan = try processor.process(source(surfaces: [
            surface(id: wallID, kind: .wall, width: 3),
            surface(id: doorID, parent: wallID, kind: .door, width: 0.9),
        ]))

        let door = try #require(plan.roomPlanMetadata?.surfaces.first { $0.id == doorID })
        #expect(door.parentIdentifier == wallID)
        #expect(door.kind == .door)
        #expect(door.confidence == .high)
    }

    @Test("Two-wall scans remain valid and are marked incomplete")
    func incompleteScan() throws {
        let plan = try processor.process(source(surfaces: [
            surface(kind: .wall, width: 4),
            surface(kind: .wall, width: 3, transform: transform(yawDegrees: 90)),
        ]))

        #expect(plan.outerWalls.count == 2)
        #expect(plan.roomPlanMetadata?.completeness == .incomplete)
        #expect(plan.roomPlanMetadata?.floorArea == nil)
    }

    @Test("Missing optional doors, windows and floors do not invent geometry")
    func missingSurfaces() throws {
        let plan = try processor.process(source(surfaces: [
            surface(kind: .wall, width: 2),
        ]))

        #expect(plan.doors.isEmpty)
        #expect(plan.windows.isEmpty)
        #expect(plan.rooms.isEmpty)
        #expect(plan.roomPlanMetadata?.floorArea == nil)
    }

    @Test("Nonfinite transforms and dimensions are rejected")
    func invalidGeometry() throws {
        let invalidTransform = RoomGeometrySource.Transform(values: Array(repeating: .nan, count: 16))
        let validID = UUID()
        let invalidID = UUID()
        let plan = try processor.process(source(surfaces: [
            surface(id: invalidID, kind: .wall, width: 2, transform: invalidTransform),
            surface(id: validID, kind: .wall, width: 2),
        ]))

        #expect(plan.roomPlanMetadata?.rejectedElementIdentifiers == [invalidID])
        #expect(plan.roomPlanMetadata?.surfaces.map(\.id) == [validID])
    }

    @Test("Area comes only from valid RoomPlan floor polygons")
    func floorArea() throws {
        let floor = surface(
            kind: .floor,
            width: 4,
            height: 3,
            polygon: [
                .init(x: 0, y: 0, z: 0),
                .init(x: 4, y: 0, z: 0),
                .init(x: 4, y: 0, z: 3),
                .init(x: 0, y: 0, z: 3),
            ]
        )
        let plan = try processor.process(source(surfaces: [
            floor,
            surface(kind: .wall, width: 4),
            surface(kind: .wall, width: 3, transform: transform(yawDegrees: 90)),
            surface(kind: .wall, width: 4, transform: transform(translationZ: 3)),
        ]))

        #expect(abs((plan.roomPlanMetadata?.floorArea ?? 0) - 12) < 0.0001)
        #expect(plan.roomPlanMetadata?.completeness == .complete)
    }

    @Test("Version 2 geometry round-trips and legacy version 1 remains decodable")
    func serializationCompatibility() throws {
        let plan = try processor.process(source(surfaces: [
            surface(kind: .wall, width: 3),
        ]))
        let decoded = try FloorPlan.decode(from: plan.encoded())
        #expect(decoded == plan)
        #expect(decoded.formatVersion == 2)

        let legacy = """
        {
          "formatVersion": 1,
          "bounds": [[0, 0], [2, 2]],
          "rooms": [],
          "outerWalls": [],
          "innerWalls": [],
          "doors": [],
          "windows": [],
          "dimensions": []
        }
        """.data(using: .utf8)!
        let legacyPlan = try FloorPlan.decode(from: legacy)
        #expect(legacyPlan.formatVersion == 1)
        #expect(legacyPlan.roomPlanMetadata == nil)
    }
}
