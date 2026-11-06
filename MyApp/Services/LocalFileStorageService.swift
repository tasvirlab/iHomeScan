import Foundation
import CryptoKit

enum FileStorageError: LocalizedError, Equatable {
    case invalidPath(String)
    case fileMissing(String)
    case corrupted(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "Invalid storage path: \(path)"
        case .fileMissing(let path): "File is missing: \(path)"
        case .corrupted(let path): "File is corrupted: \(path)"
        case .writeFailed(let reason): "Could not write file: \(reason)"
        }
    }
}

/// Result of storing a file; persisted as `LocalAsset` metadata.
struct StoredFile: Equatable {
    let relativePath: String
    let fileName: String
    let fileSize: Int64
    let checksum: String
}

struct StoredScanBundle: Equatable {
    let scanID: UUID
    let source: StoredFile
    let geometry: StoredFile
    let model: StoredFile
}

/// Manages project files inside the app's private Application Support directory:
///
///     <root>/Projects/<projectUUID>/{Scans,Models,Photos,Reports}/<file>
///
/// Only paths relative to `rootURL` are handed out for persistence, so data survives
/// container path changes between installs and restores.
final class LocalFileStorageService {
    let rootURL: URL
    private let fileManager = FileManager.default

    /// - Parameter rootURL: Storage root. Defaults to `Application Support/iHomeScan`. Tests pass a temporary directory.
    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? URL.applicationSupportDirectory
            self.rootURL = support.appending(path: "iHomeScan", directoryHint: .isDirectory)
        }
    }

    // MARK: - Paths

    var projectsDirectory: URL { rootURL.appending(path: "Projects", directoryHint: .isDirectory) }

    func projectDirectory(for projectID: UUID) -> URL {
        projectsDirectory.appending(path: projectID.uuidString, directoryHint: .isDirectory)
    }

    /// Resolves a stored relative path, rejecting anything that would escape the storage root.
    func url(forRelativePath relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !relativePath.hasPrefix("/"), !components.isEmpty,
              !components.contains(where: { $0 == ".." || $0 == "." }) else {
            throw FileStorageError.invalidPath(relativePath)
        }
        return rootURL.appending(path: relativePath, directoryHint: .notDirectory)
    }

    // MARK: - Writing

    /// Writes `data` atomically (temp file + rename), so a failed write never leaves a partial file.
    /// A unique file name is chosen if `preferredFileName` already exists.
    @discardableResult
    func save(_ data: Data, projectID: UUID, type: AssetType, preferredFileName: String) throws -> StoredFile {
        let directory = try ensureDirectory(projectID: projectID, type: type)
        let fileName = uniqueFileName(sanitized(preferredFileName), in: directory)
        let destination = directory.appending(path: fileName, directoryHint: .notDirectory)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
        return StoredFile(
            relativePath: relativePath(for: destination),
            fileName: fileName,
            fileSize: Int64(data.count),
            checksum: Self.checksum(of: data)
        )
    }

    /// Copies a (possibly large) file into storage. The copy goes to a temporary name in the
    /// destination folder first and is renamed only after it completes.
    @discardableResult
    func importFile(at sourceURL: URL, projectID: UUID, type: AssetType, preferredFileName: String? = nil) throws -> StoredFile {
        let directory = try ensureDirectory(projectID: projectID, type: type)
        let fileName = uniqueFileName(sanitized(preferredFileName ?? sourceURL.lastPathComponent), in: directory)
        let destination = directory.appending(path: fileName, directoryHint: .notDirectory)
        let partial = directory.appending(path: ".\(UUID().uuidString).partial", directoryHint: .notDirectory)
        do {
            try fileManager.copyItem(at: sourceURL, to: partial)
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
        return StoredFile(
            relativePath: relativePath(for: destination),
            fileName: fileName,
            fileSize: Int64(data.count),
            checksum: Self.checksum(of: data)
        )
    }

    /// Commits all required scan artifacts as one directory. Files are first written to a
    /// staging directory and validated, then the directory is atomically renamed into place.
    func saveScanBundle(
        sourceData: Data,
        geometryData: Data,
        modelURL: URL,
        projectID: UUID,
        scanID: UUID
    ) throws -> StoredScanBundle {
        guard !sourceData.isEmpty, !geometryData.isEmpty else {
            throw FileStorageError.writeFailed("empty scan data")
        }

        let scansDirectory = projectDirectory(for: projectID)
            .appending(path: AssetType.roomGeometry.folderName, directoryHint: .isDirectory)
        let destination = scansDirectory.appending(path: scanID.uuidString, directoryHint: .isDirectory)
        let staging = scansDirectory.appending(
            path: ".staging-\(scanID.uuidString)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw FileStorageError.writeFailed("scan already exists")
        }

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let sourceURL = staging.appending(path: "roomplan.json")
            let geometryURL = staging.appending(path: "geometry.json")
            let stagedModelURL = staging.appending(path: "room.usdz")
            try sourceData.write(
                to: sourceURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try geometryData.write(
                to: geometryURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try fileManager.copyItem(at: modelURL, to: stagedModelURL)

            let sourceFile = try validatedStoredFile(at: sourceURL)
            let geometryFile = try validatedStoredFile(at: geometryURL)
            let modelFile = try validatedStoredFile(at: stagedModelURL)
            // Resolve final relative paths while the staging URL still exists. Some file-system
            // URL standardization behaviors change after the directory has been moved.
            let committedSource = storedScanFile(sourceFile, projectID: projectID, scanID: scanID)
            let committedGeometry = storedScanFile(geometryFile, projectID: projectID, scanID: scanID)
            let committedModel = storedScanFile(modelFile, projectID: projectID, scanID: scanID)
            try fileManager.moveItem(at: staging, to: destination)

            return StoredScanBundle(
                scanID: scanID,
                source: committedSource,
                geometry: committedGeometry,
                model: committedModel
            )
        } catch let error as FileStorageError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
    }

    func deleteScanDirectory(projectID: UUID, scanID: UUID) throws {
        let directory = projectDirectory(for: projectID)
            .appending(path: AssetType.roomGeometry.folderName, directoryHint: .isDirectory)
            .appending(path: scanID.uuidString, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
    }

    /// Lazily stores the editable parametric artifact beside an existing scan bundle.
    /// Original RoomPlan, FloorPlan and USDZ files are never modified.
    @discardableResult
    func saveParametricPlan(_ data: Data, projectID: UUID, scanID: UUID) throws -> StoredFile {
        guard !data.isEmpty else { throw FileStorageError.writeFailed("empty parametric geometry") }
        let directory = projectDirectory(for: projectID)
            .appending(path: AssetType.roomGeometry.folderName, directoryHint: .isDirectory)
            .appending(path: scanID.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            throw FileStorageError.fileMissing(scanID.uuidString)
        }
        let destination = directory.appending(path: "parametric-v1.json", directoryHint: .notDirectory)
        do {
            try data.write(
                to: destination,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
        return StoredFile(
            relativePath: relativePath(for: destination),
            fileName: destination.lastPathComponent,
            fileSize: Int64(data.count),
            checksum: Self.checksum(of: data)
        )
    }

    func readParametricPlan(projectID: UUID, scanID: UUID) throws -> Data {
        let relativePath = [
            "Projects", projectID.uuidString, AssetType.roomGeometry.folderName,
            scanID.uuidString, "parametric-v1.json",
        ].joined(separator: "/")
        return try read(relativePath: relativePath)
    }

    func parametricPlanExists(projectID: UUID, scanID: UUID) -> Bool {
        let relativePath = [
            "Projects", projectID.uuidString, AssetType.roomGeometry.folderName,
            scanID.uuidString, "parametric-v1.json",
        ].joined(separator: "/")
        return fileExists(atRelativePath: relativePath)
    }

    /// Stores accepted precision edits separately, preserving `parametric-v1.json` as the baseline.
    @discardableResult
    func savePrecisionPlan(_ data: Data, projectID: UUID, scanID: UUID) throws -> StoredFile {
        guard !data.isEmpty else { throw FileStorageError.writeFailed("empty precision geometry") }
        let directory = projectDirectory(for: projectID)
            .appending(path: AssetType.roomGeometry.folderName, directoryHint: .isDirectory)
            .appending(path: scanID.uuidString, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            throw FileStorageError.fileMissing(scanID.uuidString)
        }
        let destination = directory.appending(path: "precision-v2.json", directoryHint: .notDirectory)
        do {
            try data.write(
                to: destination,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
        return StoredFile(
            relativePath: relativePath(for: destination),
            fileName: destination.lastPathComponent,
            fileSize: Int64(data.count),
            checksum: Self.checksum(of: data)
        )
    }

    func readPrecisionPlan(projectID: UUID, scanID: UUID) throws -> Data {
        try read(relativePath: precisionPlanPath(projectID: projectID, scanID: scanID))
    }

    func precisionPlanExists(projectID: UUID, scanID: UUID) -> Bool {
        fileExists(atRelativePath: precisionPlanPath(projectID: projectID, scanID: scanID))
    }

    private func precisionPlanPath(projectID: UUID, scanID: UUID) -> String {
        [
            "Projects", projectID.uuidString, AssetType.roomGeometry.folderName,
            scanID.uuidString, "precision-v2.json",
        ].joined(separator: "/")
    }

    // MARK: - Reading

    func fileExists(atRelativePath relativePath: String) -> Bool {
        guard let url = try? url(forRelativePath: relativePath) else { return false }
        return fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Reads a stored file. When `expectedChecksum` is given, verifies integrity.
    func read(relativePath: String, expectedChecksum: String? = nil) throws -> Data {
        let url = try url(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw FileStorageError.fileMissing(relativePath)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if let expectedChecksum, Self.checksum(of: data) != expectedChecksum {
            throw FileStorageError.corrupted(relativePath)
        }
        return data
    }

    // MARK: - Deleting

    /// Deletes a stored file. Missing files are ignored (the goal state is already reached).
    func deleteFile(atRelativePath relativePath: String) throws {
        let url = try url(forRelativePath: relativePath)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Removes everything stored for a project.
    func deleteProjectDirectory(for projectID: UUID) throws {
        let directory = projectDirectory(for: projectID)
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
    }

    /// Project IDs that have a directory on disk.
    func storedProjectIDs() -> Set<UUID> {
        let names = (try? fileManager.contentsOfDirectory(atPath: projectsDirectory.path(percentEncoded: false))) ?? []
        return Set(names.compactMap(UUID.init(uuidString:)))
    }

    /// Removes only scan staging directories left by an interrupted save. Final UUID-named scan
    /// directories are never touched.
    @discardableResult
    func removeStaleScanStagingDirectories() throws -> Int {
        var removed = 0
        for projectID in storedProjectIDs() {
            let scans = projectDirectory(for: projectID)
                .appending(path: AssetType.roomGeometry.folderName, directoryHint: .isDirectory)
            let entries = (try? fileManager.contentsOfDirectory(
                at: scans,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []
            for entry in entries where entry.lastPathComponent.hasPrefix(".staging-") {
                try fileManager.removeItem(at: entry)
                removed += 1
            }
        }
        return removed
    }

    // MARK: - Helpers

    private func validatedStoredFile(at url: URL) throws -> StoredFile {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw FileStorageError.fileMissing(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw FileStorageError.corrupted(url.lastPathComponent) }
        return StoredFile(
            relativePath: relativePath(for: url),
            fileName: url.lastPathComponent,
            fileSize: Int64(data.count),
            checksum: Self.checksum(of: data)
        )
    }

    private func storedScanFile(_ file: StoredFile, projectID: UUID, scanID: UUID) -> StoredFile {
        StoredFile(
            relativePath: [
                "Projects", projectID.uuidString, AssetType.roomGeometry.folderName,
                scanID.uuidString, file.fileName,
            ].joined(separator: "/"),
            fileName: file.fileName,
            fileSize: file.fileSize,
            checksum: file.checksum
        )
    }

    static func checksum(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func ensureDirectory(projectID: UUID, type: AssetType) throws -> URL {
        let directory = projectDirectory(for: projectID).appending(path: type.folderName, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
        return directory
    }

    private func relativePath(for url: URL) -> String {
        let root = rootURL.standardizedFileURL.path(percentEncoded: false)
        let full = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// Keeps file names portable: letters (any script), digits, `-`, `_`, `.`, `,`, `()` and spaces.
    private func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_., ()"))
        var cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if cleaned.isEmpty { cleaned = "file" }
        return String(cleaned.prefix(120))
    }

    /// Appends " (2)", " (3)"… before the extension until the name is free.
    private func uniqueFileName(_ name: String, in directory: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var counter = 2
        while fileManager.fileExists(atPath: directory.appending(path: candidate).path(percentEncoded: false)) {
            candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            counter += 1
        }
        return candidate
    }
}
