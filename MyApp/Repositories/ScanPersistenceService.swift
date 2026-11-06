import Foundation
import SwiftData

enum ScanPersistenceError: Error, Equatable {
    case duplicateScan
    case invalidAssociation
    case emptyRoomName
    case missingGeometryMetadata
}

enum ScanProjectDestination: Equatable {
    case new(name: String)
    case existing(projectID: UUID)
}

enum ScanFloorDestination: Equatable {
    case automatic
    case new
    case existing(floorID: UUID)
}

enum ScanRoomDestination: Equatable {
    case new(name: String)
    case existing(roomID: UUID)
}

struct ScanSaveRequest: Equatable {
    let project: ScanProjectDestination
    let floor: ScanFloorDestination
    let room: ScanRoomDestination
}

struct SavedScanAssociation: Equatable {
    let scanID: UUID
    let projectID: UUID
    let projectName: String
    let floorID: UUID
    let roomID: UUID
    let roomName: String
}

@MainActor
struct ScanPersistenceService {
    let context: ModelContext
    let files: LocalFileStorageService
    let artifactProducer: any ScanArtifactProducing
    private let saveContext: () throws -> Void

    init(
        context: ModelContext,
        files: LocalFileStorageService,
        artifactProducer: (any ScanArtifactProducing)? = nil,
        saveContext: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.files = files
        self.artifactProducer = artifactProducer ?? RoomPlanScanArtifactProducer()
        self.saveContext = saveContext ?? { try context.save() }
    }

    func save(
        output: RoomScanOutput,
        request: ScanSaveRequest
    ) throws -> SavedScanAssociation {
        guard try savedScan(id: output.scanID) == nil else {
            throw ScanPersistenceError.duplicateScan
        }
        guard output.floorPlan.roomPlanMetadata != nil else {
            throw ScanPersistenceError.missingGeometryMetadata
        }

        let prepared = try artifactProducer.prepareArtifacts(for: output)
        defer { try? FileManager.default.removeItem(at: prepared.temporaryDirectory) }

        var projectIDForCleanup: UUID?
        do {
            let project = try resolveProject(request.project)
            projectIDForCleanup = project.id
            let floor = try resolveFloor(request.floor, project: project)
            let existingRoom = try resolveRoom(request.room, floor: floor)
            let roomName: String
            switch request.room {
            case .new(let name): roomName = name
            case .existing:
                guard let existingRoom else { throw ScanPersistenceError.invalidAssociation }
                roomName = existingRoom.name
            }
            return try persist(
                output: output,
                prepared: prepared,
                project: project,
                floor: floor,
                existingRoom: existingRoom,
                roomName: roomName
            )
        } catch {
            context.rollback()
            if let projectIDForCleanup {
                try? files.deleteScanDirectory(projectID: projectIDForCleanup, scanID: output.scanID)
            }
            throw error
        }
    }

    func save(
        output: RoomScanOutput,
        project: Project,
        floor: Floor,
        existingRoom: Room?,
        roomName: String
    ) throws -> SavedScanAssociation {
        guard try savedScan(id: output.scanID) == nil else {
            throw ScanPersistenceError.duplicateScan
        }
        guard floor.project?.id == project.id else {
            throw ScanPersistenceError.invalidAssociation
        }
        if let existingRoom, existingRoom.floor?.id != floor.id {
            throw ScanPersistenceError.invalidAssociation
        }
        guard let name = roomName.nilIfBlank else {
            throw ScanPersistenceError.emptyRoomName
        }
        guard output.floorPlan.roomPlanMetadata != nil else {
            throw ScanPersistenceError.missingGeometryMetadata
        }

        let prepared = try artifactProducer.prepareArtifacts(for: output)
        defer { try? FileManager.default.removeItem(at: prepared.temporaryDirectory) }

        return try persist(
            output: output,
            prepared: prepared,
            project: project,
            floor: floor,
            existingRoom: existingRoom,
            roomName: name
        )
    }

    private func persist(
        output: RoomScanOutput,
        prepared: PreparedScanArtifacts,
        project: Project,
        floor: Floor,
        existingRoom: Room?,
        roomName: String
    ) throws -> SavedScanAssociation {
        guard let metadata = output.floorPlan.roomPlanMetadata else {
            throw ScanPersistenceError.missingGeometryMetadata
        }
        guard let name = roomName.nilIfBlank else { throw ScanPersistenceError.emptyRoomName }
        let bundle = try files.saveScanBundle(
            sourceData: prepared.sourceData,
            geometryData: prepared.geometryData,
            modelURL: prepared.modelURL,
            projectID: project.id,
            scanID: output.scanID
        )

        do {
            let room: Room
            if let existingRoom {
                room = existingRoom
                room.name = name
                room.updatedAt = .now
            } else {
                room = Room(name: name)
                context.insert(room)
                room.floor = floor
            }

            room.geometryIdentifier = metadata.roomIdentifier.uuidString
            if room.area == nil {
                room.area = metadata.floorArea
            }

            let sourceAsset = makeAsset(bundle.source, type: .roomPlanSource)
            let geometryAsset = makeAsset(bundle.geometry, type: .roomGeometry)
            let modelAsset = makeAsset(bundle.model, type: .usdzModel)
            for asset in [sourceAsset, geometryAsset, modelAsset] {
                context.insert(asset)
                asset.project = project
                asset.floor = floor
                asset.room = room
            }

            let scan = SavedScan(
                id: output.scanID,
                projectID: project.id,
                floorID: floor.id,
                roomID: room.id,
                createdAt: output.capturedAt,
                completeness: metadata.completeness,
                floorArea: metadata.floorArea,
                sourceAssetID: sourceAsset.id,
                geometryAssetID: geometryAsset.id,
                modelAssetID: modelAsset.id
            )
            context.insert(scan)
            project.status = .scanned
            project.updatedAt = .now
            try saveContext()

            return SavedScanAssociation(
                scanID: scan.id,
                projectID: project.id,
                projectName: project.name,
                floorID: floor.id,
                roomID: room.id,
                roomName: room.name
            )
        } catch {
            context.rollback()
            try? files.deleteScanDirectory(projectID: project.id, scanID: output.scanID)
            throw error
        }
    }

    private func resolveProject(_ destination: ScanProjectDestination) throws -> Project {
        switch destination {
        case .new(let name):
            guard let name = name.nilIfBlank else { throw RepositoryError.emptyName }
            let project = Project(name: name)
            context.insert(project)
            return project
        case .existing(let projectID):
            var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })
            descriptor.fetchLimit = 1
            guard let project = try context.fetch(descriptor).first, !project.isSample else {
                throw ScanPersistenceError.invalidAssociation
            }
            return project
        }
    }

    private func resolveFloor(_ destination: ScanFloorDestination, project: Project) throws -> Floor {
        switch destination {
        case .automatic:
            if let floor = project.sortedFloors.first { return floor }
            return makeFloor(project: project)
        case .new:
            return makeFloor(project: project)
        case .existing(let floorID):
            guard let floor = project.floors.first(where: { $0.id == floorID }) else {
                throw ScanPersistenceError.invalidAssociation
            }
            return floor
        }
    }

    private func makeFloor(project: Project) -> Floor {
        let level = (project.floors.map(\.level).max() ?? 0) + 1
        let floor = Floor(level: level, name: "")
        context.insert(floor)
        floor.project = project
        return floor
    }

    private func resolveRoom(_ destination: ScanRoomDestination, floor: Floor) throws -> Room? {
        switch destination {
        case .new(let name):
            guard name.nilIfBlank != nil else { throw ScanPersistenceError.emptyRoomName }
            return nil
        case .existing(let roomID):
            guard let room = floor.rooms.first(where: { $0.id == roomID }) else {
                throw ScanPersistenceError.invalidAssociation
            }
            return room
        }
    }

    func savedScan(id: UUID) throws -> SavedScan? {
        var descriptor = FetchDescriptor<SavedScan>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func scans(projectID: UUID) throws -> [SavedScan] {
        try context.fetch(
            FetchDescriptor<SavedScan>(
                predicate: #Predicate { $0.projectID == projectID },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    func scans(roomID: UUID) throws -> [SavedScan] {
        try context.fetch(
            FetchDescriptor<SavedScan>(
                predicate: #Predicate { $0.roomID == roomID },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    func delete(_ scan: SavedScan) throws {
        let projectID = scan.projectID
        let scanID = scan.id
        let assetIDs = [scan.sourceAssetID, scan.geometryAssetID, scan.modelAssetID]
        let assets = try context.fetch(
            FetchDescriptor<LocalAsset>(predicate: #Predicate { assetIDs.contains($0.id) })
        )
        for asset in assets {
            context.delete(asset)
        }
        context.delete(scan)
        try context.save()
        try files.deleteScanDirectory(projectID: projectID, scanID: scanID)
    }

    private func makeAsset(_ file: StoredFile, type: AssetType) -> LocalAsset {
        LocalAsset(
            type: type,
            relativeFilePath: file.relativePath,
            fileName: file.fileName,
            fileSize: file.fileSize,
            checksum: file.checksum
        )
    }
}
