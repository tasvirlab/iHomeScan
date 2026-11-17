import Foundation

struct GeometrySolverConfiguration: Sendable {
    var distanceTolerance = 0.000_1
    var angularTolerance = 0.000_1
    var minimumLength = 0.001
    var maximumIterations = 120
}

/// Deterministic projection solver for the explicitly supported P1.2 constraint set.
/// It is intentionally not a general nonlinear CAD solver.
struct GeometryConstraintSolver: Sendable {
    let configuration: GeometrySolverConfiguration
    let validator: ParametricGeometryValidator

    init(
        configuration: GeometrySolverConfiguration = GeometrySolverConfiguration(),
        validator: ParametricGeometryValidator = ParametricGeometryValidator()
    ) {
        self.configuration = configuration
        self.validator = validator
    }

    func preview(
        command: SetWallLengthCommand,
        plan: ParametricFloorPlan,
        constraints: [GeometryConstraint],
        allowsReplacingVerifiedMeasurement: Bool = false,
        allowsRectangularPropagation: Bool = false
    ) -> ConstraintSolveResult {
        guard command.targetLength.isFinite, command.targetLength >= configuration.minimumLength else {
            return .conflict([conflict(.invalidTarget, geometry: [command.wallID])])
        }
        guard let targetWall = plan.wall(id: command.wallID),
              plan.vertex(id: targetWall.startVertexID) != nil,
              plan.vertex(id: targetWall.endVertexID) != nil else {
            return .conflict([conflict(.missingGeometry, geometry: [command.wallID])])
        }

        let enabled = constraints.filter(\.isEnabled)
        let modelConflicts = GeometryConstraintValidator().validate(enabled, in: plan)
        if !modelConflicts.isEmpty { return .conflict(modelConflicts) }
        let fixed = fixedPositions(from: enabled)
        let anchorID = command.anchor == .keepStart ? targetWall.startVertexID : targetWall.endVertexID
        let movingID = command.anchor == .keepStart ? targetWall.endVertexID : targetWall.startVertexID
        if let locked = fixed[movingID], fixed[anchorID] != nil {
            let residual = locked.distance(to: fixed[anchorID]!) - command.targetLength
            if abs(residual) > configuration.distanceTolerance {
                return .conflict([conflict(.fixedVertex, constraints: fixedConstraintIDs(enabled, vertexID: movingID), geometry: [movingID], residual: residual)])
            }
        }

        let protectedLengths = enabled.filter { constraint in
            guard constraint.strength == .hard,
                  constraint.provenance.verificationStatus == .verified,
                  case .wallLength(let wallID, let meters) = constraint.kind,
                  wallID == command.wallID else { return false }
            return abs(meters - command.targetLength) > configuration.distanceTolerance
        }
        if !protectedLengths.isEmpty && !allowsReplacingVerifiedMeasurement {
            return .conflict([conflict(
                .verifiedMeasurement,
                constraints: protectedLengths.map(\.id),
                geometry: [command.wallID]
            )])
        }

        var candidate = plan
        guard setInitialTarget(command, wall: targetWall, fixed: fixed, plan: &candidate) else {
            return .conflict([conflict(.degenerateGeometry, geometry: [command.wallID])])
        }

        let commandConstraint = GeometryConstraint(
            id: command.id,
            kind: .wallLength(wallID: command.wallID, meters: command.targetLength),
            strength: .hard,
            priority: command.provenance.verificationStatus == .verified ? .protected : .high,
            provenance: command.provenance,
            createdAt: command.createdAt,
            isEnabled: true
        )
        let propagatedWallIDs = allowsRectangularPropagation
            ? rectangularPropagationWallIDs(targetWallID: command.wallID, in: plan)
            : []
        let active = (enabled.filter { constraint in
            if case .wallLength(let wallID, _) = constraint.kind {
                if wallID == command.wallID { return false }
                if propagatedWallIDs.contains(wallID),
                   constraint.provenance.verificationStatus != .verified {
                    return false
                }
            }
            return true
        } + [commandConstraint]).sorted { lhs, rhs in
            if lhs.priority.rawValue == rhs.priority.rawValue { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.priority.rawValue > rhs.priority.rawValue
        }

        for _ in 0..<configuration.maximumIterations {
            var maximumCorrection = 0.0
            for constraint in active where constraint.strength == .hard {
                maximumCorrection = max(maximumCorrection, project(constraint, fixed: fixed, plan: &candidate))
            }
            if maximumCorrection <= configuration.distanceTolerance { break }
        }

        if allowsRectangularPropagation {
            propagateRectangleIfApplicable(targetWallID: command.wallID, original: plan, candidate: &candidate)
        }

        let residualConflicts = hardConstraintConflicts(active, plan: candidate)
        if !residualConflicts.isEmpty { return .conflict(residualConflicts) }
        let openingConflicts = validateOpenings(in: candidate, constraints: active)
        if !openingConflicts.isEmpty { return .conflict(openingConflicts) }

        candidate.floorBoundary = closedBoundary(in: candidate)
        candidate.revision = ParametricRevision(
            number: plan.revision.number + 1,
            createdAt: command.createdAt,
            source: command.provenance.source
        )
        let validation = validator.validate(candidate)
        guard validation.isValid else {
            return .conflict([conflict(.invalidResult, geometry: validation.errors.compactMap(\.entityID))])
        }
        let transaction = GeometryRevisionTransaction(
            id: command.id,
            command: .setWallLength(command),
            originalPlan: plan,
            candidatePlan: candidate,
            constraints: active,
            validation: validation
        )
        return .solved(transaction, warnings: [])
    }

    private func propagateRectangleIfApplicable(
        targetWallID: UUID,
        original: ParametricFloorPlan,
        candidate: inout ParametricFloorPlan
    ) {
        guard original.walls.count == 4, original.vertices.count == 4,
              let target = original.wall(id: targetWallID),
              let cycle = rectangleCycle(startingWith: target, in: original) else { return }

        let originalPoints = cycle.compactMap { original.vertex(id: $0)?.position }
        guard originalPoints.count == 4, isNearRectangle(originalPoints) else { return }

        let candidatePoints = cycle.compactMap { candidate.vertex(id: $0)?.position }
        guard candidatePoints.count == 4 else { return }
        let a = candidatePoints[0]
        let b = candidatePoints[1]
        let width = a.distance(to: b)
        guard width >= configuration.minimumLength else { return }

        let ux = (b.x - a.x) / width
        let uy = (b.y - a.y) / width
        let leftHeight = originalPoints[0].distance(to: originalPoints[3])
        let rightHeight = originalPoints[1].distance(to: originalPoints[2])
        let height = (leftHeight + rightHeight) / 2
        guard height >= configuration.minimumLength else { return }

        let cross = ux * (originalPoints[2].y - originalPoints[1].y)
            - uy * (originalPoints[2].x - originalPoints[1].x)
        let sign = cross >= 0 ? 1.0 : -1.0
        let nx = -uy * sign
        let ny = ux * sign
        setPosition(.init(x: b.x + nx * height, y: b.y + ny * height), for: cycle[2], in: &candidate)
        setPosition(.init(x: a.x + nx * height, y: a.y + ny * height), for: cycle[3], in: &candidate)
    }

    /// Length constraints on the opposite side of a near rectangle are derived when the
    /// edited side is propagated. Stale manual/LiDAR values must not block that revision;
    /// independently verified measurements remain protected in `active`.
    private func rectangularPropagationWallIDs(
        targetWallID: UUID,
        in plan: ParametricFloorPlan
    ) -> Set<UUID> {
        guard plan.walls.count == 4, plan.vertices.count == 4,
              let target = plan.wall(id: targetWallID),
              let cycle = rectangleCycle(startingWith: target, in: plan),
              isNearRectangle(cycle.compactMap { plan.vertex(id: $0)?.position }) else {
            return []
        }
        let opposite = plan.walls.first { wall in
            Set([wall.startVertexID, wall.endVertexID]) == Set([cycle[2], cycle[3]])
        }
        var wallIDs = Set([targetWallID])
        if let opposite { wallIDs.insert(opposite.id) }
        return wallIDs
    }

    private func rectangleCycle(startingWith target: ParametricWall, in plan: ParametricFloorPlan) -> [UUID]? {
        var result = [target.startVertexID, target.endVertexID]
        var previousWallID = target.id
        var currentVertexID = target.endVertexID
        while result.count < 4 {
            let next = plan.walls.first { wall in
                wall.id != previousWallID
                    && (wall.startVertexID == currentVertexID || wall.endVertexID == currentVertexID)
            }
            guard let next else { return nil }
            let nextVertexID = next.startVertexID == currentVertexID ? next.endVertexID : next.startVertexID
            guard !result.contains(nextVertexID) else { return nil }
            result.append(nextVertexID)
            previousWallID = next.id
            currentVertexID = nextVertexID
        }
        guard plan.walls.contains(where: { wall in
            (wall.startVertexID == result[3] && wall.endVertexID == result[0])
                || (wall.endVertexID == result[3] && wall.startVertexID == result[0])
        }) else { return nil }
        return result
    }

    private func isNearRectangle(_ points: [PlanPoint2D]) -> Bool {
        guard points.count == 4 else { return false }
        let lengths = points.indices.map { points[$0].distance(to: points[($0 + 1) % 4]) }
        guard lengths.allSatisfy({ $0 >= configuration.minimumLength }),
              abs(lengths[0] - lengths[2]) / max(lengths[0], lengths[2]) < 0.1,
              abs(lengths[1] - lengths[3]) / max(lengths[1], lengths[3]) < 0.1 else { return false }
        return points.indices.allSatisfy { index in
            let previous = points[(index + 3) % 4]
            let center = points[index]
            let next = points[(index + 1) % 4]
            let ax = previous.x - center.x
            let ay = previous.y - center.y
            let bx = next.x - center.x
            let by = next.y - center.y
            let cosine = (ax * bx + ay * by) / max(hypot(ax, ay) * hypot(bx, by), 0.000_001)
            return abs(cosine) < 0.26
        }
    }

    private func setInitialTarget(
        _ command: SetWallLengthCommand,
        wall: ParametricWall,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Bool {
        guard let start = plan.vertex(id: wall.startVertexID)?.position,
              let end = plan.vertex(id: wall.endVertexID)?.position else { return false }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= configuration.minimumLength else { return false }
        let unit = PlanPoint2D(x: dx / length, y: dy / length)
        switch command.anchor {
        case .keepStart:
            setPosition(.init(x: start.x + unit.x * command.targetLength, y: start.y + unit.y * command.targetLength), for: wall.endVertexID, in: &plan)
        case .keepEnd:
            setPosition(.init(x: end.x - unit.x * command.targetLength, y: end.y - unit.y * command.targetLength), for: wall.startVertexID, in: &plan)
        }
        for (id, position) in fixed { setPosition(position, for: id, in: &plan) }
        return true
    }

    private func project(
        _ constraint: GeometryConstraint,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Double {
        switch constraint.kind {
        case .fixedVertex(let id, let position):
            return move(id, to: position, fixed: [:], plan: &plan)
        case .wallLength(let wallID, let meters):
            return projectLength(wallID, meters: meters, fixed: fixed, plan: &plan)
        case .horizontal(let wallID):
            return projectAxis(wallID, horizontal: true, fixed: fixed, plan: &plan)
        case .vertical(let wallID):
            return projectAxis(wallID, horizontal: false, fixed: fixed, plan: &plan)
        case .coincident(let first, let second):
            return projectCoincident(first, second, fixed: fixed, plan: &plan)
        case .parallel(let first, let second):
            return projectAngle(first, second, perpendicular: false, fixed: fixed, plan: &plan)
        case .perpendicular(let first, let second):
            return projectAngle(first, second, perpendicular: true, fixed: fixed, plan: &plan)
        case .wallOpeningAnchor:
            return 0
        }
    }

    private func projectLength(
        _ wallID: UUID,
        meters: Double,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Double {
        guard meters.isFinite, meters >= configuration.minimumLength,
              let wall = plan.wall(id: wallID),
              let start = plan.vertex(id: wall.startVertexID)?.position,
              let end = plan.vertex(id: wall.endVertexID)?.position else { return .infinity }
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= configuration.minimumLength else { return .infinity }
        let error = length - meters
        let ux = dx / length, uy = dy / length
        if fixed[wall.startVertexID] != nil && fixed[wall.endVertexID] != nil { return abs(error) }
        if fixed[wall.startVertexID] != nil {
            return move(wall.endVertexID, to: .init(x: end.x - ux * error, y: end.y - uy * error), fixed: fixed, plan: &plan)
        }
        if fixed[wall.endVertexID] != nil {
            return move(wall.startVertexID, to: .init(x: start.x + ux * error, y: start.y + uy * error), fixed: fixed, plan: &plan)
        }
        let half = error / 2
        let a = move(wall.startVertexID, to: .init(x: start.x + ux * half, y: start.y + uy * half), fixed: fixed, plan: &plan)
        let b = move(wall.endVertexID, to: .init(x: end.x - ux * half, y: end.y - uy * half), fixed: fixed, plan: &plan)
        return max(a, b)
    }

    private func projectAxis(
        _ wallID: UUID,
        horizontal: Bool,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Double {
        guard let wall = plan.wall(id: wallID),
              let start = plan.vertex(id: wall.startVertexID)?.position,
              let end = plan.vertex(id: wall.endVertexID)?.position else { return .infinity }
        let valueA = horizontal ? start.y : start.x
        let valueB = horizontal ? end.y : end.x
        let target: Double
        if fixed[wall.startVertexID] != nil { target = valueA }
        else if fixed[wall.endVertexID] != nil { target = valueB }
        else { target = (valueA + valueB) / 2 }
        var newStart = start, newEnd = end
        if horizontal { newStart.y = target; newEnd.y = target } else { newStart.x = target; newEnd.x = target }
        return max(
            move(wall.startVertexID, to: newStart, fixed: fixed, plan: &plan),
            move(wall.endVertexID, to: newEnd, fixed: fixed, plan: &plan)
        )
    }

    private func projectCoincident(
        _ first: UUID,
        _ second: UUID,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Double {
        guard let a = plan.vertex(id: first)?.position, let b = plan.vertex(id: second)?.position else { return .infinity }
        let target = fixed[first] ?? fixed[second] ?? .init(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        return max(move(first, to: target, fixed: fixed, plan: &plan), move(second, to: target, fixed: fixed, plan: &plan))
    }

    private func projectAngle(
        _ firstID: UUID,
        _ secondID: UUID,
        perpendicular: Bool,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Double {
        guard let first = plan.wall(id: firstID), let second = plan.wall(id: secondID),
              let a = plan.vertex(id: first.startVertexID)?.position,
              let b = plan.vertex(id: first.endVertexID)?.position,
              let c = plan.vertex(id: second.startVertexID)?.position,
              let d = plan.vertex(id: second.endVertexID)?.position else { return .infinity }
        let base = atan2(b.y - a.y, b.x - a.x) + (perpendicular ? .pi / 2 : 0)
        let length = c.distance(to: d)
        guard length >= configuration.minimumLength else { return .infinity }
        let candidateForward = PlanPoint2D(x: c.x + cos(base) * length, y: c.y + sin(base) * length)
        let candidateReverse = PlanPoint2D(x: c.x - cos(base) * length, y: c.y - sin(base) * length)
        let target = candidateForward.distance(to: d) <= candidateReverse.distance(to: d) ? candidateForward : candidateReverse
        if fixed[second.endVertexID] == nil { return move(second.endVertexID, to: target, fixed: fixed, plan: &plan) }
        let reverse = PlanPoint2D(x: d.x - (target.x - c.x), y: d.y - (target.y - c.y))
        return move(second.startVertexID, to: reverse, fixed: fixed, plan: &plan)
    }

    private func move(
        _ id: UUID,
        to position: PlanPoint2D,
        fixed: [UUID: PlanPoint2D],
        plan: inout ParametricFloorPlan
    ) -> Double {
        guard let index = plan.vertices.firstIndex(where: { $0.id == id }) else { return .infinity }
        let current = plan.vertices[index].position
        let target = fixed[id] ?? position
        plan.vertices[index].position = target
        return current.distance(to: target)
    }

    private func setPosition(_ position: PlanPoint2D, for id: UUID, in plan: inout ParametricFloorPlan) {
        guard let index = plan.vertices.firstIndex(where: { $0.id == id }) else { return }
        plan.vertices[index].position = position
    }

    private func hardConstraintConflicts(
        _ constraints: [GeometryConstraint],
        plan: ParametricFloorPlan
    ) -> [ConstraintConflict] {
        constraints.compactMap { constraint in
            guard constraint.strength == .hard else { return nil }
            let residual = constraintResidual(constraint.kind, plan: plan)
            guard !residual.isFinite || residual > configuration.distanceTolerance else { return nil }
            return conflict(.unsatisfiedHardConstraint, constraints: [constraint.id], geometry: referencedGeometry(constraint.kind), residual: residual)
        }
    }

    private func constraintResidual(_ kind: GeometryConstraintKind, plan: ParametricFloorPlan) -> Double {
        switch kind {
        case .fixedVertex(let id, let position): return plan.vertex(id: id)?.position.distance(to: position) ?? .infinity
        case .wallLength(let id, let meters): return abs((plan.wall(id: id)?.length(in: plan) ?? .infinity) - meters)
        case .horizontal(let id): return axisResidual(id, horizontal: true, plan: plan)
        case .vertical(let id): return axisResidual(id, horizontal: false, plan: plan)
        case .coincident(let a, let b): return plan.vertex(id: a)?.position.distance(to: plan.vertex(id: b)?.position ?? .init(x: .infinity, y: .infinity)) ?? .infinity
        case .parallel(let a, let b): return angleResidual(a, b, target: 0, plan: plan)
        case .perpendicular(let a, let b): return angleResidual(a, b, target: .pi / 2, plan: plan)
        case .wallOpeningAnchor(let id, let meters):
            guard let opening = plan.openings.first(where: { $0.id == id }), case .distanceFromStart(let anchor) = opening.horizontalAnchor else { return .infinity }
            return abs(anchor.value - meters)
        }
    }

    private func axisResidual(_ wallID: UUID, horizontal: Bool, plan: ParametricFloorPlan) -> Double {
        guard let wall = plan.wall(id: wallID), let a = plan.vertex(id: wall.startVertexID)?.position, let b = plan.vertex(id: wall.endVertexID)?.position else { return .infinity }
        return abs(horizontal ? b.y - a.y : b.x - a.x)
    }

    private func angleResidual(_ first: UUID, _ second: UUID, target: Double, plan: ParametricFloorPlan) -> Double {
        guard let a = plan.wall(id: first)?.orientation(in: plan), let b = plan.wall(id: second)?.orientation(in: plan) else { return .infinity }
        let difference = abs(atan2(sin(b - a), cos(b - a)))
        let unsigned = min(difference, abs(.pi - difference))
        return abs(unsigned - target)
    }

    private func validateOpenings(in plan: ParametricFloorPlan, constraints: [GeometryConstraint]) -> [ConstraintConflict] {
        plan.openings.compactMap { opening in
            guard let wall = plan.wall(id: opening.hostWallID), let length = wall.length(in: plan),
                  case .distanceFromStart(let anchor) = opening.horizontalAnchor else {
                return conflict(.openingOutsideHost, geometry: [opening.id, opening.hostWallID])
            }
            let halfWidth = (opening.width?.value ?? 0) / 2
            guard anchor.value - halfWidth >= -configuration.distanceTolerance,
                  anchor.value + halfWidth <= length + configuration.distanceTolerance else {
                let related = constraints.filter {
                    if case .wallOpeningAnchor(let id, _) = $0.kind { return id == opening.id }
                    return false
                }.map(\.id)
                return conflict(.openingOutsideHost, constraints: related, geometry: [opening.id, wall.id])
            }
            return nil
        }
    }

    private func fixedPositions(from constraints: [GeometryConstraint]) -> [UUID: PlanPoint2D] {
        constraints.reduce(into: [:]) { result, constraint in
            if constraint.strength == .hard, case .fixedVertex(let id, let point) = constraint.kind { result[id] = point }
        }
    }

    private func fixedConstraintIDs(_ constraints: [GeometryConstraint], vertexID: UUID) -> [UUID] {
        constraints.compactMap { constraint in
            if case .fixedVertex(let id, _) = constraint.kind, id == vertexID { return constraint.id }
            return nil
        }
    }

    private func referencedGeometry(_ kind: GeometryConstraintKind) -> [UUID] {
        switch kind {
        case .fixedVertex(let id, _): [id]
        case .wallLength(let id, _), .horizontal(let id), .vertical(let id): [id]
        case .perpendicular(let a, let b), .parallel(let a, let b), .coincident(let a, let b): [a, b]
        case .wallOpeningAnchor(let id, _): [id]
        }
    }

    private func conflict(
        _ code: ConstraintConflictCode,
        constraints: [UUID] = [],
        geometry: [UUID] = [],
        residual: Double? = nil
    ) -> ConstraintConflict {
        ConstraintConflict(
            id: "\(code.rawValue)-\(constraints.map(\.uuidString).sorted().joined())-\(geometry.map(\.uuidString).sorted().joined())",
            code: code,
            constraintIDs: constraints,
            geometryIDs: geometry,
            residual: residual
        )
    }

    private func closedBoundary(in plan: ParametricFloorPlan) -> [[PlanPoint2D]]? {
        guard plan.walls.count >= 3 else { return nil }
        let adjacency = plan.walls.reduce(into: [UUID: [UUID]]()) { result, wall in
            result[wall.startVertexID, default: []].append(wall.endVertexID)
            result[wall.endVertexID, default: []].append(wall.startVertexID)
        }
        guard adjacency.values.allSatisfy({ $0.count == 2 }), let start = adjacency.keys.min(by: { $0.uuidString < $1.uuidString }) else { return nil }
        var ordered = [start], previous: UUID?, current = start
        repeat {
            guard let next = adjacency[current]?.first(where: { $0 != previous }) else { return nil }
            previous = current
            current = next
            if current != start { ordered.append(current) }
        } while current != start && ordered.count <= plan.vertices.count
        guard current == start, ordered.count == adjacency.count else { return nil }
        return [ordered.compactMap { plan.vertex(id: $0)?.position }]
    }
}
