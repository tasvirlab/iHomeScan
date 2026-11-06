import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(RoomPlan)
import RoomPlan
#endif

/// Lifecycle of one RoomPlan capture.
enum RoomScanState: Equatable {
    case idle
    /// Camera and AR session are starting.
    case preparing
    /// Live capture is running.
    case scanning
    /// Capture stopped; RoomPlan is building the final `CapturedRoom`.
    case processing
    /// A real, non-empty `CapturedRoom` was received.
    case completed(RoomScanSummary)
    case cancelled
    case failed(RoomScanFailure)

    /// States in which the camera / capture session may be running.
    var isActive: Bool {
        switch self {
        case .preparing, .scanning, .processing: true
        default: false
        }
    }

    var isFinal: Bool {
        switch self {
        case .completed, .cancelled, .failed: true
        default: false
        }
    }
}

/// Why a scan could not produce a result. Each case has a localized explanation.
enum RoomScanFailure: Equatable {
    case unsupportedDevice
    case cameraPermissionDenied
    /// The capture session could not start or stopped with an internal error.
    case sessionFailed
    /// The app left the foreground or the AR session was interrupted.
    case interrupted
    /// World tracking was lost (e.g. camera covered, too dark, moved too fast).
    case trackingLost
    case deviceTooHot
    case sceneTooLarge
    /// RoomPlan could not build the final room model.
    case processingFailed
    /// Capture finished but contained no walls, openings or objects.
    case emptyResult

    var titleKey: String { "scan.failure.\(keySuffix).title" }
    var bodyKey: String { "scan.failure.\(keySuffix).body" }

    /// Whether starting a new scan right away can help.
    var isRetryable: Bool {
        switch self {
        case .unsupportedDevice, .cameraPermissionDenied: false
        default: true
        }
    }

    private var keySuffix: String {
        switch self {
        case .unsupportedDevice: "unsupported"
        case .cameraPermissionDenied: "permission"
        case .sessionFailed: "session"
        case .interrupted: "interrupted"
        case .trackingLost: "tracking"
        case .deviceTooHot: "hot"
        case .sceneTooLarge: "tooLarge"
        case .processingFailed: "processing"
        case .emptyResult: "empty"
        }
    }

    #if canImport(RoomPlan)
    /// Maps a RoomPlan error. `duringProcessing` selects the fallback for unknown errors.
    init(roomPlanError error: Error, duringProcessing: Bool) {
        if let captureError = error as? RoomCaptureSession.CaptureError {
            switch captureError {
            case .deviceNotSupported: self = .unsupportedDevice
            case .deviceTooHot: self = .deviceTooHot
            case .exceedSceneSizeLimit: self = .sceneTooLarge
            case .worldTrackingFailure: self = .trackingLost
            case .invalidARConfiguration, .internalError: self = .sessionFailed
            @unknown default: self = duringProcessing ? .processingFailed : .sessionFailed
            }
        } else {
            self = duringProcessing ? .processingFailed : .sessionFailed
        }
    }
    #endif
}

/// Counts of what RoomPlan actually detected. Measurements are processed in Stage 2.3.
struct RoomScanSummary: Equatable {
    var walls: Int
    var doors: Int
    var windows: Int
    var openings: Int
    var objects: Int
    var floors: Int

    /// A usable scan has at least one detected surface or object.
    var hasContent: Bool { walls + doors + windows + openings + objects > 0 }
}

/// The in-memory result of a finished scan. Not persisted in Stage 2.2.
struct RoomScanOutput {
    let summary: RoomScanSummary
    let capturedAt: Date
    #if canImport(RoomPlan)
    /// The real RoomPlan result, kept for geometry processing in Stage 2.3.
    let capturedRoom: CapturedRoom?
    #endif
}

#if canImport(RoomPlan)
extension RoomScanSummary {
    init(_ room: CapturedRoom) {
        self.init(
            walls: room.walls.count,
            doors: room.doors.count,
            windows: room.windows.count,
            openings: room.openings.count,
            objects: room.objects.count,
            floors: room.floors.count
        )
    }
}
#endif

/// Events a capture controller reports back to the session model.
enum RoomCaptureEvent {
    case started
    case completed(RoomScanOutput)
    case failed(RoomScanFailure)
}

/// Abstraction over the RoomPlan capture view/session so the state machine can be tested
/// without LiDAR hardware.
protocol RoomCaptureControlling: AnyObject {
    /// Set by the session model; called on the main actor.
    var onEvent: ((RoomCaptureEvent) -> Void)? { get set }
    #if canImport(UIKit)
    /// The live camera view to display while scanning (nil for test doubles).
    var previewView: UIView? { get }
    #endif
    /// Starts a capture. Must be a no-op while one is already running.
    func start()
    /// Stops capturing and processes the result (`.completed` or `.failed` follows).
    func finish()
    /// Stops capturing and discards everything; no further events are sent.
    func cancel()
    /// Releases the camera view and delegates. Call when the scan screen goes away.
    func invalidate()
}
