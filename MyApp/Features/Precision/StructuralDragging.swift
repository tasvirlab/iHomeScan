import Foundation

struct StructuralDragCandidate: Sendable {
    let plan: ParametricFloorPlan
    let snappedPoint: PlanPoint2D
}

enum StructuralDragResolver {
    static func candidate(
        event: StructuralDragEvent,
        in plan: ParametricFloorPlan,
        snapDistance: Double = 0.08,
        gridStep: Double = 0.05
    ) -> StructuralDragCandidate? {
        let destination = snapped(
            event.modelPoint,
            in: plan,
            snapDistance: snapDistance,
            gridStep: gridStep
        )
        var candidate = plan
        switch event.kind {
        case .column:
            guard let index = candidate.columns.firstIndex(where: { $0.id == event.id }) else { return nil }
            candidate.columns[index].position = destination
        case .beam:
            guard let index = candidate.beams.firstIndex(where: { $0.id == event.id }),
                  let start = point(candidate.beams[index].start, in: candidate),
                  let end = point(candidate.beams[index].end, in: candidate) else { return nil }
            let center = PlanPoint2D(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let delta = destination - center
            candidate.beams[index].start = .point(start + delta)
            candidate.beams[index].end = .point(end + delta)
            if var metadata = candidate.beams[index].architecturalMetadata {
                metadata.startReference = .init(entity: .unresolved, reliability: .unresolved)
                metadata.endReference = .init(entity: .unresolved, reliability: .unresolved)
                candidate.beams[index].architecturalMetadata = metadata
            }
        }
        candidate.revision = .init(
            number: plan.revision.number + 1,
            createdAt: .now,
            source: .manualEntered
        )
        guard ParametricGeometryValidator().validate(candidate).isValid else { return nil }
        return .init(plan: candidate, snappedPoint: destination)
    }

    private static func snapped(
        _ point: PlanPoint2D,
        in plan: ParametricFloorPlan,
        snapDistance: Double,
        gridStep: Double
    ) -> PlanPoint2D {
        var best = PlanPoint2D(
            x: (point.x / gridStep).rounded() * gridStep,
            y: (point.y / gridStep).rounded() * gridStep
        )
        var bestDistance = point.distance(to: best)

        for vertex in plan.vertices {
            let distance = point.distance(to: vertex.position)
            if distance < bestDistance, distance <= snapDistance {
                best = vertex.position
                bestDistance = distance
            }
        }
        for wall in plan.walls {
            guard let start = plan.vertex(id: wall.startVertexID)?.position,
                  let end = plan.vertex(id: wall.endVertexID)?.position else { continue }
            let projection = projected(point, onto: start, end: end)
            let distance = point.distance(to: projection)
            if distance < bestDistance, distance <= snapDistance {
                best = projection
                bestDistance = distance
            }
        }
        return bestDistance <= snapDistance ? best : point
    }

    private static func projected(_ point: PlanPoint2D, onto start: PlanPoint2D, end: PlanPoint2D) -> PlanPoint2D {
        let vector = end - start
        let lengthSquared = vector.x * vector.x + vector.y * vector.y
        guard lengthSquared > 0 else { return start }
        let offset = point - start
        let parameter = min(max((offset.x * vector.x + offset.y * vector.y) / lengthSquared, 0), 1)
        return .init(x: start.x + vector.x * parameter, y: start.y + vector.y * parameter)
    }

    private static func point(_ anchor: BeamAnchor, in plan: ParametricFloorPlan) -> PlanPoint2D? {
        switch anchor {
        case .point(let point): point
        case .vertex(let id): plan.vertex(id: id)?.position
        case .unresolved: nil
        }
    }
}

private extension PlanPoint2D {
    static func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
}
