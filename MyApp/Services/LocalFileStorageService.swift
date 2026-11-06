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

    // MARK: - Helpers

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
