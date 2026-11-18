import CoreGraphics
import Foundation

enum StructuralCreationKind: String, CaseIterable, Identifiable, Sendable {
    case column
    case beam

    var id: Self { self }
}

enum StructuralPlacementStep: Equatable, Sendable {
    case idle
    case columnPoint
    case beamStart
    case beamEnd
    case dimensions
}

struct StructuralCreationDraft: Equatable, Sendable {
    var kind: StructuralCreationKind?
    var columnShape: ColumnShape = .rectangular
    var placementStep: StructuralPlacementStep = .idle
    var columnPosition: PlanPoint2D?
    var beamStart: PlanPoint2D?
    var beamEnd: PlanPoint2D?
    var widthMillimeters = ""
    var depthMillimeters = ""
    var heightMillimeters = ""
    var rotationDegrees = ""
    var baseElevationMillimeters = ""
    var bottomElevationMillimeters = ""
    var topElevationMillimeters = ""
    var isSaving = false

    mutating func beginColumn(shape: ColumnShape) {
        self = .init(kind: .column, columnShape: shape, placementStep: .columnPoint)
    }

    mutating func beginBeam() {
        self = .init(kind: .beam, placementStep: .beamStart)
    }

    mutating func place(_ point: PlanPoint2D) {
        switch placementStep {
        case .columnPoint:
            columnPosition = point
            placementStep = .dimensions
        case .beamStart:
            beamStart = point
            placementStep = .beamEnd
        case .beamEnd:
            beamEnd = point
            placementStep = .dimensions
        default:
            break
        }
    }

    var isPlacing: Bool {
        [.columnPoint, .beamStart, .beamEnd].contains(placementStep)
    }
}

enum StructuralCreationError: Error, Equatable {
    case missingPlacement
    case invalidDimension
    case degenerateBeam
    case invalidGeometry([GeometryValidationIssue])
}

struct StructuralCreationCandidate: Sendable {
    let plan: ParametricFloorPlan
    let createdID: UUID
    let kind: StructuralCreationKind
}

struct StructuralCreationEngine {
    private let minimumDimension = 0.001

    func candidate(
        from draft: StructuralCreationDraft,
        in plan: ParametricFloorPlan,
        id: UUID = UUID()
    ) -> Result<StructuralCreationCandidate, StructuralCreationError> {
        guard let kind = draft.kind else { return .failure(.missingPlacement) }
        let provenance = MeasurementProvenance(
            source: .manualEntered,
            verificationStatus: .unverified,
            timestamp: Date(),
            uncertainty: nil
        )
        let source = GeometrySourceMetadata(
            sourceElementID: nil,
            confidence: .low,
            originalStart: nil,
            originalEnd: nil,
            transform: nil
        )
        var candidate = plan

        switch kind {
        case .column:
            guard let position = draft.columnPosition else { return .failure(.missingPlacement) }
            guard let first = meters(draft.widthMillimeters), first >= minimumDimension else {
                return .failure(.invalidDimension)
            }
            let width: Double
            let depth: Double
            switch draft.columnShape {
            case .rectangular:
                guard let second = meters(draft.depthMillimeters), second >= minimumDimension else {
                    return .failure(.invalidDimension)
                }
                width = first
                depth = second
            case .square, .circular:
                width = first
                depth = first
            }
            let height = optionalMeters(draft.heightMillimeters).map {
                LengthMeasurement(value: $0, provenance: provenance)
            }
            let rotation = optionalDegrees(draft.rotationDegrees) ?? 0
            let baseElevation = optionalMeters(draft.baseElevationMillimeters).map {
                LengthMeasurement(value: $0, provenance: provenance)
            }
            let measurements = columnMeasurements(
                id: id,
                shape: draft.columnShape,
                width: width,
                depth: depth,
                height: height?.value,
                rotation: draft.rotationDegrees.isEmpty ? nil : rotation,
                baseElevation: baseElevation?.value,
                provenance: provenance
            )
            candidate.columns.append(ParametricColumn(
                id: id,
                position: position,
                width: .init(value: width, provenance: provenance),
                depth: .init(value: depth, provenance: provenance),
                height: height,
                orientation: rotation,
                referenceVertexIDs: [],
                architecturalMetadata: .init(
                    shape: draft.columnShape,
                    measurements: measurements,
                    references: [],
                    baseElevation: baseElevation,
                    completeness: height == nil ? .partial : .complete,
                    source: source
                )
            ))
        case .beam:
            guard let start = draft.beamStart, let end = draft.beamEnd else {
                return .failure(.missingPlacement)
            }
            let length = start.distance(to: end)
            guard length.isFinite, length >= minimumDimension else { return .failure(.degenerateBeam) }
            guard let width = meters(draft.widthMillimeters), width >= minimumDimension,
                  let depth = meters(draft.depthMillimeters), depth >= minimumDimension else {
                return .failure(.invalidDimension)
            }
            let bottom = optionalMeters(draft.bottomElevationMillimeters).map {
                LengthMeasurement(value: $0, provenance: provenance)
            }
            var measurements: [BeamMeasurement] = [
                beamMeasurement(id, .width, width, provenance),
                beamMeasurement(id, .depth, depth, provenance),
                .init(
                    id: UUID(), beamID: id, kind: .length,
                    value: .init(
                        value: length,
                        unit: .meters,
                        provenance: .init(source: .derived, verificationStatus: .unverified, timestamp: Date(), uncertainty: nil)
                    ),
                    referenceID: nil
                )
            ]
            if let bottom {
                measurements.append(beamMeasurement(id, .bottomElevation, bottom.value, provenance))
            }
            if let top = optionalMeters(draft.topElevationMillimeters) {
                measurements.append(beamMeasurement(id, .topElevation, top, provenance))
            }
            candidate.beams.append(ParametricBeam(
                id: id,
                start: .point(start),
                end: .point(end),
                width: .init(value: width, provenance: provenance),
                depth: .init(value: depth, provenance: provenance),
                bottomElevation: bottom,
                architecturalMetadata: .init(
                    measurements: measurements,
                    references: [],
                    startReference: .init(entity: .unresolved, reliability: .unresolved),
                    endReference: .init(entity: .unresolved, reliability: .unresolved),
                    verifiedSupportEntityIDs: nil,
                    completeness: bottom == nil ? .partial : .complete,
                    source: source
                )
            ))
        }

        candidate.revision = .init(
            number: plan.revision.number + 1,
            createdAt: Date(),
            source: .manualEntered
        )
        let validation = ParametricGeometryValidator().validate(candidate)
        guard validation.isValid else { return .failure(.invalidGeometry(validation.errors)) }
        return .success(.init(plan: candidate, createdID: id, kind: kind))
    }

    private func meters(_ text: String) -> Double? {
        PrecisionMeasurementInput.meters(fromMillimeters: text)
    }

    private func optionalMeters(_ text: String) -> Double? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : meters(text)
    }

    private func optionalDegrees(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value * .pi / 180
    }

    private func columnMeasurements(
        id: UUID,
        shape: ColumnShape,
        width: Double,
        depth: Double,
        height: Double?,
        rotation: Double?,
        baseElevation: Double?,
        provenance: MeasurementProvenance
    ) -> [ColumnMeasurement] {
        var values: [ColumnMeasurement] = []
        if shape == .circular {
            values.append(columnMeasurement(id, .diameter, width, .meters, provenance))
        } else {
            values.append(columnMeasurement(id, .width, width, .meters, provenance))
            values.append(columnMeasurement(id, .depth, depth, .meters, provenance))
        }
        if let height { values.append(columnMeasurement(id, .height, height, .meters, provenance)) }
        if let rotation { values.append(columnMeasurement(id, .rotation, rotation, .radians, provenance)) }
        if let baseElevation { values.append(columnMeasurement(id, .baseElevation, baseElevation, .meters, provenance)) }
        return values
    }

    private func columnMeasurement(
        _ id: UUID,
        _ kind: ColumnMeasurementKind,
        _ value: Double,
        _ unit: StructuralMeasurementUnit,
        _ provenance: MeasurementProvenance
    ) -> ColumnMeasurement {
        .init(id: UUID(), columnID: id, kind: kind,
              value: .init(value: value, unit: unit, provenance: provenance), referenceID: nil)
    }

    private func beamMeasurement(
        _ id: UUID,
        _ kind: BeamMeasurementKind,
        _ value: Double,
        _ provenance: MeasurementProvenance
    ) -> BeamMeasurement {
        .init(id: UUID(), beamID: id, kind: kind,
              value: .init(value: value, unit: .meters, provenance: provenance), referenceID: nil)
    }
}

struct StructuralHitTarget: Equatable, Sendable {
    let id: UUID
    let kind: StructuralCreationKind
    let bounds: CGRect
}

enum StructuralHitTesting {
    static func targets(for plan: ParametricFloorPlan, transform: CGAffineTransform) -> [StructuralHitTarget] {
        let columns = plan.columns.map { column in
            let center = CGPoint(x: column.position.x, y: column.position.y).applying(transform)
            let x = CGPoint(x: column.position.x + column.width.value / 2, y: column.position.y).applying(transform)
            let y = CGPoint(x: column.position.x, y: column.position.y + column.depth.value / 2).applying(transform)
            return StructuralHitTarget(
                id: column.id,
                kind: .column,
                bounds: CGRect(
                    x: center.x - max(center.distance(to: x), 22),
                    y: center.y - max(center.distance(to: y), 22),
                    width: max(center.distance(to: x) * 2, 44),
                    height: max(center.distance(to: y) * 2, 44)
                )
            )
        }
        let beams = plan.beams.compactMap { beam -> StructuralHitTarget? in
            guard let start = point(beam.start, plan: plan), let end = point(beam.end, plan: plan) else { return nil }
            let a = CGPoint(x: start.x, y: start.y).applying(transform)
            let b = CGPoint(x: end.x, y: end.y).applying(transform)
            return .init(
                id: beam.id,
                kind: .beam,
                bounds: CGRect(
                    x: min(a.x, b.x) - 22, y: min(a.y, b.y) - 22,
                    width: max(abs(a.x - b.x), 44), height: max(abs(a.y - b.y), 44)
                )
            )
        }
        return columns + beams
    }

    static func selected(at point: CGPoint, targets: [StructuralHitTarget]) -> StructuralHitTarget? {
        targets.last { $0.bounds.contains(point) }
    }

    private static func point(_ anchor: BeamAnchor, plan: ParametricFloorPlan) -> PlanPoint2D? {
        switch anchor {
        case .point(let point): point
        case .vertex(let id): plan.vertex(id: id)?.position
        case .unresolved: nil
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
}
