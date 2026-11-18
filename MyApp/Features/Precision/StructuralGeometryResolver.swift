import Foundation

struct StructuralGeometryResolver: Sendable {
    let computationalTolerance: Double

    init(computationalTolerance: Double = 0.000_1) {
        self.computationalTolerance = computationalTolerance
    }

    func resolve(plan: ParametricFloorPlan) -> StructuralResolutionResult {
        var candidate = plan
        var placements: [ResolvedColumnPlacement] = []
        var beams: [ResolvedBeamGeometry] = []
        var conflicts: [StructuralConflict] = []
        var unresolved: [UUID] = []

        for index in candidate.columns.indices {
            let original = candidate.columns[index]
            let result = resolveColumn(original, in: candidate)
            conflicts += result.conflicts
            if let position = result.position {
                candidate.columns[index].position = position
                placements.append(.init(columnID: original.id, position: position))
            } else if original.architecturalMetadata != nil {
                unresolved.append(original.id)
            }
            applyColumnMeasurements(to: &candidate.columns[index], conflicts: &conflicts)
        }

        for index in candidate.beams.indices {
            applyBeamMeasurements(to: &candidate.beams[index], conflicts: &conflicts)
            let beam = candidate.beams[index]
            let result = resolveBeam(beam, in: candidate)
            conflicts += result.conflicts
            if let geometry = result.geometry {
                beams.append(geometry)
            } else if beam.architecturalMetadata != nil || isUnresolved(beam.start) || isUnresolved(beam.end) {
                unresolved.append(beam.id)
            }
        }

        return StructuralResolutionResult(
            candidatePlan: candidate,
            columnPlacements: placements,
            beamGeometries: beams,
            conflicts: conflicts,
            unresolvedEntityIDs: Array(Set(unresolved))
        )
    }

    private func resolveColumn(
        _ column: ParametricColumn,
        in plan: ParametricFloorPlan
    ) -> (position: PlanPoint2D?, conflicts: [StructuralConflict]) {
        guard let metadata = column.architecturalMetadata else {
            return (column.position.isFinite ? column.position : nil, [])
        }
        let foreignMeasurements = metadata.measurements.filter { $0.columnID != column.id }
        let offsets = authoritativeMeasurements(metadata.measurements.filter {
            $0.columnID == column.id && $0.kind == .offset
        })
        var conflicts = Dictionary(grouping: offsets, by: \ColumnMeasurement.referenceID)
            .values
            .flatMap { duplicateVerifiedConflicts($0, entityID: column.id) }
        conflicts += foreignMeasurements.map {
            conflict(.invalidMeasurement, entity: column.id, measurements: [$0.id])
        }
        var references: [UUID: StructuralReference] = [:]
        for reference in metadata.references {
            if references.updateValue(reference, forKey: reference.id) != nil {
                conflicts.append(conflict(.invalidMeasurement, entity: column.id))
            }
        }
        let lines: [(ColumnMeasurement, OffsetLine)] = offsets.compactMap { measurement in
            guard measurement.value.unit == .meters,
                  measurement.value.value.isFinite,
                  measurement.value.value >= 0,
                  let referenceID = measurement.referenceID,
                  let reference = references[referenceID] else {
                conflicts.append(conflict(.invalidMeasurement, entity: column.id, measurements: [measurement.id]))
                return nil
            }
            guard reference.reliability != .unresolved else { return nil }
            guard let line = offsetLine(reference, distance: measurement.value.value, in: plan) else { return nil }
            return (measurement, line)
        }
        guard conflicts.isEmpty else { return (nil, conflicts) }
        guard lines.count >= 2 else { return (nil, []) }

        guard let point = intersection(lines[0].1, lines[1].1) else {
            let residual = parallelResidual(lines[0].1, lines[1].1)
            if residual > computationalTolerance,
               lines[0].0.value.provenance.verificationStatus == .verified,
               lines[1].0.value.provenance.verificationStatus == .verified {
                conflicts.append(conflict(
                    .contradictoryReferences,
                    entity: column.id,
                    measurements: [lines[0].0.id, lines[1].0.id],
                    residual: residual
                ))
            }
            return (nil, conflicts)
        }
        for (measurement, line) in lines.dropFirst(2) {
            let residual = abs(signedDistance(point, to: line))
            if residual > computationalTolerance,
               measurement.value.provenance.verificationStatus == .verified {
                conflicts.append(conflict(
                    .contradictoryReferences,
                    entity: column.id,
                    measurements: [measurement.id],
                    residual: residual
                ))
            }
        }
        return conflicts.isEmpty ? (point, []) : (nil, conflicts)
    }

    private func applyColumnMeasurements(
        to column: inout ParametricColumn,
        conflicts: inout [StructuralConflict]
    ) {
        guard let metadata = column.architecturalMetadata else { return }
        for measurement in metadata.measurements where measurement.columnID != column.id || !isValid(measurement) {
            conflicts.append(conflict(.invalidMeasurement, entity: column.id, measurements: [measurement.id]))
        }
        let byKind = Dictionary(grouping: metadata.measurements.filter { $0.columnID == column.id }, by: \ColumnMeasurement.kind)
        func measurement(_ kind: ColumnMeasurementKind, unit: StructuralMeasurementUnit) -> ColumnMeasurement? {
            let values = authoritativeMeasurements(byKind[kind] ?? [])
            conflicts += duplicateVerifiedConflicts(values, entityID: column.id)
            guard let value = values.first, value.value.unit == unit, value.value.value.isFinite else { return nil }
            return value
        }
        if let value = measurement(.width, unit: .meters), value.value.value > 0 {
            column.width = lengthMeasurement(value.value)
        }
        if let value = measurement(.depth, unit: .meters), value.value.value > 0 {
            column.depth = lengthMeasurement(value.value)
        }
        if let value = measurement(.height, unit: .meters), value.value.value > 0 {
            column.height = lengthMeasurement(value.value)
        }
        if let value = measurement(.rotation, unit: .radians) {
            column.orientation = value.value.value
        }
        if metadata.shape == .circular,
           let diameter = measurement(.diameter, unit: .meters), diameter.value.value > 0 {
            column.width = lengthMeasurement(diameter.value)
            column.depth = lengthMeasurement(diameter.value)
        }
    }

    private func applyBeamMeasurements(
        to beam: inout ParametricBeam,
        conflicts: inout [StructuralConflict]
    ) {
        guard let metadata = beam.architecturalMetadata else { return }
        for measurement in metadata.measurements where measurement.beamID != beam.id || !isValid(measurement) {
            conflicts.append(conflict(.invalidMeasurement, entity: beam.id, measurements: [measurement.id]))
        }
        for kind in [BeamMeasurementKind.width, .depth, .bottomElevation] {
            let values = authoritativeMeasurements(metadata.measurements.filter {
                $0.beamID == beam.id && $0.kind == kind
            })
            conflicts += duplicateVerifiedConflicts(values, entityID: beam.id)
            guard let measurement = values.first,
                  measurement.value.unit == .meters,
                  measurement.value.value.isFinite,
                  (kind == .bottomElevation ? measurement.value.value >= 0 : measurement.value.value > 0) else { continue }
            let value = lengthMeasurement(measurement.value)
            switch kind {
            case .width: beam.width = value
            case .depth: beam.depth = value
            case .bottomElevation: beam.bottomElevation = value
            default: break
            }
        }
    }

    private func resolveBeam(
        _ beam: ParametricBeam,
        in plan: ParametricFloorPlan
    ) -> (geometry: ResolvedBeamGeometry?, conflicts: [StructuralConflict]) {
        var conflicts: [StructuralConflict] = []
        guard let start = point(for: beam.start, metadataReference: beam.architecturalMetadata?.startReference, in: plan),
              let end = point(for: beam.end, metadataReference: beam.architecturalMetadata?.endReference, in: plan) else {
            return (nil, [])
        }
        let length = start.distance(to: end)
        guard length.isFinite, length > computationalTolerance else {
            return (nil, [conflict(.invalidBeamGeometry, entity: beam.id)])
        }
        let metadata = beam.architecturalMetadata
        let lengthMeasurements = authoritativeMeasurements(metadata?.measurements.filter {
            $0.beamID == beam.id && $0.kind == .length
        } ?? [])
        conflicts += duplicateVerifiedConflicts(lengthMeasurements, entityID: beam.id)
        if let measured = lengthMeasurements.first,
           measured.value.unit != .meters || !measured.value.value.isFinite || measured.value.value <= 0 {
            conflicts.append(conflict(.invalidMeasurement, entity: beam.id, measurements: [measured.id]))
        } else if let measured = lengthMeasurements.first,
                  measured.value.provenance.verificationStatus == .verified,
                  abs(measured.value.value - length) > computationalTolerance {
            conflicts.append(conflict(
                .verifiedMeasurementConflict,
                entity: beam.id,
                measurements: [measured.id],
                residual: abs(measured.value.value - length)
            ))
        }

        let bottom = authoritativeValue(.bottomElevation, beamID: beam.id, metadata: metadata) ?? beam.bottomElevation.value
        let depth = authoritativeValue(.depth, beamID: beam.id, metadata: metadata) ?? beam.depth.value
        let top = bottom + depth
        if !bottom.isFinite || !depth.isFinite || bottom < 0 || depth <= 0 {
            conflicts.append(conflict(.invalidVerticalChain, entity: beam.id))
        }
        let measuredTop = authoritativeMeasurement(.topElevation, beamID: beam.id, metadata: metadata)
        if let measuredTop {
            if measuredTop.value.unit != .meters || !measuredTop.value.value.isFinite {
                conflicts.append(conflict(.invalidMeasurement, entity: beam.id, measurements: [measuredTop.id]))
            } else if measuredTop.value.provenance.verificationStatus == .verified,
                      abs(measuredTop.value.value - top) > computationalTolerance {
                conflicts.append(conflict(
                    .invalidVerticalChain,
                    entity: beam.id,
                    measurements: [measuredTop.id],
                    residual: abs(measuredTop.value.value - top)
                ))
            }
        }
        guard conflicts.isEmpty else { return (nil, conflicts) }
        let derived = MeasurementProvenance(
            source: .derived, verificationStatus: .unverified, timestamp: nil, uncertainty: nil
        )
        let resolvedLength = lengthMeasurements.first.map { lengthMeasurement($0.value) }
            ?? LengthMeasurement(value: length, provenance: derived)
        let resolvedTop = measuredTop.map { lengthMeasurement($0.value) }
            ?? LengthMeasurement(value: top, provenance: derived)
        return (.init(
            beamID: beam.id, start: start, end: end,
            length: resolvedLength, topElevation: resolvedTop
        ), [])
    }

    private func point(
        for anchor: BeamAnchor,
        metadataReference: BeamEndpointReference?,
        in plan: ParametricFloorPlan
    ) -> PlanPoint2D? {
        switch anchor {
        case .point(let point): return point.isFinite ? point : nil
        case .vertex(let id): return plan.vertex(id: id)?.position
        case .unresolved:
            guard let metadataReference, metadataReference.reliability != .unresolved else { return nil }
            switch metadataReference.entity {
            case .vertex(let id): return plan.vertex(id: id)?.position
            case .column(let id): return plan.columns.first(where: { $0.id == id })?.position
            case .wall, .unresolved: return nil
            }
        }
    }

    private struct OffsetLine {
        let point: PlanPoint2D
        let direction: PlanPoint2D
    }

    private func offsetLine(
        _ reference: StructuralReference,
        distance: Double,
        in plan: ParametricFloorPlan
    ) -> OffsetLine? {
        guard case let .wall(wallID, face, side) = reference.entity,
              let wall = plan.wall(id: wallID),
              let start = plan.vertex(id: wall.startVertexID)?.position,
              let end = plan.vertex(id: wall.endVertexID)?.position else { return nil }
        let length = start.distance(to: end)
        guard length.isFinite, length > computationalTolerance else { return nil }
        let direction = PlanPoint2D(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let normal = PlanPoint2D(x: -direction.y, y: direction.x)
        let halfThickness = (wall.thickness?.value ?? 0) / 2
        let faceOffset: Double = switch face {
        case .centerline: 0
        case .positiveFace: halfThickness
        case .negativeFace: -halfThickness
        }
        let total = faceOffset + Double(side.rawValue) * distance
        return OffsetLine(
            point: .init(x: start.x + normal.x * total, y: start.y + normal.y * total),
            direction: direction
        )
    }

    private func intersection(_ first: OffsetLine, _ second: OffsetLine) -> PlanPoint2D? {
        let cross = first.direction.x * second.direction.y - first.direction.y * second.direction.x
        guard abs(cross) > computationalTolerance else { return nil }
        let delta = PlanPoint2D(x: second.point.x - first.point.x, y: second.point.y - first.point.y)
        let t = (delta.x * second.direction.y - delta.y * second.direction.x) / cross
        return .init(x: first.point.x + first.direction.x * t, y: first.point.y + first.direction.y * t)
    }

    private func signedDistance(_ point: PlanPoint2D, to line: OffsetLine) -> Double {
        let dx = point.x - line.point.x
        let dy = point.y - line.point.y
        return dx * (-line.direction.y) + dy * line.direction.x
    }

    private func parallelResidual(_ first: OffsetLine, _ second: OffsetLine) -> Double {
        abs(signedDistance(second.point, to: first))
    }

    private func authoritativeMeasurements<T>(_ measurements: [T]) -> [T] where T: StructuralMeasured {
        measurements.sorted { priority($0.structuralValue.provenance) > priority($1.structuralValue.provenance) }
    }

    private func priority(_ provenance: MeasurementProvenance) -> Int {
        switch provenance.verificationStatus {
        case .verified: return 400
        case .unverified:
            return provenance.source == .manualEntered ? 300 : provenance.source == .derived ? 100 : 200
        case .estimated: return 200
        }
    }

    private func duplicateVerifiedConflicts<T: StructuralMeasured>(
        _ measurements: [T],
        entityID: UUID
    ) -> [StructuralConflict] {
        let verified = measurements.filter { $0.structuralValue.provenance.verificationStatus == .verified }
        guard let first = verified.first else { return [] }
        let differing = verified.dropFirst().filter {
            $0.structuralValue.unit != first.structuralValue.unit
                || abs($0.structuralValue.value - first.structuralValue.value) > computationalTolerance
        }
        guard !differing.isEmpty else { return [] }
        return [conflict(
            .verifiedMeasurementConflict,
            entity: entityID,
            measurements: [first.structuralID] + differing.map(\.structuralID)
        )]
    }

    private func authoritativeMeasurement(
        _ kind: BeamMeasurementKind,
        beamID: UUID,
        metadata: BeamArchitecturalMetadata?
    ) -> BeamMeasurement? {
        authoritativeMeasurements(metadata?.measurements.filter {
            $0.beamID == beamID && $0.kind == kind
        } ?? []).first
    }

    private func authoritativeValue(
        _ kind: BeamMeasurementKind,
        beamID: UUID,
        metadata: BeamArchitecturalMetadata?
    ) -> Double? {
        guard let measurement = authoritativeMeasurement(kind, beamID: beamID, metadata: metadata),
              measurement.value.unit == .meters else { return nil }
        return measurement.value.value
    }

    private func lengthMeasurement(_ value: StructuralMeasurementValue) -> LengthMeasurement {
        .init(value: value.value, provenance: value.provenance)
    }

    private func isValid(_ measurement: ColumnMeasurement) -> Bool {
        guard measurement.value.value.isFinite else { return false }
        switch measurement.kind {
        case .rotation: return measurement.value.unit == .radians
        case .baseElevation, .offset:
            return measurement.value.unit == .meters && measurement.value.value >= 0
        case .width, .depth, .diameter, .height:
            return measurement.value.unit == .meters && measurement.value.value > 0
        }
    }

    private func isValid(_ measurement: BeamMeasurement) -> Bool {
        guard measurement.value.unit == .meters, measurement.value.value.isFinite else { return false }
        switch measurement.kind {
        case .bottomElevation, .topElevation: return measurement.value.value >= 0
        case .length, .width, .depth: return measurement.value.value > 0
        }
    }

    private func isUnresolved(_ anchor: BeamAnchor) -> Bool {
        if case .unresolved = anchor { return true }
        return false
    }

    private func conflict(
        _ code: StructuralConflictCode,
        entity: UUID,
        measurements: [UUID] = [],
        residual: Double? = nil
    ) -> StructuralConflict {
        .init(
            id: "\(code.rawValue)-\(entity.uuidString)-\(measurements.map(\.uuidString).sorted().joined())",
            code: code,
            entityIDs: [entity],
            measurementIDs: measurements,
            residual: residual
        )
    }
}

private protocol StructuralMeasured {
    var structuralID: UUID { get }
    var structuralValue: StructuralMeasurementValue { get }
}

extension ColumnMeasurement: StructuralMeasured {
    fileprivate var structuralID: UUID { id }
    fileprivate var structuralValue: StructuralMeasurementValue { value }
}

extension BeamMeasurement: StructuralMeasured {
    fileprivate var structuralID: UUID { id }
    fileprivate var structuralValue: StructuralMeasurementValue { value }
}
