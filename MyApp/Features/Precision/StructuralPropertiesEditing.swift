import Foundation

struct StructuralPropertiesDraft: Equatable, Sendable {
    let id: UUID
    let kind: StructuralCreationKind
    let shape: ColumnShape?
    var widthMillimeters: String
    var depthMillimeters: String
    var heightMillimeters: String
    var rotationDegrees: String
    var baseElevationMillimeters: String
    var positionXMillimeters: String
    var positionYMillimeters: String
    var startXMillimeters: String
    var startYMillimeters: String
    var endXMillimeters: String
    var endYMillimeters: String
    var bottomElevationMillimeters: String
    var topElevationMillimeters: String
    var laserVerified = false
    var isSaving = false

    static func make(column: ParametricColumn) -> Self {
        .init(
            id: column.id,
            kind: .column,
            shape: column.architecturalMetadata?.shape ?? .rectangular,
            widthMillimeters: millimeters(column.width.value),
            depthMillimeters: millimeters(column.depth.value),
            heightMillimeters: optionalMillimeters(column.height?.value),
            rotationDegrees: decimal(column.orientation * 180 / .pi),
            baseElevationMillimeters: optionalMillimeters(column.architecturalMetadata?.baseElevation?.value),
            positionXMillimeters: millimeters(column.position.x),
            positionYMillimeters: millimeters(column.position.y),
            startXMillimeters: "", startYMillimeters: "", endXMillimeters: "", endYMillimeters: "",
            bottomElevationMillimeters: "", topElevationMillimeters: ""
        )
    }

    static func make(beam: ParametricBeam, in plan: ParametricFloorPlan) -> Self? {
        guard let start = point(beam.start, plan: plan), let end = point(beam.end, plan: plan) else { return nil }
        let top = beam.architecturalMetadata?.measurements.first(where: { $0.kind == .topElevation })?.value.value
        return .init(
            id: beam.id,
            kind: .beam,
            shape: nil,
            widthMillimeters: millimeters(beam.width.value),
            depthMillimeters: millimeters(beam.depth.value),
            heightMillimeters: "", rotationDegrees: "", baseElevationMillimeters: "",
            positionXMillimeters: "", positionYMillimeters: "",
            startXMillimeters: millimeters(start.x), startYMillimeters: millimeters(start.y),
            endXMillimeters: millimeters(end.x), endYMillimeters: millimeters(end.y),
            bottomElevationMillimeters: optionalMillimeters(beam.bottomElevation?.value),
            topElevationMillimeters: optionalMillimeters(top)
        )
    }

    private static func point(_ anchor: BeamAnchor, plan: ParametricFloorPlan) -> PlanPoint2D? {
        switch anchor {
        case .point(let point): point
        case .vertex(let id): plan.vertex(id: id)?.position
        case .unresolved: nil
        }
    }

    private static func millimeters(_ meters: Double) -> String { decimal(meters * 1_000) }
    private static func optionalMillimeters(_ meters: Double?) -> String { meters.map(millimeters) ?? "" }
    private static func decimal(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

enum StructuralPropertiesError: Error, Equatable {
    case missingElement
    case invalidDimension
    case invalidPosition
    case verticalConflict
    case invalidGeometry([GeometryValidationIssue])
}

struct StructuralPropertiesPreview: Sendable {
    let plan: ParametricFloorPlan
    let changed: Bool
}

struct StructuralPropertiesEngine {
    private let tolerance = 0.000_001

    func preview(
        draft: StructuralPropertiesDraft,
        in plan: ParametricFloorPlan
    ) -> Result<StructuralPropertiesPreview, StructuralPropertiesError> {
        var candidate = plan
        let provenance = MeasurementProvenance(
            source: draft.laserVerified ? .laserVerified : .manualEntered,
            verificationStatus: draft.laserVerified ? .verified : .unverified,
            timestamp: Date(), uncertainty: nil
        )
        switch draft.kind {
        case .column:
            guard let index = candidate.columns.firstIndex(where: { $0.id == draft.id }) else {
                return .failure(.missingElement)
            }
            if draft.hasSameMeasurements(as: .make(column: candidate.columns[index])) {
                return .success(.init(plan: plan, changed: false))
            }
            guard let width = meters(draft.widthMillimeters), width > 0,
                  let x = meters(draft.positionXMillimeters),
                  let y = meters(draft.positionYMillimeters),
                  let rotation = degrees(draft.rotationDegrees) else {
                return .failure(.invalidDimension)
            }
            let shape = candidate.columns[index].architecturalMetadata?.shape ?? draft.shape ?? .rectangular
            let depth: Double
            if shape == .rectangular {
                guard let parsed = meters(draft.depthMillimeters), parsed > 0 else {
                    return .failure(.invalidDimension)
                }
                depth = parsed
            } else {
                depth = width
            }
            guard x.isFinite, y.isFinite else { return .failure(.invalidPosition) }
            let height = optionalMeters(draft.heightMillimeters)
            let base = optionalMeters(draft.baseElevationMillimeters)
            if draft.heightMillimeters.isEmpty == false && height == nil { return .failure(.invalidDimension) }
            if draft.baseElevationMillimeters.isEmpty == false && base == nil { return .failure(.invalidDimension) }

            var column = candidate.columns[index]
            column.position = .init(x: x, y: y)
            column.width = revised(column.width, value: width, provenance: provenance)
            column.depth = revised(column.depth, value: depth, provenance: provenance)
            column.height = revisedOptional(column.height, value: height, provenance: provenance)
            column.orientation = rotation
            if var metadata = column.architecturalMetadata {
                metadata.baseElevation = revisedOptional(metadata.baseElevation, value: base, provenance: provenance)
                metadata.measurements = revisedColumnMeasurements(
                    metadata.measurements, columnID: column.id, shape: shape,
                    width: width, depth: depth, height: height, rotation: rotation,
                    base: base, provenance: provenance
                )
                metadata.completeness = height == nil ? .partial : .complete
                column.architecturalMetadata = metadata
            }
            candidate.columns[index] = column
        case .beam:
            guard let index = candidate.beams.firstIndex(where: { $0.id == draft.id }) else {
                return .failure(.missingElement)
            }
            if let currentDraft = StructuralPropertiesDraft.make(beam: candidate.beams[index], in: candidate),
               draft.hasSameMeasurements(as: currentDraft) {
                return .success(.init(plan: plan, changed: false))
            }
            guard let width = meters(draft.widthMillimeters), width > 0,
                  let depth = meters(draft.depthMillimeters), depth > 0,
                  let startX = meters(draft.startXMillimeters), let startY = meters(draft.startYMillimeters),
                  let endX = meters(draft.endXMillimeters), let endY = meters(draft.endYMillimeters) else {
                return .failure(.invalidDimension)
            }
            let start = PlanPoint2D(x: startX, y: startY)
            let end = PlanPoint2D(x: endX, y: endY)
            guard start.isFinite, end.isFinite, start.distance(to: end) > 0.001 else {
                return .failure(.invalidPosition)
            }
            let bottom = optionalMeters(draft.bottomElevationMillimeters)
            let top = optionalMeters(draft.topElevationMillimeters)
            if draft.bottomElevationMillimeters.isEmpty == false && bottom == nil { return .failure(.invalidDimension) }
            if draft.topElevationMillimeters.isEmpty == false && top == nil { return .failure(.invalidDimension) }
            if let bottom, let top, abs(bottom + depth - top) > tolerance {
                return .failure(.verticalConflict)
            }

            var beam = candidate.beams[index]
            beam.start = .point(start)
            beam.end = .point(end)
            beam.width = revised(beam.width, value: width, provenance: provenance)
            beam.depth = revised(beam.depth, value: depth, provenance: provenance)
            beam.bottomElevation = revisedOptional(beam.bottomElevation, value: bottom, provenance: provenance)
            if var metadata = beam.architecturalMetadata {
                metadata.measurements = revisedBeamMeasurements(
                    metadata.measurements, beamID: beam.id, length: start.distance(to: end),
                    width: width, depth: depth, bottom: bottom, top: top, provenance: provenance
                )
                metadata.startReference = .init(entity: .unresolved, reliability: .unresolved)
                metadata.endReference = .init(entity: .unresolved, reliability: .unresolved)
                metadata.completeness = bottom == nil ? .partial : .complete
                beam.architecturalMetadata = metadata
            }
            candidate.beams[index] = beam
        }

        let changed = candidate.columns != plan.columns || candidate.beams != plan.beams
        guard changed else { return .success(.init(plan: plan, changed: false)) }
        candidate.revision = .init(number: plan.revision.number + 1, createdAt: Date(), source: .manualEntered)
        let validation = ParametricGeometryValidator().validate(candidate)
        guard validation.isValid else { return .failure(.invalidGeometry(validation.errors)) }
        return .success(.init(plan: candidate, changed: true))
    }

    private func meters(_ text: String) -> Double? {
        PrecisionMeasurementInput.meters(fromMillimeters: text)
    }

    private func optionalMeters(_ text: String) -> Double? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : meters(text)
    }

    private func degrees(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? 0 : Double(text.replacingOccurrences(of: ",", with: "."))
        guard let value, value.isFinite else { return nil }
        return value * .pi / 180
    }

    private func revised(
        _ current: LengthMeasurement,
        value: Double,
        provenance: MeasurementProvenance
    ) -> LengthMeasurement {
        abs(current.value - value) <= tolerance ? current : .init(value: value, provenance: provenance)
    }

    private func revisedOptional(
        _ current: LengthMeasurement?,
        value: Double?,
        provenance: MeasurementProvenance
    ) -> LengthMeasurement? {
        guard let value else { return nil }
        guard let current else { return .init(value: value, provenance: provenance) }
        return revised(current, value: value, provenance: provenance)
    }

    private func revisedColumnMeasurements(
        _ current: [ColumnMeasurement], columnID: UUID, shape: ColumnShape,
        width: Double, depth: Double, height: Double?, rotation: Double,
        base: Double?, provenance: MeasurementProvenance
    ) -> [ColumnMeasurement] {
        let values: [(ColumnMeasurementKind, Double?, StructuralMeasurementUnit)] = [
            (shape == .circular ? .diameter : .width, width, .meters),
            (shape == .circular ? .width : .depth, shape == .circular ? nil : depth, .meters),
            (.height, height, .meters), (.rotation, rotation, .radians), (.baseElevation, base, .meters)
        ]
        let kinds = Set(values.map(\.0))
        var result = current.filter { !kinds.contains($0.kind) }
        for (kind, value, unit) in values {
            guard let value else { continue }
            if let existing = current.first(where: { $0.kind == kind }),
               abs(existing.value.value - value) <= tolerance {
                result.append(existing)
            } else {
                result.append(.init(id: UUID(), columnID: columnID, kind: kind,
                                    value: .init(value: value, unit: unit, provenance: provenance), referenceID: nil))
            }
        }
        return result
    }

    private func revisedBeamMeasurements(
        _ current: [BeamMeasurement], beamID: UUID, length: Double,
        width: Double, depth: Double, bottom: Double?, top: Double?,
        provenance: MeasurementProvenance
    ) -> [BeamMeasurement] {
        let derived = MeasurementProvenance(source: .derived, verificationStatus: .unverified, timestamp: Date(), uncertainty: nil)
        let values: [(BeamMeasurementKind, Double?, MeasurementProvenance)] = [
            (.length, length, derived), (.width, width, provenance), (.depth, depth, provenance),
            (.bottomElevation, bottom, provenance), (.topElevation, top, provenance)
        ]
        let kinds = Set(values.map(\.0))
        var result = current.filter { !kinds.contains($0.kind) }
        for (kind, value, source) in values {
            guard let value else { continue }
            if let existing = current.first(where: { $0.kind == kind }),
               abs(existing.value.value - value) <= tolerance {
                result.append(existing)
            } else {
                result.append(.init(id: UUID(), beamID: beamID, kind: kind,
                                    value: .init(value: value, unit: .meters, provenance: source), referenceID: nil))
            }
        }
        return result
    }
}

private extension StructuralPropertiesDraft {
    func hasSameMeasurements(as other: Self) -> Bool {
        id == other.id && kind == other.kind && shape == other.shape
            && widthMillimeters == other.widthMillimeters
            && depthMillimeters == other.depthMillimeters
            && heightMillimeters == other.heightMillimeters
            && rotationDegrees == other.rotationDegrees
            && baseElevationMillimeters == other.baseElevationMillimeters
            && positionXMillimeters == other.positionXMillimeters
            && positionYMillimeters == other.positionYMillimeters
            && startXMillimeters == other.startXMillimeters
            && startYMillimeters == other.startYMillimeters
            && endXMillimeters == other.endXMillimeters
            && endYMillimeters == other.endYMillimeters
            && bottomElevationMillimeters == other.bottomElevationMillimeters
            && topElevationMillimeters == other.topElevationMillimeters
    }
}
