import Foundation
import SwiftData
import Testing
@testable import iHomeScan

private struct FakeScanArtifactProducer: ScanArtifactProducing {
    var shouldFail = false
    var modelData = Data("USDZ-test-model".utf8)

    func prepareArtifacts(for output: RoomScanOutput) throws -> PreparedScanArtifacts {
        if shouldFail { throw FileStorageError.writeFailed("injected") }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ScanPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let modelURL = directory.appending(path: "room.usdz")
        try modelData.write(to: modelURL)
        return PreparedScanArtifacts(
            sourceData: Data("{\"capturedRoom\":true}".utf8),
            geometryData: try output.floorPlan.encoded(),
            modelURL: modelURL,
            temporaryDirectory: directory
        )
    }
}

@MainActor
@Suite("Persistent RoomPlan scans")
struct ScanPersistenceTests {
    private func output(scanID: UUID = UUID(), incomplete: Bool = false) throws -> RoomScanOutput {
        let floorID = UUID()
        let surfaces: [RoomGeometrySource.Surface] = [
            surface(kind: .wall, width: 4),
            surface(kind: .wall, width: 3, yaw: 90),
            surface(kind: .wall, width: 4, translationZ: 3),
        ] + (incomplete ? [] : [
            surface(
                id: floorID,
                kind: .floor,
                width: 4,
                polygon: [
                    .init(x: 0, y: 0, z: 0),
                    .init(x: 4, y: 0, z: 0),
                    .init(x: 4, y: 0, z: 3),
                    .init(x: 0, y: 0, z: 3),
                ]
            ),
        ])
        let plan = try RoomGeometryProcessor().process(
            RoomGeometrySource(
                roomIdentifier: UUID(),
                roomPlanVersion: 1,
                surfaces: surfaces,
                objects: []
            )
        )
        return RoomScanOutput(
            scanID: scanID,
            summary: RoomScanSummary(
                walls: 3,
                doors: 0,
                windows: 0,
                openings: 0,
                objects: 0,
                floors: incomplete ? 0 : 1
            ),
            floorPlan: plan,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            capturedRoom: nil
        )
    }

    private func surface(
        id: UUID = UUID(),
        kind: RoomGeometrySource.SurfaceKind,
        width: Double,
        translationZ: Double = 0,
        yaw: Double = 0,
        polygon: [RoomGeometrySource.Vector3] = []
    ) -> RoomGeometrySource.Surface {
        let radians = yaw * .pi / 180
        let c = cos(radians)
        let s = sin(radians)
        return RoomGeometrySource.Surface(
            identifier: id,
            parentIdentifier: nil,
            kind: kind,
            dimensions: .init(x: width, y: 2.5, z: 0),
            transform: .init(values: [
                c, 0, -s, 0,
                0, 1, 0, 0,
                s, 0, c, 0,
                0, 0, translationZ, 1,
            ]),
            polygonCorners: polygon,
            confidence: .high,
            story: 0
        )
    }

    private func save(
        _ output: RoomScanOutput,
        environment: TestEnvironment,
        existingRoom: Room? = nil,
        saveContext: (() throws -> Void)? = nil
    ) throws -> SavedScanAssociation {
        let project: Project
        let floor: Floor
        if let existingRoom {
            floor = try #require(existingRoom.floor)
            project = try #require(floor.project)
        } else {
            project = try environment.projects.create(name: "Real scan project")
            floor = try #require(project.sortedFloors.first)
        }
        return try ScanPersistenceService(
            context: environment.context,
            files: environment.files,
            artifactProducer: FakeScanArtifactProducer(),
            saveContext: saveContext
        ).save(
            output: output,
            project: project,
            floor: floor,
            existingRoom: existingRoom,
            roomName: existingRoom?.name ?? "Living room"
        )
    }

    @Test("Persists source JSON, geometry JSON, model and metadata")
    func savesAllArtifacts() throws {
        let environment = try TestEnvironment()
        let output = try output()
        let association = try save(output, environment: environment)

        let storedScan = try ScanPersistenceService(
            context: environment.context,
            files: environment.files
        ).savedScan(id: output.scanID)
        let scan = try #require(storedScan)
        #expect(scan.projectID == association.projectID)
        #expect(scan.floorID == association.floorID)
        #expect(scan.roomID == association.roomID)
        #expect(scan.completeness == .complete)
        #expect(scan.floorArea == 12)

        let assets = try environment.context.fetch(FetchDescriptor<LocalAsset>())
            .filter { [scan.sourceAssetID, scan.geometryAssetID, scan.modelAssetID].contains($0.id) }
        #expect(assets.count == 3)
        #expect(Set(assets.compactMap(\.type)) == [.roomPlanSource, .roomGeometry, .usdzModel])
        for asset in assets {
            #expect(environment.files.fileExists(atRelativePath: asset.relativeFilePath))
            #expect(try environment.files.read(
                relativePath: asset.relativeFilePath,
                expectedChecksum: asset.checksum
            ).isEmpty == false)
        }
    }

    @Test("Partial scans are saved honestly without fabricated area")
    func partialScan() throws {
        let environment = try TestEnvironment()
        let output = try output(incomplete: true)
        _ = try save(output, environment: environment)

        let storedScan = try ScanPersistenceService(
            context: environment.context,
            files: environment.files
        ).savedScan(id: output.scanID)
        let scan = try #require(storedScan)
        #expect(scan.completeness == .incomplete)
        #expect(scan.floorArea == nil)
        let room = try #require(
            try environment.context.fetch(FetchDescriptor<Room>())
                .first { $0.id == scan.roomID }
        )
        #expect(room.area == nil)
        #expect(room.width == nil)
        #expect(room.length == nil)
    }

    @Test("Saved scans and files survive reopening the store")
    func reopen() throws {
        let environment = try TestEnvironment(onDisk: true)
        let output = try output()
        let association = try save(output, environment: environment)
        try environment.reopen()

        let storedScan = try ScanPersistenceService(
            context: environment.context,
            files: environment.files
        ).savedScan(id: output.scanID)
        let scan = try #require(storedScan)
        #expect(scan.roomID == association.roomID)
        let assets = try environment.context.fetch(FetchDescriptor<LocalAsset>())
        let scanAssets = assets.filter {
            [scan.sourceAssetID, scan.geometryAssetID, scan.modelAssetID].contains($0.id)
        }
        #expect(scanAssets.count == 3)
        #expect(scanAssets.allSatisfy {
            environment.files.fileExists(atRelativePath: $0.relativeFilePath)
        })
    }

    @Test("Repeated save taps cannot duplicate a scan")
    func duplicatePrevention() throws {
        let environment = try TestEnvironment()
        let output = try output()
        let project = try environment.projects.create(name: "Project")
        let floor = try #require(project.sortedFloors.first)
        let service = ScanPersistenceService(
            context: environment.context,
            files: environment.files,
            artifactProducer: FakeScanArtifactProducer()
        )
        _ = try service.save(
            output: output,
            project: project,
            floor: floor,
            existingRoom: nil,
            roomName: "Room"
        )

        #expect(throws: ScanPersistenceError.duplicateScan) {
            try service.save(
                output: output,
                project: project,
                floor: floor,
                existingRoom: nil,
                roomName: "Room"
            )
        }
        #expect(try environment.count(SavedScan.self) == 1)
    }

    @Test("Existing-room association keeps a separate scan version")
    func existingRoomVersions() throws {
        let environment = try TestEnvironment()
        let project = try environment.projects.create(name: "Project")
        let floor = try #require(project.sortedFloors.first)
        let room = try environment.rooms.addRoom(to: floor, draft: RoomDraft(name: "Office"))

        let first = try output()
        let second = try output()
        _ = try save(first, environment: environment, existingRoom: room)
        _ = try save(second, environment: environment, existingRoom: room)

        let scans = try ScanPersistenceService(
            context: environment.context,
            files: environment.files
        ).scans(roomID: room.id)
        #expect(scans.count == 2)
        #expect(Set(scans.map(\.id)) == [first.scanID, second.scanID])
    }

    @Test("Artifact failure preserves the in-memory result and writes no metadata")
    func exportFailure() throws {
        let environment = try TestEnvironment()
        let output = try output()
        let project = try environment.projects.create(name: "Project")
        let floor = try #require(project.sortedFloors.first)
        let service = ScanPersistenceService(
            context: environment.context,
            files: environment.files,
            artifactProducer: FakeScanArtifactProducer(shouldFail: true)
        )

        #expect(throws: FileStorageError.self) {
            try service.save(
                output: output,
                project: project,
                floor: floor,
                existingRoom: nil,
                roomName: "Room"
            )
        }
        #expect(try environment.count(SavedScan.self) == 0)
        #expect(try environment.count(LocalAsset.self) == 0)
    }

    @Test("Database failure rolls back metadata and finalized files")
    func databaseFailureRecovery() throws {
        let environment = try TestEnvironment()
        let output = try output()
        let project = try environment.projects.create(name: "Project")
        let floor = try #require(project.sortedFloors.first)
        let service = ScanPersistenceService(
            context: environment.context,
            files: environment.files,
            artifactProducer: FakeScanArtifactProducer(),
            saveContext: { throw FileStorageError.writeFailed("database injected") }
        )

        #expect(throws: FileStorageError.self) {
            try service.save(
                output: output,
                project: project,
                floor: floor,
                existingRoom: nil,
                roomName: "Room"
            )
        }
        #expect(try environment.count(SavedScan.self) == 0)
        #expect(try environment.count(LocalAsset.self) == 0)
        let scanDirectory = environment.files.projectDirectory(for: project.id)
            .appending(path: "Scans/\(output.scanID.uuidString)")
        #expect(FileManager.default.fileExists(atPath: scanDirectory.path()) == false)
    }

    @Test("Deleting a room removes scan metadata and its bundle")
    func deletionCleanup() throws {
        let environment = try TestEnvironment()
        let output = try output()
        let association = try save(output, environment: environment)
        let room = try #require(
            try environment.context.fetch(FetchDescriptor<Room>())
                .first { $0.id == association.roomID }
        )

        try environment.rooms.deleteRoom(room)
        #expect(try environment.count(SavedScan.self) == 0)
        let directory = environment.files.projectDirectory(for: association.projectID)
            .appending(path: "Scans/\(output.scanID.uuidString)")
        #expect(FileManager.default.fileExists(atPath: directory.path()) == false)
    }

    @Test("Real scan saving does not modify the sample project")
    func samplePreservation() throws {
        let environment = try TestEnvironment()
        let seededSample = try SampleProjectSeeder.seedIfNeeded(
            context: environment.context,
            files: environment.files,
            settings: environment.settings,
            defaults: environment.defaults
        )
        let sample = try #require(seededSample)
        let sampleName = sample.name
        let sampleAssetCount = sample.assets.count

        _ = try save(try output(), environment: environment)

        #expect(sample.isSample)
        #expect(sample.name == sampleName)
        #expect(sample.assets.count == sampleAssetCount)
    }

    @Test("Schema V1 stores migrate to V2 without deleting projects")
    func migrationCompatibility() throws {
        let root = URL.temporaryDirectory
            .appending(path: "Migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appending(path: "legacy.store")

        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let legacy = try ModelContainer(for: schema, configurations: configuration)
            let project = Project(name: "Legacy project")
            legacy.mainContext.insert(project)
            try legacy.mainContext.save()
        }

        let migrated = try Persistence.makeContainer(storeURL: storeURL)
        let projects = try migrated.mainContext.fetch(FetchDescriptor<Project>())
        #expect(projects.map(\.name) == ["Legacy project"])
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<SavedScan>()) == 0)
    }

    @Test("Empty model export is rejected without database metadata")
    func emptyModelRejected() throws {
        let environment = try TestEnvironment()
        let output = try output()
        let project = try environment.projects.create(name: "Project")
        let floor = try #require(project.sortedFloors.first)
        let service = ScanPersistenceService(
            context: environment.context,
            files: environment.files,
            artifactProducer: FakeScanArtifactProducer(modelData: Data())
        )

        #expect(throws: FileStorageError.self) {
            try service.save(
                output: output,
                project: project,
                floor: floor,
                existingRoom: nil,
                roomName: "Room"
            )
        }
        #expect(try environment.count(SavedScan.self) == 0)
        #expect(try environment.count(LocalAsset.self) == 0)
    }

    @Test("Startup cleanup removes staging only and preserves finalized scans")
    func stagingCleanup() throws {
        let environment = try TestEnvironment()
        let project = try environment.projects.create(name: "Project")
        let scans = environment.files.projectDirectory(for: project.id)
            .appending(path: "Scans", directoryHint: .isDirectory)
        let staging = scans.appending(path: ".staging-interrupted", directoryHint: .isDirectory)
        let final = scans.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: final, withIntermediateDirectories: true)

        #expect(try environment.files.removeStaleScanStagingDirectories() == 1)
        #expect(FileManager.default.fileExists(atPath: staging.path()) == false)
        #expect(FileManager.default.fileExists(atPath: final.path()))
    }

    @Test("Live artifact producer refuses a missing real CapturedRoom")
    func missingCapturedRoom() throws {
        let output = try output()
        #expect(throws: ScanArtifactError.missingCapturedRoom) {
            try RoomPlanScanArtifactProducer().prepareArtifacts(for: output)
        }
    }
}
