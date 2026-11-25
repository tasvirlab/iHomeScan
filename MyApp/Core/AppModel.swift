import SwiftUI
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case home, projects, settings

    var id: String { rawValue }

    var titleKey: String { "tab.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .projects: "square.grid.2x2"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Screens pushed onto the root navigation stack.
enum Route: Hashable {
    case project(UUID)
    case photoScanDrafts
    case photoScanDraft(String)
    case reports(UUID)
    case savedScan(projectID: UUID, roomID: UUID, scanID: UUID?)
}

/// Where a scan was started from. Stage 2.2 saves the captured plan to this floor.
struct ScannerContext: Identifiable, Equatable {
    let id = UUID()
    var projectID: UUID?
    var floorID: UUID?
}

private enum PendingScanDestination {
    case photo(ScannerContext)
    case lidar(ScannerContext)
}

/// Transient UI message shown at the top of the screen.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let messageKey: String
}

/// App-wide navigation and transient UI state. Persistent data lives in SwiftData.
@Observable
final class AppModel {
    var selectedTab: AppTab = .home
    var path: [Route] = []
    var toast: Toast?
    /// Presents the "New project" sheet from anywhere in the app.
    var isCreatingProject = false
    /// Presents the scanner readiness screen.
    var scanner: ScannerContext?
    /// Presents the reusable FotoScan / LiDARScan choice sheet.
    var scanPicker: ScannerContext?
    /// Opens a new Photo Scan capture.
    var photoScan: ScannerContext?

    @ObservationIgnored private var pendingScanDestination: PendingScanDestination?

    func openScanner(projectID: UUID? = nil, floorID: UUID? = nil) {
        scanner = ScannerContext(projectID: projectID, floorID: floorID)
    }

    func openPhotoScan(projectID: UUID? = nil, floorID: UUID? = nil) {
        photoScan = ScannerContext(projectID: projectID, floorID: floorID)
    }

    func openScanPicker(projectID: UUID? = nil, floorID: UUID? = nil) {
        scanPicker = ScannerContext(projectID: projectID, floorID: floorID)
    }

    /// Defers the destination until the choice sheet has fully dismissed, avoiding
    /// competing SwiftUI presentations while preserving its project/floor context.
    func choosePhotoScan(from context: ScannerContext) {
        pendingScanDestination = .photo(context)
        scanPicker = nil
    }

    func chooseLidarScan(from context: ScannerContext) {
        pendingScanDestination = .lidar(context)
        scanPicker = nil
    }

    func presentPendingScanDestination() {
        defer { pendingScanDestination = nil }
        switch pendingScanDestination {
        case .photo(let context): photoScan = context
        case .lidar(let context): scanner = context
        case .none: break
        }
    }

    func open(_ project: Project) {
        path.append(.project(project.id))
    }

    func openSavedScan(_ association: SavedScanAssociation) {
        selectedTab = .projects
        path = [
            .project(association.projectID),
            .savedScan(
                projectID: association.projectID,
                roomID: association.roomID,
                scanID: association.scanID
            ),
        ]
        scanner = nil
    }

    func showToast(_ messageKey: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            toast = Toast(messageKey: messageKey)
        }
    }

    /// Shows a localized message for a failed operation.
    func showError(_ error: Error) {
        switch error {
        case RepositoryError.emptyName: showToast("error.emptyName")
        case RepositoryError.invalidMeasurement: showToast("error.invalidMeasurement")
        case RepositoryError.lastFloor: showToast("error.lastFloor")
        case FileStorageError.fileMissing: showToast("error.fileMissing")
        case FileStorageError.corrupted: showToast("error.fileCorrupted")
        default: showToast("error.generic")
        }
    }
}

extension LocalFileStorageService {
    /// The app's single storage instance (Application Support/iHomeScan).
    static let shared = LocalFileStorageService()
}

extension EnvironmentValues {
    /// Shared on-disk file storage. Tests and previews can inject an instance with a temporary root.
    @Entry var fileStorage: LocalFileStorageService = .shared
}
