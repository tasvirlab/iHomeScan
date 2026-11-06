import Foundation

struct GeometryConstraintValidator: Sendable {
    func validate(
        _ constraints: [GeometryConstraint],
        in plan: ParametricFloorPlan
    ) -> [ConstraintConflict] {
        var conflicts: [ConstraintConflict] = []
        let duplicateIDs = Dictionary(grouping: constraints, by: \.id).filter { $0.value.count > 1 }.keys
        for id in duplicateIDs {
            conflicts.append(issue(.unsupportedConfiguration, constraintIDs: [id]))
        }
        for constraint in constraints where constraint.isEnabled {
            let missing = references(constraint.kind).filter { !exists($0, kind: constraint.kind, plan: plan) }
            if !missing.isEmpty {
                conflicts.append(issue(.missingGeometry, constraintIDs: [constraint.id], geometryIDs: missing))
            }
            switch constraint.kind {
            case .wallLength(_, let meters), .wallOpeningAnchor(_, let meters):
                if !meters.isFinite || meters <= 0 {
                    conflicts.append(issue(.invalidTarget, constraintIDs: [constraint.id]))
                }
            case .fixedVertex(_, let position) where !position.isFinite:
                conflicts.append(issue(.invalidTarget, constraintIDs: [constraint.id]))
            default:
                break
            }
        }
        return conflicts
    }

    private func references(_ kind: GeometryConstraintKind) -> [UUID] {
        switch kind {
        case .fixedVertex(let id, _): [id]
        case .wallLength(let id, _), .horizontal(let id), .vertical(let id): [id]
        case .perpendicular(let first, let second), .parallel(let first, let second): [first, second]
        case .coincident(let first, let second): [first, second]
        case .wallOpeningAnchor(let id, _): [id]
        }
    }

    private func exists(_ id: UUID, kind: GeometryConstraintKind, plan: ParametricFloorPlan) -> Bool {
        switch kind {
        case .fixedVertex, .coincident:
            plan.vertex(id: id) != nil
        case .wallOpeningAnchor:
            plan.openings.contains { $0.id == id }
        default:
            plan.wall(id: id) != nil
        }
    }

    private func issue(
        _ code: ConstraintConflictCode,
        constraintIDs: [UUID],
        geometryIDs: [UUID] = []
    ) -> ConstraintConflict {
        .init(
            id: "constraint-validation-\(code.rawValue)-\(constraintIDs.map(\.uuidString).joined())",
            code: code,
            constraintIDs: constraintIDs,
            geometryIDs: geometryIDs,
            residual: nil
        )
    }
}
