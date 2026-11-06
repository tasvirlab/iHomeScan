import CryptoKit
import Foundation

enum ParametricAdapterError: Error, Equatable {
    case missingRoomPlanMetadata
    case invalidWallGeometry(UUID)
}

struct EndpointReconciliationConfiguration: Sendable {
    /// Maximum distance for a merge supported by wall-direction evidence.
    let supportedTolerance: Double
    /// Very small gaps may be merged without directional evidence.
    let strongPositionalTolerance: Double
    let minimumIntersectionAngle: Double

    static let conservative = EndpointReconciliationConfiguration(
        supportedTolerance: 0.04,
        strongPositionalTolerance: 0.008,
        minimumIntersectionAngle: 20 * .pi / 180
    )
}

/// Converts immutable RoomPlan-derived metadata into the framework-independent editing aggregate.
struct RoomPlanToParametricAdapter {
    private struct Endpoint {
        let key: String
        let position: PlanPoint2D
        let wallSourceID: UUID
        let direction: PlanPoint2D
        let source: GeometrySourceMetadata
    }

    private struct Cluster {
        var endpoints: [Endpoint]
        var center: PlanPoint2D {
            let count = Double(endpoints.count)
            return PlanPoint2D(
                x: endpoints.reduce(0) { $0 + $1.position.x } / count,
                y: endpoints.reduce(0) { $0 + $1.position.y } / count
            )
        }
    }

    let reconciliation: EndpointReconciliationConfiguration

    init(reconciliation: EndpointReconciliationConfiguration = .conservative) {
        self.reconciliation = reconciliation
    }

    func convert(
        _ floorPlan: FloorPlan,
        scanID: UUID,
        projectID: UUID,
        roomID: UUID,
        createdAt: Date
    ) throws -> ParametricFloorPlan {
        guard let metadata = floorPlan.roomPlanMetadata else {
            throw ParametricAdapterError.missingRoomPlanMetadata
        }

        let wallSurfaces = metadata.surfaces
            .filter { $0.kind == .wall }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var endpoints: [Endpoint] = []
        for surface in wallSurfaces {
            guard let segment = surface.projectedSegment,
                  finite(segment.start), finite(segment.end),
                  distance(segment.start, segment.end) > 0.001 else {
                throw ParametricAdapterError.invalidWallGeometry(surface.id)
            }
            let start = point(segment.start)
            let end = point(segment.end)
            let direction = normalized(from: start, to: end)
            let source = sourceMetadata(surface, originalStart: start, originalEnd: end)
            endpoints.append(Endpoint(
                key: "\(surface.id.uuidString):start", position: start,
                wallSourceID: surface.id, direction: direction, source: source
            ))
            endpoints.append(Endpoint(
                key: "\(surface.id.uuidString):end", position: end,
                wallSourceID: surface.id, direction: direction, source: source
            ))
        }

        let clusters = reconcile(endpoints.sorted { $0.key < $1.key })
        var endpointVertexIDs: [String: UUID] = [:]
        var vertices: [PlanVertex] = []
        var merges: [EndpointMergeRecord] = []
        for cluster in clusters {
            let keys = cluster.endpoints.map(\.key).sorted()
            let id = StableGeometryID.make(namespace: scanID, components: ["vertex"] + keys)
            keys.forEach { endpointVertexIDs[$0] = id }
            let source = cluster.endpoints.count == 1
                ? cluster.endpoints[0].source
                : GeometrySourceMetadata(
                    sourceElementID: nil,
                    confidence: weakestConfidence(cluster.endpoints.map { $0.source.confidence }),
                    originalStart: nil, originalEnd: nil, transform: nil
                )
            vertices.append(PlanVertex(
                id: id, position: cluster.center, source: source, mergedEndpointKeys: keys
            ))
            if cluster.endpoints.count > 1 {
                merges.append(EndpointMergeRecord(
                    vertexID: id,
                    endpointKeys: keys,
                    maximumSeparation: maximumSeparation(cluster.endpoints.map(\.position))
                ))
            }
        }

        let lidar = MeasurementProvenance(
            source: .lidarEstimated, verificationStatus: .estimated,
            timestamp: createdAt, uncertainty: nil
        )
        var walls: [ParametricWall] = []
        var wallIDsBySource: [UUID: UUID] = [:]
        for surface in wallSurfaces {
            guard let startID = endpointVertexIDs["\(surface.id.uuidString):start"],
                  let endID = endpointVertexIDs["\(surface.id.uuidString):end"] else {
                throw ParametricAdapterError.invalidWallGeometry(surface.id)
            }
            let wallID = StableGeometryID.make(
                namespace: scanID, components: ["wall", surface.id.uuidString]
            )
            wallIDsBySource[surface.id] = wallID
            walls.append(ParametricWall(
                id: wallID,
                startVertexID: startID,
                endVertexID: endID,
                height: measurement(surface.dimensions.y, provenance: lidar),
                thickness: measurement(surface.dimensions.z, provenance: lidar),
                source: sourceMetadata(
                    surface,
                    originalStart: point(surface.projectedSegment?.start),
                    originalEnd: point(surface.projectedSegment?.end)
                )
            ))
        }

        let temporary = ParametricFloorPlan(
            id: scanID, projectID: projectID, roomID: roomID, sourceScanID: scanID,
            coordinateSystem: metadata.coordinateSystem,
            completeness: completeness(metadata.completeness),
            vertices: vertices.sorted { $0.id.uuidString < $1.id.uuidString },
            walls: walls.sorted { $0.id.uuidString < $1.id.uuidString },
            openings: [], columns: [], beams: [],
            floorBoundary: floorBoundaries(metadata),
            endpointMerges: merges.sorted { $0.vertexID.uuidString < $1.vertexID.uuidString },
            revision: ParametricRevision(number: 1, createdAt: createdAt, source: .lidarEstimated)
        )

        let openings = metadata.surfaces
            .filter { [.door, .window, .opening].contains($0.kind) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .compactMap { surface in
                makeOpening(
                    surface, wallIDsBySource: wallIDsBySource, plan: temporary, provenance: lidar,
                    scanID: scanID
                )
            }
        return ParametricFloorPlan(
            id: temporary.id, projectID: projectID, roomID: roomID, sourceScanID: scanID,
            coordinateSystem: temporary.coordinateSystem, completeness: temporary.completeness,
            vertices: temporary.vertices, walls: temporary.walls, openings: openings,
            columns: [], beams: [], floorBoundary: temporary.floorBoundary,
            endpointMerges: temporary.endpointMerges, revision: temporary.revision
        )
    }

    private func reconcile(_ endpoints: [Endpoint]) -> [Cluster] {
        var clusters: [Cluster] = []
        for endpoint in endpoints {
            let candidates = clusters.indices.compactMap { index -> (Int, Double)? in
                let separation = endpoint.position.distance(to: clusters[index].center)
                guard separation <= reconciliation.supportedTolerance,
                      clusters[index].endpoints.allSatisfy({
                          $0.wallSourceID != endpoint.wallSourceID &&
                          supportsConnection(endpoint, $0, separation: separation)
                      }) else { return nil }
                return (index, separation)
            }
            if let selected = candidates.min(by: { $0.1 < $1.1 }) {
                clusters[selected.0].endpoints.append(endpoint)
            } else {
                clusters.append(Cluster(endpoints: [endpoint]))
            }
        }
        return clusters
    }

    private func supportsConnection(_ lhs: Endpoint, _ rhs: Endpoint, separation: Double) -> Bool {
        if separation <= reconciliation.strongPositionalTolerance { return true }
        let dot = min(abs(lhs.direction.x * rhs.direction.x + lhs.direction.y * rhs.direction.y), 1)
        return acos(dot) >= reconciliation.minimumIntersectionAngle
    }

    private func makeOpening(
        _ surface: RoomPlanGeometryMetadata.Surface,
        wallIDsBySource: [UUID: UUID],
        plan: ParametricFloorPlan,
        provenance: MeasurementProvenance,
        scanID: UUID
    ) -> WallOpening? {
        guard let parent = surface.parentIdentifier,
              let hostWallID = wallIDsBySource[parent],
              let host = plan.wall(id: hostWallID),
              let start = plan.vertex(id: host.startVertexID)?.position,
              let end = plan.vertex(id: host.endVertexID)?.position,
              let segment = surface.projectedSegment else { return nil }
        let midpoint = PlanPoint2D(
            x: (Double(segment.start.x) + Double(segment.end.x)) / 2,
            y: (Double(segment.start.y) + Double(segment.end.y)) / 2
        )
        let wallLength = start.distance(to: end)
        guard wallLength > 0 else { return nil }
        let direction = normalized(from: start, to: end)
        let offset = (midpoint.x - start.x) * direction.x + (midpoint.y - start.y) * direction.y
        let anchor = LengthMeasurement(value: offset, provenance: provenance)
        let kind: WallOpeningKind = switch surface.kind {
        case .door: .door
        case .window: .window
        default: .opening
        }
        return WallOpening(
            id: StableGeometryID.make(namespace: scanID, components: ["opening", surface.id.uuidString]),
            hostWallID: hostWallID,
            kind: kind,
            width: measurement(surface.dimensions.x, provenance: provenance),
            height: measurement(surface.dimensions.y, provenance: provenance),
            // RoomGeometryProcessor does not retain a defensible wall-relative sill elevation.
            verticalOffset: nil,
            horizontalAnchor: .distanceFromStart(anchor),
            source: sourceMetadata(
                surface,
                originalStart: point(segment.start),
                originalEnd: point(segment.end)
            )
        )
    }

    private func floorBoundaries(_ metadata: RoomPlanGeometryMetadata) -> [[PlanPoint2D]]? {
        let polygons = metadata.surfaces
            .filter { $0.kind == .floor && $0.projectedPolygon.count >= 3 }
            .map { $0.projectedPolygon.map(point) }
            .filter { $0.allSatisfy(\.isFinite) }
        return polygons.isEmpty ? nil : polygons
    }

    private func sourceMetadata(
        _ surface: RoomPlanGeometryMetadata.Surface,
        originalStart: PlanPoint2D?,
        originalEnd: PlanPoint2D?
    ) -> GeometrySourceMetadata {
        GeometrySourceMetadata(
            sourceElementID: surface.id, confidence: surface.confidence,
            originalStart: originalStart, originalEnd: originalEnd, transform: surface.transform
        )
    }

    private func measurement(
        _ value: Double,
        provenance: MeasurementProvenance
    ) -> LengthMeasurement? {
        value.isFinite && value > 0 ? LengthMeasurement(value: value, provenance: provenance) : nil
    }

    private func completeness(
        _ value: RoomPlanGeometryMetadata.Completeness
    ) -> ParametricGeometryCompleteness {
        switch value {
        case .complete: .complete
        case .incomplete: .partial
        case .empty: .empty
        }
    }

    private func point(_ value: CGPoint?) -> PlanPoint2D? {
        value.map(point)
    }

    private func point(_ value: CGPoint) -> PlanPoint2D {
        PlanPoint2D(x: Double(value.x), y: Double(value.y))
    }

    private func finite(_ value: CGPoint) -> Bool {
        value.x.isFinite && value.y.isFinite
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        hypot(Double(rhs.x - lhs.x), Double(rhs.y - lhs.y))
    }

    private func normalized(from start: PlanPoint2D, to end: PlanPoint2D) -> PlanPoint2D {
        let length = max(start.distance(to: end), .leastNonzeroMagnitude)
        return PlanPoint2D(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
    }

    private func weakestConfidence(
        _ values: [RoomGeometrySource.Confidence]
    ) -> RoomGeometrySource.Confidence {
        let rank: [RoomGeometrySource.Confidence: Int] = [.unknown: 0, .low: 1, .medium: 2, .high: 3]
        return values.min { rank[$0, default: 0] < rank[$1, default: 0] } ?? .unknown
    }

    private func maximumSeparation(_ points: [PlanPoint2D]) -> Double {
        points.indices.reduce(0) { maximum, first in
            points.indices.dropFirst(first + 1).reduce(maximum) { current, second in
                max(current, points[first].distance(to: points[second]))
            }
        }
    }
}

enum StableGeometryID {
    static func make(namespace: UUID, components: [String]) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        bytes.append(components.joined(separator: "|").data(using: .utf8) ?? Data())
        var digest = Array(SHA256.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
