import Foundation
import CoreGraphics
import SwiftData
import Testing
@testable import iHomeScan

@MainActor
@Suite("Saved scan visualization")
struct SavedScanViewerTests {
    private struct Fixture {
        let project: Project
        let floor: Floor
        let room: Room
        let scan: SavedScan
        let geometry: LocalAsset
        let model: LocalAsset
    }

    private func fixture(
        in environment: TestEnvironment,
        geometryData: Data? = nil,
        modelData: Data = Data("test-usdz".utf8),
        date: Date = .now
    ) throws -> Fixture {
        let geometryData = try geometryData ?? SampleProjectSeeder.plan.encoded()
        let project = try environment.projects.create(name: "Viewer")
        let floor = try #require(project.sortedFloors.first)
        let room = try environment.rooms.addRoom(to: floor, draft: RoomDraft(name: "Room 1"))
        let geometryFile = try environment.files.save(
            geometryData, projectID: project.id, type: .roomGeometry, preferredFileName: "geometry.json"
        )
        let modelFile = try environment.files.save(
            modelData, projectID: project.id, type: .usdzModel, preferredFileName: "room.usdz"
        )
        let sourceFile = try environment.files.save(
            Data("{}".utf8), projectID: project.id, type: .roomPlanSource, preferredFileName: "source.json"
        )
        let geometry = asset(geometryFile, type: .roomGeometry)
        let model = asset(modelFile, type: .usdzModel)
        let source = asset(sourceFile, type: .roomPlanSource)
        for item in [geometry, model, source] {
            environment.context.insert(item)
            item.project = project
            item.floor = floor
            item.room = room
        }
        let scan = SavedScan(
            id: UUID(), projectID: project.id, floorID: floor.id, roomID: room.id,
            createdAt: date, completeness: .complete, floorArea: 12,
            sourceAssetID: source.id, geometryAssetID: geometry.id, modelAssetID: model.id
        )
        environment.context.insert(scan)
        try environment.context.save()
        return Fixture(project: project, floor: floor, room: room, scan: scan, geometry: geometry, model: model)
    }

    private func asset(_ file: StoredFile, type: AssetType) -> LocalAsset {
        LocalAsset(type: type, relativeFilePath: file.relativePath, fileName: file.fileName,
                   fileSize: file.fileSize, checksum: file.checksum)
    }

    @Test("Loads saved geometry and real model URL")
    func loadsContent() throws {
        let environment = try TestEnvironment()
        let item = try fixture(in: environment)
        let content = try SavedScanContentLoader(context: environment.context, files: environment.files).load(item.scan)
        #expect(content.floorPlan.bounds == SampleProjectSeeder.plan.bounds)
        let modelURL = try #require(content.modelURL)
        #expect(modelURL.pathExtension == "usdz")
        #expect(FileManager.default.fileExists(atPath: modelURL.path()))
    }

    @Test("Missing geometry is reported without crashing")
    func missingGeometry() throws {
        let environment = try TestEnvironment()
        let item = try fixture(in: environment)
        try environment.files.deleteFile(atRelativePath: item.geometry.relativeFilePath)
        #expect(throws: SavedScanLoadingError.missingGeometry) {
            try SavedScanContentLoader(context: environment.context, files: environment.files).load(item.scan)
        }
    }

    @Test("Invalid geometry JSON is rejected")
    func invalidGeometry() throws {
        let environment = try TestEnvironment()
        let item = try fixture(in: environment, geometryData: Data("not-json".utf8))
        #expect(throws: SavedScanLoadingError.invalidGeometry) {
            try SavedScanContentLoader(context: environment.context, files: environment.files).load(item.scan)
        }
    }

    @Test("Missing USDZ is reported independently")
    func missingModel() throws {
        let environment = try TestEnvironment()
        let item = try fixture(in: environment)
        try environment.files.deleteFile(atRelativePath: item.model.relativeFilePath)
        let content = try SavedScanContentLoader(context: environment.context, files: environment.files).load(item.scan)
        #expect(content.floorPlan.bounds == SampleProjectSeeder.plan.bounds)
        #expect(content.modelURL == nil)
        #expect(content.modelError == .missingModel)
    }

    @Test("Empty USDZ is rejected as invalid")
    func invalidModel() throws {
        let environment = try TestEnvironment()
        let item = try fixture(in: environment, modelData: Data())
        let content = try SavedScanContentLoader(context: environment.context, files: environment.files).load(item.scan)
        #expect(content.modelURL == nil)
        #expect(content.modelError == .invalidModel)
    }

    @Test("Partial geometry remains partial and keeps detected walls")
    func partialVisualization() throws {
        let environment = try TestEnvironment()
        let base = SampleProjectSeeder.plan
        let metadata = RoomPlanGeometryMetadata(
            formatVersion: RoomPlanGeometryMetadata.currentFormatVersion,
            roomIdentifier: UUID(), roomPlanVersion: 1,
            coordinateSystem: "meters; x=worldX; y=-worldZ",
            completeness: .incomplete, floorArea: nil,
            surfaces: [], objects: [], rejectedElementIdentifiers: []
        )
        let partial = FloorPlan(
            bounds: base.bounds, rooms: [], outerWalls: [Array(base.outerWalls[0].prefix(2))],
            innerWalls: [], doors: [], windows: [], dimensions: [], roomPlanMetadata: metadata
        )
        let item = try fixture(in: environment, geometryData: try partial.encoded())
        let content = try SavedScanContentLoader(context: environment.context, files: environment.files).load(item.scan)
        #expect(content.floorPlan.roomPlanMetadata?.completeness == .incomplete)
        #expect(content.floorPlan.roomPlanMetadata?.floorArea == nil)
        #expect(content.floorPlan.outerWalls.first?.count == 2)
    }

    @Test("Scan versions are returned newest first")
    func versionSelectionOrder() throws {
        let environment = try TestEnvironment()
        let older = try fixture(in: environment, date: Date(timeIntervalSince1970: 100))
        let newer = SavedScan(
            id: UUID(), projectID: older.project.id, floorID: older.floor.id, roomID: older.room.id,
            createdAt: Date(timeIntervalSince1970: 200), completeness: .incomplete, floorArea: nil,
            sourceAssetID: older.scan.sourceAssetID, geometryAssetID: older.scan.geometryAssetID,
            modelAssetID: older.scan.modelAssetID
        )
        environment.context.insert(newer)
        try environment.context.save()
        let scans = try ScanPersistenceService(context: environment.context, files: environment.files)
            .scans(roomID: older.room.id)
        #expect(scans.map(\.id) == [newer.id, older.scan.id])
        #expect(scans.last?.completeness == .complete)
    }

    @Test("Successful save navigation opens the exact scan and keeps project as back destination")
    func navigationAfterSave() {
        let association = SavedScanAssociation(
            scanID: UUID(), projectID: UUID(), projectName: "Project",
            floorID: UUID(), roomID: UUID(), roomName: "Room"
        )
        let model = AppModel()
        model.openSavedScan(association)
        #expect(model.selectedTab == .projects)
        #expect(model.path == [
            .project(association.projectID),
            .savedScan(projectID: association.projectID, roomID: association.roomID, scanID: association.scanID),
        ])
        #expect(model.scanner == nil)
    }

    @Test("2D viewer transform supports fit, pan and zoom for irregular bounds")
    func viewerTransform() {
        let plan = SampleProjectSeeder.plan
        let fitted = FloorPlanCanvas.transform(
            for: plan, in: CGSize(width: 390, height: 700), zoom: 1, offset: .zero
        )
        let zoomed = FloorPlanCanvas.transform(
            for: plan, in: CGSize(width: 390, height: 700), zoom: 2,
            offset: CGSize(width: 20, height: -15)
        )
        let start = plan.bounds.origin
        let end = CGPoint(x: plan.bounds.maxX, y: plan.bounds.maxY)
        let fittedDistance = hypot(end.applying(fitted).x - start.applying(fitted).x,
                                   end.applying(fitted).y - start.applying(fitted).y)
        let zoomedDistance = hypot(end.applying(zoomed).x - start.applying(zoomed).x,
                                   end.applying(zoomed).y - start.applying(zoomed).y)
        #expect(fittedDistance.isFinite)
        #expect(abs(zoomedDistance / fittedDistance - 2) < 0.001)
    }
}
