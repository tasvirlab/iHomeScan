import Foundation
import Observation

/// What the scanner entry screen should show. Derived only from the real device capability
/// and camera authorization — never assumed.
enum ScannerReadinessState: Equatable {
    case checkingDevice
    /// RoomPlan is unavailable. `isSimulator` distinguishes the Simulator from a non-LiDAR device.
    case unsupportedDevice(isSimulator: Bool)
    /// Supported device, camera permission not asked yet — explain before asking.
    case cameraPermissionRequired
    case cameraPermissionDenied
    case cameraRestricted
    case readyToScan
    case unexpectedError
}

/// Scanner readiness state machine, kept separate from SwiftUI for testability.
///
/// Rules:
/// - Device capability is checked first; unsupported devices never reach a permission prompt.
/// - `refresh()` only *reads* authorization; the system prompt is shown solely from
///   `requestCameraAccess()`, which the UI calls after an explicit user tap.
@Observable
final class ScannerReadinessModel {
    private(set) var state: ScannerReadinessState = .checkingDevice
    /// True while the system permission prompt is on screen.
    private(set) var isRequestingAccess = false

    @ObservationIgnored private let capabilities: DeviceCapabilityChecking
    @ObservationIgnored private let camera: CameraAuthorizationProviding

    init(
        capabilities: DeviceCapabilityChecking = RoomPlanCapabilityChecker(),
        camera: CameraAuthorizationProviding = SystemCameraAuthorization()
    ) {
        self.capabilities = capabilities
        self.camera = camera
    }

    /// Device capability, when known (nil while checking or on error).
    var isDeviceSupported: Bool? {
        switch state {
        case .checkingDevice, .unexpectedError: nil
        case .unsupportedDevice: false
        default: true
        }
    }

    /// Re-evaluates the state. Call on appear and whenever the app returns to the foreground
    /// (e.g. after the user changed camera access in Settings).
    func refresh() {
        state = evaluate()
    }

    /// Asks for camera permission. Only valid after the user chose to continue from the
    /// explanation shown in `.cameraPermissionRequired`; ignored in every other state.
    func requestCameraAccess() async {
        guard state == .cameraPermissionRequired, !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        _ = await camera.requestAccess()
        // Re-read the real status rather than trusting the callback value.
        state = evaluate()
    }

    private func evaluate() -> ScannerReadinessState {
        guard capabilities.isRoomCaptureSupported else {
            return .unsupportedDevice(isSimulator: capabilities.isSimulator)
        }
        switch camera.status {
        case .notDetermined: return .cameraPermissionRequired
        case .authorized: return .readyToScan
        case .denied: return .cameraPermissionDenied
        case .restricted: return .cameraRestricted
        case .unknown: return .unexpectedError
        }
    }
}
