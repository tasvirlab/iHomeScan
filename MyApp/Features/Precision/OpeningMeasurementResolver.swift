import Foundation

enum OpeningMeasurementConflictCode: String, Codable, Sendable {
    case missingHostWall
    case invalidReference
    case invalidMeasurement
    case contradictoryMeasurements
    case underdeterminedPlacement
    case outsideHostWall
    case overlappingOpenings
    case invalidVerticalChain
    case exceedsWallHeight
}

struct OpeningMeasurementConflict: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let code: OpeningMeasurementConflictCode
    let openingIDs: [UUID]
    let measurementIDs: [UUID]
    let residual: Double?
}

struct ResolvedOpeningPlacement: Codable, Hashable, Sendable {
    let openingID: UUID
    let hostWallID: UUID
    let startOffset: Double
    let width: Double
    let endOffset: Double
    let centerOffset: Double
    let lowerElevation: Double?
    let height: Double?
    let topElevation: Double?
}

struct ResolvedOpeningGap: Codable, Hashable, Sendable {
    let hostWallID: UUID
    let leadingOpeningID: UUID
    let trailingOpeningID: UUID
    let distance: Double
}

struct OpeningMeasurementResolution: Sendable {
    let candidatePlan: ParametricFloorPlan
    let placements: [ResolvedOpeningPlacement]
    let gaps: [ResolvedOpeningGap]
    let derivedMeasurements: [OpeningMeasurement]
    let conflicts: [OpeningMeasurementConflict]
    let unresolvedOpeningIDs: [UUID]

    var isValid: Bool { conflicts.isEmpty }
}

/// Resolves architectural opening measurements without moving wall or vertex geometry.
/// Verified values are never weakened; derived values are recreated from the current host wall.
struct OpeningMeasurementResolver: Sendable {
    let computationalTolerance: Double

    init(computationalTolerance: Double = 0.000_1) {
        self.computationalTolerance = computationalTolerance
    }

    func resolve(plan: ParametricFloorPlan) -> OpeningMeasurementResolution {
        var candidate = plan
        var placements: [ResolvedOpeningPlacement] = []
        var derived: [OpeningMeasurement] = []
        var conflicts: [OpeningMeasurementConflict] = []
        var unresolved: [UUID] = []
        var gaps: [ResolvedOpeningGap] = []

        for (index, opening) in plan.openings.enumerated() {
            guard let wall = plan.wall(id: opening.hostWallID),
                  let wallLength = wall.length(in: plan), wallLength.isFinite else {
                conflicts.append(conflict(.missingHostWall, openingIDs: [opening.id]))
                continue
            }
            let result = resolve(opening: opening, wall: wall, wallLength: wallLength, plan: plan)
            conflicts.append(contentsOf: result.conflicts)
            derived.append(contentsOf: result.derived)
            guard let placement = result.placement else {
                if result.conflicts.isEmpty { unresolved.append(opening.id) }
                continue
            }
            placements.append(placement)
            candidate.openings[index] = openingWithResolvedGeometry(opening, placement: placement)
        }

        for group in Dictionary(grouping: placements, by: \.hostWallID).values {
            let ordered = group.sorted { $0.startOffset < $1.startOffset }
            for pair in zip(ordered, ordered.dropFirst())
            {
                let distance = pair.1.startOffset - (pair.0.startOffset + pair.0.width)
                if distance < -computationalTolerance {
                    conflicts.append(conflict(
                        .overlappingOpenings,
                        openingIDs: [pair.0.openingID, pair.1.openingID],
                        residual: -distance
                    ))
                } else {
                    gaps.append(ResolvedOpeningGap(
                        hostWallID: pair.0.hostWallID,
                        leadingOpeningID: pair.0.openingID,
                        trailingOpeningID: pair.1.openingID,
                        distance: max(0, distance)
                    ))
                    let gapMeasurements = plan.openings.first(where: { $0.id == pair.0.openingID })?
                        .architecturalMetadata?.measurements.filter {
                            $0.kind == .gapToNextOpening && $0.relatedOpeningID == pair.1.openingID
                                && $0.value.provenance.source != .derived
                        } ?? []
                    if let measuredGap = preferred(.gapToNextOpening, in: gapMeasurements) {
                        if abs(measuredGap.value.value - distance) > computationalTolerance {
                            conflicts.append(conflict(
                                .contradictoryMeasurements,
                                openingIDs: [pair.0.openingID, pair.1.openingID],
                                measurementIDs: [measuredGap.id],
                                residual: measuredGap.value.value - distance
                            ))
                        }
                    } else {
                        var gap = derivedMeasurement(pair.0.openingID, .gapToNextOpening, max(0, distance))
                        gap.relatedOpeningID = pair.1.openingID
                        derived.append(gap)
                    }
                }
            }
        }

        return OpeningMeasurementResolution(
            candidatePlan: candidate,
            placements: placements,
            gaps: gaps,
            derivedMeasurements: derived,
            conflicts: conflicts,
            unresolvedOpeningIDs: unresolved
        )
    }

    /// Re-expresses host-relative measurements after an explicit wall direction reversal.
    /// Physical opening placement is preserved; start/end semantics and references are swapped.
    func reversingHostDirection(of opening: WallOpening, wallLength: Double) -> WallOpening {
        let measurements = opening.architecturalMetadata?.measurements.map { measurement in
            let kind: OpeningMeasurementKind
            switch measurement.kind {
            case .offsetFromStart: kind = .offsetFromEnd
            case .offsetFromEnd: kind = .offsetFromStart
            default: kind = measurement.kind
            }
            let reference = measurement.reference.map { reference in
                OpeningMeasurementReference(
                    endpoint: reference.endpoint == .wallStart ? .wallEnd : .wallStart,
                    vertexID: reference.vertexID,
                    reliability: reference.reliability
                )
            }
            return OpeningMeasurement(
                id: measurement.id,
                openingID: measurement.openingID,
                kind: kind,
                value: measurement.value,
                reference: reference,
                relatedOpeningID: measurement.relatedOpeningID,
                relatedConstraintIDs: measurement.relatedConstraintIDs
            )
        }
        let center: LengthMeasurement
        switch opening.horizontalAnchor {
        case .distanceFromStart(let old):
            center = LengthMeasurement(value: wallLength - old.value, provenance: old.provenance)
        }
        return WallOpening(
            id: opening.id, hostWallID: opening.hostWallID, kind: opening.kind,
            width: opening.width, height: opening.height, verticalOffset: opening.verticalOffset,
            horizontalAnchor: .distanceFromStart(center), source: opening.source,
            architecturalMetadata: opening.architecturalMetadata.map {
                OpeningArchitecturalMetadata(
                    measurements: measurements ?? [],
                    completeness: $0.completeness,
                    doorSwing: $0.doorSwing.map { swing in
                        let hinge: DoorHingeSide = switch swing.hingeSide {
                        case .start: .end
                        case .end: .start
                        case .unknown: .unknown
                        }
                        return DoorSwingMetadata(
                            hingeSide: hinge, direction: swing.direction, angle: swing.angle,
                            leafWidth: swing.leafWidth, configuration: swing.configuration
                        )
                    }
                )
            }
        )
    }

    private func resolve(
        opening: WallOpening,
        wall: ParametricWall,
        wallLength: Double,
        plan: ParametricFloorPlan
    ) -> (placement: ResolvedOpeningPlacement?, derived: [OpeningMeasurement], conflicts: [OpeningMeasurementConflict]) {
        let explicit = opening.architecturalMetadata?.measurements.filter {
            $0.openingID == opening.id && $0.value.provenance.source != .derived
        } ?? []
        var conflicts = validateMeasurements(explicit, opening: opening, wall: wall)
        if !conflicts.isEmpty { return (nil, [], conflicts) }

        let startMeasurement = preferred(.offsetFromStart, in: explicit)
        let endMeasurement = preferred(.offsetFromEnd, in: explicit)
        let widthMeasurement = preferred(.width, in: explicit)
        let legacyWidth = opening.width?.value
        let width = widthMeasurement?.value.value ?? legacyWidth

        var start = startMeasurement?.value.value
        var end = endMeasurement?.value.value
        var resolvedWidth = width

        if resolvedWidth == nil, let start, let end {
            resolvedWidth = wallLength - start - end
        }
        if start == nil, let end, let resolvedWidth {
            start = wallLength - end - resolvedWidth
        }
        if end == nil, let start, let resolvedWidth {
            end = wallLength - start - resolvedWidth
        }
        if start == nil, end == nil, let resolvedWidth,
           case .distanceFromStart(let center) = opening.horizontalAnchor {
            start = center.value - resolvedWidth / 2
            end = wallLength - (start ?? 0) - resolvedWidth
        }

        guard let start, let end, let resolvedWidth else {
            return (nil, [], conflicts)
        }
        guard [start, end, resolvedWidth].allSatisfy({ $0.isFinite && $0 >= 0 }), resolvedWidth > 0 else {
            conflicts.append(conflict(.invalidMeasurement, openingIDs: [opening.id], measurementIDs: explicit.map(\.id)))
            return (nil, [], conflicts)
        }

        let chainResidual = start + resolvedWidth + end - wallLength
        if abs(chainResidual) > computationalTolerance {
            conflicts.append(conflict(
                .contradictoryMeasurements,
                openingIDs: [opening.id],
                measurementIDs: [startMeasurement, widthMeasurement, endMeasurement].compactMap { $0?.id },
                residual: chainResidual
            ))
            return (nil, [], conflicts)
        }
        guard start + resolvedWidth <= wallLength + computationalTolerance else {
            conflicts.append(conflict(.outsideHostWall, openingIDs: [opening.id], residual: start + resolvedWidth - wallLength))
            return (nil, [], conflicts)
        }

        let vertical = resolveVertical(opening: opening, explicit: explicit, wall: wall)
        conflicts.append(contentsOf: vertical.conflicts)
        if !conflicts.isEmpty { return (nil, [], conflicts) }

        var derived = vertical.derived
        if startMeasurement == nil { derived.append(derivedMeasurement(opening.id, .offsetFromStart, start, reference: reference(.wallStart, wall: wall))) }
        if widthMeasurement == nil { derived.append(derivedMeasurement(opening.id, .width, resolvedWidth)) }
        if endMeasurement == nil { derived.append(derivedMeasurement(opening.id, .offsetFromEnd, end, reference: reference(.wallEnd, wall: wall))) }

        return (ResolvedOpeningPlacement(
            openingID: opening.id,
            hostWallID: opening.hostWallID,
            startOffset: start,
            width: resolvedWidth,
            endOffset: end,
            centerOffset: start + resolvedWidth / 2,
            lowerElevation: vertical.lower,
            height: vertical.height,
            topElevation: vertical.top
        ), derived, conflicts)
    }

    private func resolveVertical(
        opening: WallOpening,
        explicit: [OpeningMeasurement],
        wall: ParametricWall
    ) -> (lower: Double?, height: Double?, top: Double?, derived: [OpeningMeasurement], conflicts: [OpeningMeasurementConflict]) {
        let lowerKind: OpeningMeasurementKind = opening.kind == .window ? .sillElevation : .thresholdElevation
        let lowerMeasurement = preferred(lowerKind, in: explicit)
        let heightMeasurement = preferred(.height, in: explicit)
        let topMeasurement = preferred(.topElevation, in: explicit)
        var lower = lowerMeasurement?.value.value ?? opening.verticalOffset?.value
        var height = heightMeasurement?.value.value ?? opening.height?.value
        var top = topMeasurement?.value.value

        if top == nil, let lower, let height { top = lower + height }
        if height == nil, let lower, let top { height = top - lower }
        if lower == nil, let height, let top { lower = top - height }
        let values = [lower, height, top].compactMap { $0 }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return (nil, nil, nil, [], [conflict(.invalidVerticalChain, openingIDs: [opening.id])])
        }
        if let lower, let height, let top {
            let residual = lower + height - top
            if abs(residual) > computationalTolerance {
                return (nil, nil, nil, [], [conflict(
                    .invalidVerticalChain,
                    openingIDs: [opening.id],
                    measurementIDs: [lowerMeasurement, heightMeasurement, topMeasurement].compactMap { $0?.id },
                    residual: residual
                )])
            }
            if let wallHeightMeasurement = wall.height,
               wallHeightMeasurement.provenance.verificationStatus == .verified,
               let wallHeight = Optional(wallHeightMeasurement.value),
               top > wallHeight + computationalTolerance {
                return (nil, nil, nil, [], [conflict(.exceedsWallHeight, openingIDs: [opening.id], residual: top - wallHeight)])
            }
        }

        var derived: [OpeningMeasurement] = []
        if let lower, lowerMeasurement == nil { derived.append(derivedMeasurement(opening.id, lowerKind, lower)) }
        if let height, heightMeasurement == nil { derived.append(derivedMeasurement(opening.id, .height, height)) }
        if let top, topMeasurement == nil { derived.append(derivedMeasurement(opening.id, .topElevation, top)) }
        return (lower, height, top, derived, [])
    }

    private func validateMeasurements(
        _ measurements: [OpeningMeasurement],
        opening: WallOpening,
        wall: ParametricWall
    ) -> [OpeningMeasurementConflict] {
        var conflicts: [OpeningMeasurementConflict] = []
        for measurement in measurements {
            if !measurement.value.value.isFinite || measurement.value.value < 0 {
                conflicts.append(conflict(.invalidMeasurement, openingIDs: [opening.id], measurementIDs: [measurement.id]))
            }
            if (measurement.kind == .width || measurement.kind == .height),
               measurement.value.value <= 0 {
                conflicts.append(conflict(.invalidMeasurement, openingIDs: [opening.id], measurementIDs: [measurement.id]))
            }
            if let reference = measurement.reference {
                let expected = reference.endpoint == .wallStart ? wall.startVertexID : wall.endVertexID
                if reference.reliability == .verified, reference.vertexID != expected {
                    conflicts.append(conflict(.invalidReference, openingIDs: [opening.id], measurementIDs: [measurement.id]))
                }
            }
        }
        for group in Dictionary(grouping: measurements, by: \.kind).values {
            let protected = group.filter { $0.value.provenance.verificationStatus == .verified }
            guard let first = protected.first else { continue }
            for other in protected.dropFirst()
            where abs(first.value.value - other.value.value) > computationalTolerance {
                conflicts.append(conflict(
                    .contradictoryMeasurements,
                    openingIDs: [opening.id],
                    measurementIDs: [first.id, other.id],
                    residual: first.value.value - other.value.value
                ))
            }
        }
        return conflicts
    }

    private func preferred(_ kind: OpeningMeasurementKind, in measurements: [OpeningMeasurement]) -> OpeningMeasurement? {
        measurements.filter {
            $0.kind == kind && $0.reference?.reliability != .unresolved
        }.max { lhs, rhs in
            let leftRank = rank(lhs.value.provenance)
            let rightRank = rank(rhs.value.provenance)
            if leftRank != rightRank { return leftRank < rightRank }
            let leftDate = lhs.value.provenance.timestamp ?? .distantPast
            let rightDate = rhs.value.provenance.timestamp ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func rank(_ provenance: MeasurementProvenance) -> Int {
        switch (provenance.verificationStatus, provenance.source) {
        case (.verified, _): 4
        case (_, .manualEntered): 3
        case (_, .lidarEstimated): 2
        case (_, .derived): 1
        default: 0
        }
    }

    private func openingWithResolvedGeometry(
        _ opening: WallOpening,
        placement: ResolvedOpeningPlacement
    ) -> WallOpening {
        let derivedProvenance = MeasurementProvenance(
            source: .derived, verificationStatus: .unverified, timestamp: nil, uncertainty: nil
        )
        return WallOpening(
            id: opening.id,
            hostWallID: opening.hostWallID,
            kind: opening.kind,
            width: LengthMeasurement(value: placement.width, provenance: preferred(.width, in: opening.architecturalMetadata?.measurements ?? [])?.value.provenance ?? opening.width?.provenance ?? derivedProvenance),
            height: placement.height.map { LengthMeasurement(value: $0, provenance: preferred(.height, in: opening.architecturalMetadata?.measurements ?? [])?.value.provenance ?? opening.height?.provenance ?? derivedProvenance) },
            verticalOffset: placement.lowerElevation.map { LengthMeasurement(value: $0, provenance: opening.verticalOffset?.provenance ?? derivedProvenance) },
            horizontalAnchor: .distanceFromStart(LengthMeasurement(value: placement.centerOffset, provenance: derivedProvenance)),
            source: opening.source,
            architecturalMetadata: opening.architecturalMetadata
        )
    }

    private func derivedMeasurement(
        _ openingID: UUID,
        _ kind: OpeningMeasurementKind,
        _ value: Double,
        reference: OpeningMeasurementReference? = nil
    ) -> OpeningMeasurement {
        OpeningMeasurement(
            id: StableGeometryID.make(namespace: openingID, components: ["derived", kind.rawValue]),
            openingID: openingID,
            kind: kind,
            value: LengthMeasurement(value: value, provenance: MeasurementProvenance(
                source: .derived, verificationStatus: .unverified, timestamp: nil, uncertainty: nil
            )),
            reference: reference,
            relatedConstraintIDs: []
        )
    }

    private func reference(_ endpoint: OpeningReferenceEndpoint, wall: ParametricWall) -> OpeningMeasurementReference {
        OpeningMeasurementReference(
            endpoint: endpoint,
            vertexID: endpoint == .wallStart ? wall.startVertexID : wall.endVertexID,
            reliability: .estimated
        )
    }

    private func conflict(
        _ code: OpeningMeasurementConflictCode,
        openingIDs: [UUID],
        measurementIDs: [UUID] = [],
        residual: Double? = nil
    ) -> OpeningMeasurementConflict {
        OpeningMeasurementConflict(
            id: ([code.rawValue] + openingIDs.map(\.uuidString) + measurementIDs.map(\.uuidString)).joined(separator: ":"),
            code: code,
            openingIDs: openingIDs,
            measurementIDs: measurementIDs,
            residual: residual
        )
    }
}
