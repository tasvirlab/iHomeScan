import Foundation

enum ParametricPlanRepositoryError: Error, Equatable {
    case invalidGeometry([GeometryValidationIssue])
}

/// Lazy compatibility layer: old scans gain a parametric artifact only when the editor is opened.
struct ParametricPlanRepository {
    let files: LocalFileStorageService
    let adapter: RoomPlanToParametricAdapter
    let validator: ParametricGeometryValidator

    init(
        files: LocalFileStorageService,
        adapter: RoomPlanToParametricAdapter = RoomPlanToParametricAdapter(),
        validator: ParametricGeometryValidator = ParametricGeometryValidator()
    ) {
        self.files = files
        self.adapter = adapter
        self.validator = validator
    }

    func loadOrCreate(scan: SavedScan, floorPlan: FloorPlan) throws -> ParametricFloorPlan {
        if files.parametricPlanExists(projectID: scan.projectID, scanID: scan.id) {
            let data = try files.readParametricPlan(projectID: scan.projectID, scanID: scan.id)
            let plan = try ParametricFloorPlan.decode(from: data)
            try requireValid(plan)
            return plan
        }

        let plan = try adapter.convert(
            floorPlan,
            scanID: scan.id,
            projectID: scan.projectID,
            roomID: scan.roomID,
            createdAt: scan.createdAt
        )
        try requireValid(plan)
        try files.saveParametricPlan(
            try plan.encoded(), projectID: scan.projectID, scanID: scan.id
        )
        return plan
    }

    func load(scan: SavedScan) throws -> ParametricFloorPlan {
        let data = try files.readParametricPlan(projectID: scan.projectID, scanID: scan.id)
        let plan = try ParametricFloorPlan.decode(from: data)
        try requireValid(plan)
        return plan
    }

    func loadPrecisionDocument(scan: SavedScan, floorPlan: FloorPlan) throws -> PrecisionPlanDocument {
        if files.precisionPlanExists(projectID: scan.projectID, scanID: scan.id) {
            let data = try files.readPrecisionPlan(projectID: scan.projectID, scanID: scan.id)
            let document = try PrecisionPlanDocument.decode(from: data)
            try requireValid(document.currentPlan)
            return document
        }
        let baseline = try loadOrCreate(scan: scan, floorPlan: floorPlan)
        return PrecisionPlanDocument(
            baselinePlan: baseline,
            currentPlan: baseline,
            constraints: [],
            revisions: []
        )
    }

    func savePrecisionDocument(_ document: PrecisionPlanDocument, scan: SavedScan) throws {
        try requireValid(document.currentPlan)
        try files.savePrecisionPlan(
            document.encoded(),
            projectID: scan.projectID,
            scanID: scan.id
        )
    }

    private func requireValid(_ plan: ParametricFloorPlan) throws {
        let result = validator.validate(plan)
        guard result.isValid else {
            throw ParametricPlanRepositoryError.invalidGeometry(result.errors)
        }
    }
}
