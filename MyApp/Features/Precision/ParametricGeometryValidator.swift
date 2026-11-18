import Foundation

enum GeometryValidationSeverity: String, Codable, Sendable {
    case warning
    case error
}

enum GeometryValidationCode: String, Codable, Sendable {
    case duplicateIdentifier
    case missingVertex
    case nonfiniteCoordinate
    case zeroLengthWall
    case invalidDimension
    case invalidOpeningHost
    case openingOutsideHost
    case duplicateConnection
    case unconnectedEndpoint
    case openChain
    case degenerateFloorBoundary
    case inconsistentSourceMetadata
    case invalidOpeningMeasurement
    case overlappingOpenings
    case inconsistentMeasurementChain
    case invalidOpeningReference
    case invalidVerticalMeasurement
    case invalidColumnGeometry
    case invalidStructuralReference
    case invalidBeamGeometry
    case inconsistentStructuralMeasurement
    case incompleteStructuralGeometry
}

struct GeometryValidationIssue: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let severity: GeometryValidationSeverity
    let code: GeometryValidationCode
    let entityID: UUID?
    let detail: String
}

struct GeometryValidationResult: Codable, Hashable, Sendable {
    let issues: [GeometryValidationIssue]
    var errors: [GeometryValidationIssue] { issues.filter { $0.severity == .error } }
    var warnings: [GeometryValidationIssue] { issues.filter { $0.severity == .warning } }
    var isValid: Bool { errors.isEmpty }
}

struct ParametricGeometryValidator {
    let minimumWallLength: Double

    init(minimumWallLength: Double = 0.001) {
        self.minimumWallLength = minimumWallLength
    }

    func validate(_ plan: ParametricFloorPlan) -> GeometryValidationResult {
        var issues: [GeometryValidationIssue] = []
        let columnReferenceIDs = plan.columns.flatMap {
            $0.architecturalMetadata?.references.map(\.id) ?? []
        }
        let columnMeasurementIDs = plan.columns.flatMap {
            $0.architecturalMetadata?.measurements.map(\.id) ?? []
        }
        let beamMeasurementIDs = plan.beams.flatMap {
            $0.architecturalMetadata?.measurements.map(\.id) ?? []
        }
        var allIDs = plan.vertices.map(\.id)
        allIDs += plan.walls.map(\.id)
        allIDs += plan.openings.map(\.id)
        allIDs += plan.columns.map(\.id)
        allIDs += plan.beams.map(\.id)
        allIDs += columnReferenceIDs + columnMeasurementIDs + beamMeasurementIDs
        for id in duplicateIDs(allIDs) {
            append(.error, .duplicateIdentifier, id, "Duplicate geometry identifier.", to: &issues)
        }

        let vertices = plan.vertices.reduce(into: [UUID: PlanVertex]()) { result, vertex in
            if result[vertex.id] == nil { result[vertex.id] = vertex }
        }
        for vertex in plan.vertices where !vertex.position.isFinite {
            append(.error, .nonfiniteCoordinate, vertex.id, "Vertex coordinate is not finite.", to: &issues)
        }

        var connections: Set<String> = []
        var degree: [UUID: Int] = [:]
        for wall in plan.walls {
            guard let start = vertices[wall.startVertexID], let end = vertices[wall.endVertexID] else {
                append(.error, .missingVertex, wall.id, "Wall references a missing vertex.", to: &issues)
                continue
            }
            let length = start.position.distance(to: end.position)
            if !length.isFinite || length < minimumWallLength {
                append(.error, .zeroLengthWall, wall.id, "Wall has zero or invalid length.", to: &issues)
            }
            validate(wall.height, entityID: wall.id, into: &issues)
            validate(wall.thickness, entityID: wall.id, into: &issues)
            if wall.source.sourceElementID == nil {
                append(.warning, .inconsistentSourceMetadata, wall.id,
                       "Wall has no source element identifier.", to: &issues)
            }
            let key = [wall.startVertexID.uuidString, wall.endVertexID.uuidString].sorted().joined(separator: ":")
            if !connections.insert(key).inserted {
                append(.error, .duplicateConnection, wall.id, "Duplicate wall connection.", to: &issues)
            }
            degree[wall.startVertexID, default: 0] += 1
            degree[wall.endVertexID, default: 0] += 1
        }

        for vertex in plan.vertices {
            let count = degree[vertex.id, default: 0]
            if count == 0 {
                append(.warning, .unconnectedEndpoint, vertex.id, "Vertex is not connected to a wall.", to: &issues)
            } else if count == 1 {
                append(.warning, .openChain, vertex.id, "Wall chain ends at this vertex.", to: &issues)
            }
        }

        let walls = plan.walls.reduce(into: [UUID: ParametricWall]()) { result, wall in
            if result[wall.id] == nil { result[wall.id] = wall }
        }
        for opening in plan.openings {
            guard let host = walls[opening.hostWallID] else {
                append(.error, .invalidOpeningHost, opening.id, "Opening host wall is missing.", to: &issues)
                continue
            }
            validate(opening.width, entityID: opening.id, into: &issues)
            validate(opening.height, entityID: opening.id, into: &issues)
            validate(opening.verticalOffset, entityID: opening.id, allowsZero: true, into: &issues)
            let offset: Double
            switch opening.horizontalAnchor {
            case .distanceFromStart(let value):
                validate(value, entityID: opening.id, allowsZero: true, into: &issues)
                offset = value.value
            }
            if let hostLength = host.length(in: plan),
               !offset.isFinite || offset < 0 || offset > hostLength {
                append(.error, .openingOutsideHost, opening.id,
                       "Opening anchor lies outside the host wall.", to: &issues)
            }
        }

        if let boundaries = plan.floorBoundary {
            for (index, polygon) in boundaries.enumerated()
            where polygon.count < 3 || !polygon.allSatisfy(\.isFinite) || abs(area(polygon)) < 0.0001 {
                append(.warning, .degenerateFloorBoundary, nil,
                       "Floor boundary \(index) is degenerate.", to: &issues)
            }
        }
        let openingResolution = OpeningMeasurementResolver().resolve(plan: plan)
        for conflict in openingResolution.conflicts {
            let code: GeometryValidationCode = switch conflict.code {
            case .overlappingOpenings: .overlappingOpenings
            case .contradictoryMeasurements: .inconsistentMeasurementChain
            case .invalidReference: .invalidOpeningReference
            case .invalidVerticalChain, .exceedsWallHeight: .invalidVerticalMeasurement
            default: .invalidOpeningMeasurement
            }
            append(.error, code, conflict.openingIDs.first,
                   "Opening measurement conflict: \(conflict.code.rawValue).", to: &issues)
        }
        for openingID in openingResolution.unresolvedOpeningIDs {
            append(.warning, .invalidOpeningMeasurement, openingID,
                   "Opening placement is underdetermined.", to: &issues)
        }
        validateStructuralGeometry(plan, vertices: vertices, walls: walls, into: &issues)
        return GeometryValidationResult(issues: issues)
    }

    private func validateStructuralGeometry(
        _ plan: ParametricFloorPlan,
        vertices: [UUID: PlanVertex],
        walls: [UUID: ParametricWall],
        into issues: inout [GeometryValidationIssue]
    ) {
        for column in plan.columns {
            if !column.position.isFinite || !column.orientation.isFinite {
                append(.error, .invalidColumnGeometry, column.id,
                       "Column position or rotation is not finite.", to: &issues)
            }
            validate(column.width, entityID: column.id, into: &issues)
            validate(column.depth, entityID: column.id, into: &issues)
            validate(column.height, entityID: column.id, into: &issues)
            if let metadata = column.architecturalMetadata {
                if metadata.shape == .square,
                   abs(column.width.value - column.depth.value) > 0.000_1 {
                    append(.error, .invalidColumnGeometry, column.id,
                           "Square column width and depth differ.", to: &issues)
                }
                if metadata.shape == .circular,
                   abs(column.width.value - column.depth.value) > 0.000_1 {
                    append(.error, .invalidColumnGeometry, column.id,
                           "Circular column diameter is inconsistent.", to: &issues)
                }
                for reference in metadata.references {
                    switch reference.entity {
                    case .wall(let id, _, _) where walls[id] == nil,
                         .vertex(let id) where vertices[id] == nil:
                        append(.error, .invalidStructuralReference, column.id,
                               "Column reference entity is missing.", to: &issues)
                    case .unresolved:
                        append(.warning, .incompleteStructuralGeometry, column.id,
                               "Column reference is unresolved.", to: &issues)
                    default: break
                    }
                }
                let referenceIDs = Set(metadata.references.map(\.id))
                for measurement in metadata.measurements {
                    if measurement.columnID != column.id
                        || (measurement.referenceID.map { !referenceIDs.contains($0) } ?? false) {
                        append(.error, .invalidStructuralReference, column.id,
                               "Column measurement target or reference is invalid.", to: &issues)
                    }
                }
                if let base = metadata.baseElevation {
                    validate(base, entityID: column.id, allowsZero: true, into: &issues)
                }
            }
        }

        for beam in plan.beams {
            validate(beam.width, entityID: beam.id, into: &issues)
            validate(beam.depth, entityID: beam.id, into: &issues)
            validate(beam.bottomElevation, entityID: beam.id, allowsZero: true, into: &issues)
            for anchor in [beam.start, beam.end] {
                switch anchor {
                case .vertex(let id) where vertices[id] == nil:
                    append(.error, .invalidStructuralReference, beam.id,
                           "Beam endpoint vertex is missing.", to: &issues)
                case .point(let point) where !point.isFinite:
                    append(.error, .invalidBeamGeometry, beam.id,
                           "Beam endpoint is not finite.", to: &issues)
                case .unresolved:
                    append(.warning, .incompleteStructuralGeometry, beam.id,
                           "Beam endpoint is unresolved.", to: &issues)
                default: break
                }
            }
            if let metadata = beam.architecturalMetadata {
                for measurement in metadata.measurements where measurement.beamID != beam.id {
                    append(.error, .invalidStructuralReference, beam.id,
                           "Beam measurement target is invalid.", to: &issues)
                }
            }
        }

        let structural = StructuralGeometryResolver().resolve(plan: plan)
        for issue in structural.conflicts {
            let code: GeometryValidationCode = switch issue.code {
            case .missingReference, .missingEntity: .invalidStructuralReference
            case .invalidBeamGeometry, .invalidVerticalChain: .invalidBeamGeometry
            case .invalidMeasurement: .invalidDimension
            case .underdeterminedPlacement: .incompleteStructuralGeometry
            case .contradictoryReferences, .verifiedMeasurementConflict: .inconsistentStructuralMeasurement
            }
            append(.error, code, issue.entityIDs.first,
                   "Structural measurement conflict: \(issue.code.rawValue).", to: &issues)
        }
        for id in structural.unresolvedEntityIDs {
            append(.warning, .incompleteStructuralGeometry, id,
                   "Structural placement is underdetermined.", to: &issues)
        }
    }

    private func validate(
        _ measurement: LengthMeasurement?,
        entityID: UUID,
        allowsZero: Bool = false,
        into issues: inout [GeometryValidationIssue]
    ) {
        guard let measurement else { return }
        let valid = measurement.value.isFinite && (allowsZero ? measurement.value >= 0 : measurement.value > 0)
        if !valid || (measurement.provenance.uncertainty.map { !$0.isFinite || $0 < 0 } ?? false) {
            append(.error, .invalidDimension, entityID, "Measurement is invalid.", to: &issues)
        }
    }

    private func duplicateIDs(_ ids: [UUID]) -> Set<UUID> {
        var seen: Set<UUID> = []
        return ids.reduce(into: Set<UUID>()) { duplicates, id in
            if !seen.insert(id).inserted { duplicates.insert(id) }
        }
    }

    private func area(_ polygon: [PlanPoint2D]) -> Double {
        polygon.indices.reduce(0) { result, index in
            let next = polygon[(index + 1) % polygon.count]
            return result + polygon[index].x * next.y - next.x * polygon[index].y
        } / 2
    }

    private func append(
        _ severity: GeometryValidationSeverity,
        _ code: GeometryValidationCode,
        _ entityID: UUID?,
        _ detail: String,
        to issues: inout [GeometryValidationIssue]
    ) {
        let suffix = entityID?.uuidString ?? String(issues.count)
        issues.append(GeometryValidationIssue(
            id: "\(code.rawValue):\(suffix)", severity: severity, code: code,
            entityID: entityID, detail: detail
        ))
    }
}
