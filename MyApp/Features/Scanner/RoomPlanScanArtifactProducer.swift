import Foundation
#if canImport(RoomPlan)
import RoomPlan
#endif

struct PreparedScanArtifacts {
    let sourceData: Data
    let geometryData: Data
    let modelURL: URL
    let temporaryDirectory: URL
}

protocol ScanArtifactProducing {
    func prepareArtifacts(for output: RoomScanOutput) throws -> PreparedScanArtifacts
}

enum ScanArtifactError: Error, Equatable {
    case missingCapturedRoom
    case invalidExport
}

/// Uses RoomPlan's Codable representation and official USD export API.
struct RoomPlanScanArtifactProducer: ScanArtifactProducing {
    func prepareArtifacts(for output: RoomScanOutput) throws -> PreparedScanArtifacts {
        #if canImport(RoomPlan)
        guard let capturedRoom = output.capturedRoom else {
            throw ScanArtifactError.missingCapturedRoom
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "iHomeScan-Scan-\(output.scanID.uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let sourceData = try encoder.encode(capturedRoom)
            let geometryData = try output.floorPlan.encoded()
            let modelURL = directory.appending(path: "room.usdz")
            try capturedRoom.export(to: modelURL, exportOptions: .mesh)

            guard !sourceData.isEmpty,
                  !geometryData.isEmpty,
                  FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)),
                  (try Data(contentsOf: modelURL, options: .mappedIfSafe)).isEmpty == false
            else {
                throw ScanArtifactError.invalidExport
            }

            _ = try JSONDecoder().decode(CapturedRoom.self, from: sourceData)
            _ = try FloorPlan.decode(from: geometryData)
            return PreparedScanArtifacts(
                sourceData: sourceData,
                geometryData: geometryData,
                modelURL: modelURL,
                temporaryDirectory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        #else
        throw ScanArtifactError.missingCapturedRoom
        #endif
    }
}
