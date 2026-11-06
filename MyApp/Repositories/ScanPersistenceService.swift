import Foundation
import SwiftData

enum ScanPersistenceError: Error, Equatable {
    case duplicateScan
    case invalidAssociation
    case emptyRoomName
    case missingGeometryMetadata
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
        guard let metadata = output.floorPlan.roomPlanMetadata else {
            throw ScanPersistenceError.missingGeometryMetadata
        }

        let prepared = try artifactProducer.prepareArtifacts(for: output)
        defer { try? FileManager.default.removeItem(at: prepared.temporaryDirectory) }

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
