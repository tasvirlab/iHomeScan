import Foundation
import SwiftData

/// Stores files through `LocalFileStorageService` and records their `LocalAsset` metadata.
struct AssetRepository {
    let context: ModelContext
    let files: LocalFileStorageService

    /// Writes the file first, then the metadata. If the database save fails, the file is removed again.
    @discardableResult
    func addAsset(
        _ data: Data,
        type: AssetType,
        fileName: String,
        project: Project,
        floor: Floor? = nil,
        room: Room? = nil
    ) throws -> LocalAsset {
        let stored = try files.save(data, projectID: project.id, type: type, preferredFileName: fileName)
        let asset = LocalAsset(
            type: type,
            relativeFilePath: stored.relativePath,
            fileName: stored.fileName,
            fileSize: stored.fileSize,
            checksum: stored.checksum
        )
        context.insert(asset)
        asset.project = project
        asset.floor = floor
        asset.room = room
        project.updatedAt = .now
        do {
            try context.save()
        } catch {
            context.delete(asset)
            try? files.deleteFile(atRelativePath: stored.relativePath)
            throw error
        }
        return asset
    }

    func delete(_ asset: LocalAsset) throws {
        let path = asset.relativeFilePath
        context.delete(asset)
        try context.save()
        try files.deleteFile(atRelativePath: path)
    }

    func url(for asset: LocalAsset) throws -> URL {
        try files.url(forRelativePath: asset.relativeFilePath)
    }

    /// Reads the file and verifies its checksum.
    func data(for asset: LocalAsset) throws -> Data {
        try files.read(relativePath: asset.relativeFilePath, expectedChecksum: asset.checksum)
    }

    // MARK: - Floor plans

    /// Saves plan geometry JSON for a floor and marks the project as scanned.
    @discardableResult
    func savePlan(_ plan: FloorPlan, for floor: Floor) throws -> LocalAsset {
        guard let project = floor.project else { throw FileStorageError.invalidPath("floor without project") }
        let asset = try addAsset(try plan.encoded(), type: .roomGeometry,
                                 fileName: "floor-\(floor.level)-plan.json", project: project, floor: floor)
        project.status = .scanned
        try context.save()
        return asset
    }

    func loadPlan(_ asset: LocalAsset) throws -> FloorPlan {
        do {
            return try FloorPlan.decode(from: data(for: asset))
        } catch let error as FileStorageError {
            throw error
        } catch {
            throw FileStorageError.corrupted(asset.relativeFilePath)
        }
    }
}
