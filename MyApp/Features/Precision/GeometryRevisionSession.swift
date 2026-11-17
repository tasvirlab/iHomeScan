import Foundation

struct GeometryRevisionSession: Sendable {
    private(set) var document: PrecisionPlanDocument
    private(set) var preview: GeometryRevisionTransaction?
    private(set) var conflicts: [ConstraintConflict] = []
    private(set) var redoStack: [GeometryRevisionRecord] = []
    let historyLimit: Int

    init(document: PrecisionPlanDocument, historyLimit: Int = 30) {
        self.document = document
        self.historyLimit = max(historyLimit, 1)
    }

    mutating func propose(
        _ command: SetWallLengthCommand,
        solver: GeometryConstraintSolver = GeometryConstraintSolver(),
        allowsReplacingVerifiedMeasurement: Bool = false,
        allowsRectangularPropagation: Bool = false,
        preservesUnrelatedGeometry: Bool = false
    ) -> ConstraintSolveResult {
        let result = solver.preview(
            command: command,
            plan: document.currentPlan,
            constraints: document.constraints,
            allowsReplacingVerifiedMeasurement: allowsReplacingVerifiedMeasurement,
            allowsRectangularPropagation: allowsRectangularPropagation,
            preservesUnrelatedGeometry: preservesUnrelatedGeometry
        )
        switch result {
        case .solved(let transaction, _):
            preview = transaction
            conflicts = []
        case .conflict(let conflicts):
            preview = nil
            self.conflicts = conflicts
        }
        return result
    }

    mutating func cancelPreview() {
        preview = nil
        conflicts = []
    }

    @discardableResult
    mutating func applyPreview() -> GeometryRevisionRecord? {
        guard let preview else { return nil }
        let record = GeometryRevisionRecord(
            id: preview.id,
            createdAt: Date(),
            command: preview.command,
            previousPlan: document.currentPlan,
            resultingPlan: preview.candidatePlan,
            previousConstraints: document.constraints,
            resultingConstraints: preview.constraints,
            validation: preview.validation
        )
        document.currentPlan = record.resultingPlan
        document.constraints = record.resultingConstraints
        document.revisions.append(record)
        if document.revisions.count > historyLimit {
            document.revisions.removeFirst(document.revisions.count - historyLimit)
        }
        self.preview = nil
        conflicts = []
        redoStack = []
        return record
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let record = document.revisions.popLast() else { return false }
        document.currentPlan = record.previousPlan
        document.constraints = record.previousConstraints
        redoStack.append(record)
        preview = nil
        conflicts = []
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let record = redoStack.popLast() else { return false }
        document.currentPlan = record.resultingPlan
        document.constraints = record.resultingConstraints
        document.revisions.append(record)
        preview = nil
        conflicts = []
        return true
    }

    var displayedPlan: ParametricFloorPlan {
        preview?.candidatePlan ?? document.currentPlan
    }

    var canUndo: Bool { !document.revisions.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
}
