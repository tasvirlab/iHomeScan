import Foundation
import SwiftData

enum SavedScanLoadingError: Error, Equatable {
    case missingGeometry
    case invalidGeometry
    case missingModel
    case invalidModel
}

struct SavedScanContent {
    let floorPlan: FloorPlan
    let modelURL: URL?
    let modelError: SavedScanLoadingError?
}

@MainActor
struct SavedScanContentLoader {
    let context: ModelContext
    let files: LocalFileStorageService

    func load(_ scan: SavedScan) throws -> SavedScanContent {
        let geometryAsset = try asset(id: scan.geometryAssetID, type: .roomGeometry)
        let geometryData: Data
        do {
            geometryData = try files.read(
                relativePath: geometryAsset.relativeFilePath,
                expectedChecksum: geometryAsset.checksum
            )
        } catch FileStorageError.fileMissing {
            throw SavedScanLoadingError.missingGeometry
        } catch {
            throw SavedScanLoadingError.invalidGeometry
        }

        let plan: FloorPlan
        do {
            plan = try FloorPlan.decode(from: geometryData)
        } catch {
            throw SavedScanLoadingError.invalidGeometry
        }

        do {
            let modelURL = try validatedModelURL(for: scan)
            return SavedScanContent(floorPlan: plan, modelURL: modelURL, modelError: nil)
        } catch let error as SavedScanLoadingError {
            return SavedScanContent(floorPlan: plan, modelURL: nil, modelError: error)
        } catch {
            return SavedScanContent(floorPlan: plan, modelURL: nil, modelError: .invalidModel)
        }
    }

    private func validatedModelURL(for scan: SavedScan) throws -> URL {
        let modelAsset = try asset(id: scan.modelAssetID, type: .usdzModel)
        let modelURL: URL
        do {
            modelURL = try files.url(forRelativePath: modelAsset.relativeFilePath)
        } catch {
            throw SavedScanLoadingError.missingModel
        }
        guard FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) else {
            throw SavedScanLoadingError.missingModel
        }
        do {
            let values = try modelURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size > 0, Int64(size) == modelAsset.fileSize else {
                throw SavedScanLoadingError.invalidModel
            }
        } catch let error as SavedScanLoadingError {
            throw error
        } catch FileStorageError.fileMissing {
            throw SavedScanLoadingError.missingModel
        } catch {
            throw SavedScanLoadingError.invalidModel
        }
        return modelURL
    }

    private func asset(id: UUID, type: AssetType) throws -> LocalAsset {
        var descriptor = FetchDescriptor<LocalAsset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let asset = try context.fetch(descriptor).first else {
            throw type == .roomGeometry ? SavedScanLoadingError.missingGeometry : .missingModel
        }
        guard asset.type == type else {
            throw type == .roomGeometry ? SavedScanLoadingError.invalidGeometry : .invalidModel
        }
        return asset
    }
}
