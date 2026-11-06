import Foundation
import AVFoundation
#if canImport(RoomPlan)
import RoomPlan
#endif

/// Whether this device can run a RoomPlan capture session.
protocol DeviceCapabilityChecking {
    /// `RoomCaptureSession.isSupported` — true only on LiDAR devices running a supported OS.
    var isRoomCaptureSupported: Bool { get }
    /// True when running in the iOS Simulator (no camera, no LiDAR).
    var isSimulator: Bool { get }
}

/// Live capability check through Apple's official RoomPlan API. Never inspects model names.
struct RoomPlanCapabilityChecker: DeviceCapabilityChecking {
    var isRoomCaptureSupported: Bool {
        #if canImport(RoomPlan) && os(iOS) && !targetEnvironment(simulator)
        RoomCaptureSession.isSupported
        #else
        false
        #endif
    }

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

/// Camera authorization, mirrored from `AVAuthorizationStatus` so it can be faked in tests.
enum CameraAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    /// A status added in a future OS that this version doesn't know how to handle.
    case unknown
}

protocol CameraAuthorizationProviding {
    var status: CameraAuthorization { get }
    /// Shows the system permission prompt (only when the status is `.notDetermined`).
    func requestAccess() async -> Bool
}

/// Live camera permission through AVFoundation. Only video access is ever requested —
/// no microphone or location permission.
struct SystemCameraAuthorization: CameraAuthorizationProviding {
    var status: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
