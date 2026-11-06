import Foundation
import CoreGraphics
#if canImport(RoomPlan)
import RoomPlan
import simd
#endif

enum RoomGeometryProcessingError: Error, Equatable {
    case noValidGeometry
}

/// Converts RoomPlan world geometry into iHomeScan's meter-based, x-right/y-down 2D plan.
struct RoomGeometryProcessor {
    private struct ConvertedSurface {
        let source: RoomGeometrySource.Surface
        let worldPolygon: [CGPoint]
        let worldSegment: FloorPlan.Segment?
    }

    func process(_ source: RoomGeometrySource) throws -> FloorPlan {
        var converted: [ConvertedSurface] = []
        var rejected: [UUID] = []

        for surface in source.surfaces {
            guard validDimensions(surface.dimensions), surface.transform.isValid else {
                rejected.append(surface.identifier)
                continue
            }

            let polygon = surface.polygonCorners.compactMap {
                surface.transform.applying(to: $0).map(project)
            }
            let segment = makeSegment(for: surface)
            guard !polygon.isEmpty || segment != nil else {
                rejected.append(surface.identifier)
                continue
            }
            converted.append(ConvertedSurface(source: surface, worldPolygon: polygon, worldSegment: segment))
        }

        guard !converted.isEmpty else {
            throw RoomGeometryProcessingError.noValidGeometry
        }

        let allPoints = converted.flatMap { item in
            item.worldPolygon + [item.worldSegment?.start, item.worldSegment?.end].compactMap { $0 }
        }
        guard let minimumX = allPoints.map(\.x).min(),
              let minimumY = allPoints.map(\.y).min(),
              minimumX.isFinite,
              minimumY.isFinite
        else {
            throw RoomGeometryProcessingError.noValidGeometry
        }

        func normalize(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - minimumX, y: point.y - minimumY)
        }

        let normalized = converted.map { item in
            ConvertedSurface(
                source: item.source,
                worldPolygon: item.worldPolygon.map(normalize),
                worldSegment: item.worldSegment.map {
                    FloorPlan.Segment(start: normalize($0.start), end: normalize($0.end))
                }
            )
        }

        let normalizedPoints = normalized.flatMap { item in
            item.worldPolygon + [item.worldSegment?.start, item.worldSegment?.end].compactMap { $0 }
        }
        let bounds = bounds(containing: normalizedPoints)
        let walls = normalized.filter { $0.source.kind == .wall }
        let floorPolygons = normalized
            .filter { $0.source.kind == .floor }
            .map(\.worldPolygon)
            .filter { $0.count >= 3 }
        let floorArea = reliableFloorArea(polygons: floorPolygons)
        let completeness: RoomPlanGeometryMetadata.Completeness
        if walls.isEmpty && floorPolygons.isEmpty {
            completeness = .empty
        } else if walls.count >= 3 && floorArea != nil {
            completeness = .complete
        } else {
            completeness = .incomplete
        }

        let metadataSurfaces = normalized.map { item in
            RoomPlanGeometryMetadata.Surface(
                id: item.source.identifier,
                parentIdentifier: item.source.parentIdentifier,
                kind: item.source.kind,
                dimensions: point3D(item.source.dimensions),
                transform: item.source.transform.values,
                localPolygon: item.source.polygonCorners.map(point3D),
                projectedPolygon: item.worldPolygon,
                projectedSegment: item.worldSegment,
                confidence: item.source.confidence,
                story: item.source.story
            )
        }

        let metadataObjects = source.objects.compactMap { object -> RoomPlanGeometryMetadata.Object? in
            guard validDimensions(object.dimensions), object.transform.isValid else {
                rejected.append(object.identifier)
                return nil
            }
            return RoomPlanGeometryMetadata.Object(
                id: object.identifier,
                parentIdentifier: object.parentIdentifier,
                category: object.category,
                dimensions: point3D(object.dimensions),
                transform: object.transform.values,
                confidence: object.confidence,
                story: object.story,
                attributes: object.attributes
            )
        }

        let doors = normalized
            .filter { $0.source.kind == .door }
            .compactMap { item -> FloorPlan.Door? in
                guard let segment = item.worldSegment else { return nil }
                let dx = segment.end.x - segment.start.x
                let dy = segment.end.y - segment.start.y
                let angle = atan2(dy, dx) * 180 / .pi
                return FloorPlan.Door(
                    hinge: segment.start,
                    radius: distance(segment.start, segment.end),
                    startAngle: angle,
                    endAngle: angle + 90
                )
            }

        let windows = normalized
            .filter { $0.source.kind == .window }
            .compactMap { item -> CGRect? in
                guard let segment = item.worldSegment else { return nil }
                let thickness: CGFloat = 0.08
                return CGRect(
                    x: min(segment.start.x, segment.end.x) - thickness / 2,
                    y: min(segment.start.y, segment.end.y) - thickness / 2,
                    width: max(abs(segment.end.x - segment.start.x), thickness),
                    height: max(abs(segment.end.y - segment.start.y), thickness)
                )
            }

        let dimensions = walls.compactMap { item -> FloorPlan.Dimension? in
            guard let segment = item.worldSegment else { return nil }
            let length = item.source.dimensions.x
            guard length.isFinite, length > 0 else { return nil }
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            return FloorPlan.Dimension(
                start: segment.start,
                end: segment.end,
                value: length,
                labelPosition: CGPoint(
                    x: (segment.start.x + segment.end.x) / 2,
                    y: (segment.start.y + segment.end.y) / 2
                ),
                labelRotation: atan2(dy, dx) * 180 / .pi
            )
        }

        let planRoom: [FloorPlan.PlanRoom]
        if !floorPolygons.isEmpty {
            planRoom = [
                FloorPlan.PlanRoom(
                    id: source.roomIdentifier.uuidString,
                    rect: bounds,
                    labelCenter: CGPoint(x: bounds.midX, y: bounds.midY)
                ),
            ]
        } else {
            planRoom = []
        }

        return FloorPlan(
            formatVersion: FloorPlan.currentFormatVersion,
            bounds: bounds,
            rooms: planRoom,
            outerWalls: walls.compactMap { item in
                item.worldSegment.map { [$0.start, $0.end] }
            },
            innerWalls: [],
            doors: doors,
            windows: windows,
            dimensions: dimensions,
            roomPlanMetadata: RoomPlanGeometryMetadata(
                formatVersion: RoomPlanGeometryMetadata.currentFormatVersion,
                roomIdentifier: source.roomIdentifier,
                roomPlanVersion: source.roomPlanVersion,
                coordinateSystem: "meters; origin=minX,minZ; x=worldX; y=-worldZ",
                completeness: completeness,
                floorArea: floorArea,
                surfaces: metadataSurfaces,
                objects: metadataObjects,
                rejectedElementIdentifiers: rejected
            )
        )
    }

    private func makeSegment(for surface: RoomGeometrySource.Surface) -> FloorPlan.Segment? {
        let halfWidth = surface.dimensions.x / 2
        guard halfWidth.isFinite, halfWidth > 0,
              let start3D = surface.transform.applying(
                to: RoomGeometrySource.Vector3(x: -halfWidth, y: 0, z: 0)
              ),
              let end3D = surface.transform.applying(
                to: RoomGeometrySource.Vector3(x: halfWidth, y: 0, z: 0)
              )
        else { return nil }

        let start = project(start3D)
        let end = project(end3D)
        guard distance(start, end) > 0.0001 else { return nil }
        return FloorPlan.Segment(start: start, end: end)
    }

    private func project(_ point: RoomGeometrySource.Vector3) -> CGPoint {
        CGPoint(x: point.x, y: -point.z)
    }

    private func validDimensions(_ dimensions: RoomGeometrySource.Vector3) -> Bool {
        dimensions.isFinite && dimensions.x >= 0 && dimensions.y >= 0 && dimensions.z >= 0
    }

    private func bounds(containing points: [CGPoint]) -> CGRect {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else { return .zero }

        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0.001),
            height: max(maxY - minY, 0.001)
        )
    }

    private func reliableFloorArea(polygons: [[CGPoint]]) -> Double? {
        guard !polygons.isEmpty else { return nil }
        let areas = polygons.compactMap { polygon -> Double? in
            guard polygon.count >= 3, polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                return nil
            }
            var twiceArea: CGFloat = 0
            for index in polygon.indices {
                let next = polygon[(index + 1) % polygon.count]
                twiceArea += polygon[index].x * next.y - next.x * polygon[index].y
            }
            let area = abs(twiceArea) / 2
            return area > 0.0001 && area.isFinite ? Double(area) : nil
        }
        guard areas.count == polygons.count else { return nil }
        return areas.reduce(0, +)
    }

    private func distance(_ start: CGPoint, _ end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func point3D(_ point: RoomGeometrySource.Vector3) -> RoomPlanGeometryMetadata.Point3D {
        RoomPlanGeometryMetadata.Point3D(x: point.x, y: point.y, z: point.z)
    }
}

#if canImport(RoomPlan)
extension RoomGeometrySource {
    init(capturedRoom room: CapturedRoom) {
        func confidence(_ value: CapturedRoom.Confidence) -> Confidence {
            switch value {
            case .low: .low
            case .medium: .medium
            case .high: .high
            @unknown default: .unknown
            }
        }

        func transform(_ value: simd_float4x4) -> Transform {
            Transform(values: (0..<4).flatMap { column in
                (0..<4).map { row in Double(value[column][row]) }
            })
        }

        func vector(_ value: SIMD3<Float>) -> Vector3 {
            Vector3(x: Double(value.x), y: Double(value.y), z: Double(value.z))
        }

        func surface(_ value: CapturedRoom.Surface, kind: SurfaceKind) -> Surface {
            Surface(
                identifier: value.identifier,
                parentIdentifier: value.parentIdentifier,
                kind: kind,
                dimensions: vector(value.dimensions),
                transform: transform(value.transform),
                polygonCorners: value.polygonCorners.map(vector),
                confidence: confidence(value.confidence),
                story: value.story
            )
        }

        let surfaces =
            room.walls.map { surface($0, kind: .wall) }
            + room.doors.map { surface($0, kind: .door) }
            + room.windows.map { surface($0, kind: .window) }
            + room.openings.map { surface($0, kind: .opening) }
            + room.floors.map { surface($0, kind: .floor) }

        let objects = room.objects.map { object in
            Object(
                identifier: object.identifier,
                parentIdentifier: object.parentIdentifier,
                category: String(describing: object.category),
                dimensions: vector(object.dimensions),
                transform: transform(object.transform),
                confidence: confidence(object.confidence),
                story: object.story,
                attributes: object.attributes.map(\.shortIdentifier)
            )
        }

        self.init(
            roomIdentifier: room.identifier,
            roomPlanVersion: room.version,
            surfaces: surfaces,
            objects: objects
        )
    }
}
#endif
