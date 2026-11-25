import Foundation
import Testing
@testable import iHomeScan

/// Test double for RoomPlan support.
private struct FakeCapabilities: DeviceCapabilityChecking {
    var isRoomCaptureSupported: Bool
    var isSimulator = false
}

/// Test double for camera permission. Records prompts so tests can prove none happen implicitly.
private final class FakeCamera: CameraAuthorizationProviding {
    var status: CameraAuthorization
    /// Status after the user answers the system prompt.
    var statusAfterPrompt: CameraAuthorization
    private(set) var requestCount = 0

    init(_ status: CameraAuthorization, afterPrompt: CameraAuthorization = .authorized) {
        self.status = status
        self.statusAfterPrompt = afterPrompt
    }

    func requestAccess() async -> Bool {
        requestCount += 1
        status = statusAfterPrompt
        return status == .authorized
    }
}

@MainActor
@Suite("Scanner readiness")
struct ScannerReadinessTests {
    private func model(supported: Bool = true, simulator: Bool = false, camera: FakeCamera) -> ScannerReadinessModel {
        ScannerReadinessModel(
            capabilities: FakeCapabilities(isRoomCaptureSupported: supported, isSimulator: simulator),
            camera: camera
        )
    }

    @Test("Starts in the checking state and never prompts on creation")
    func initialState() {
        let camera = FakeCamera(.notDetermined)
        let model = model(camera: camera)
        #expect(model.state == .checkingDevice)
        #expect(model.isDeviceSupported == nil)
        #expect(camera.requestCount == 0)
    }

    @Test("Supported device with camera access is ready to scan")
    func supportedAndAuthorized() {
        let model = model(camera: FakeCamera(.authorized))
        model.refresh()
        #expect(model.state == .readyToScan)
        #expect(model.isDeviceSupported == true)
    }

    @Test("Unsupported device is reported and never asks for the camera",
          arguments: [CameraAuthorization.notDetermined, .authorized, .denied, .restricted])
    func unsupportedDevice(status: CameraAuthorization) async {
        let camera = FakeCamera(status)
        let model = model(supported: false, camera: camera)
        model.refresh()
        #expect(model.state == .unsupportedDevice(isSimulator: false))
        #expect(model.isDeviceSupported == false)

        await model.requestCameraAccess()
        #expect(camera.requestCount == 0)
        #expect(model.state == .unsupportedDevice(isSimulator: false))
    }

    @Test("Simulator falls back to an unsupported state instead of pretending to scan")
    func simulatorFallback() {
        let model = model(supported: false, simulator: true, camera: FakeCamera(.authorized))
        model.refresh()
        #expect(model.state == .unsupportedDevice(isSimulator: true))
    }

    @Test("Live capability checker reports no RoomPlan support in the Simulator")
    func liveCheckerInSimulator() {
        let checker = RoomPlanCapabilityChecker()
        #if targetEnvironment(simulator)
        #expect(checker.isSimulator)
        #expect(!checker.isRoomCaptureSupported)
        #else
        #expect(!checker.isSimulator)
        #endif
    }

    @Test("Undetermined permission asks for an explanation first; refresh alone never prompts")
    func notDetermined() {
        let camera = FakeCamera(.notDetermined)
        let model = model(camera: camera)
        model.refresh()
        model.refresh()
        #expect(model.state == .cameraPermissionRequired)
        #expect(camera.requestCount == 0)
    }

    @Test("Granting access after the explanation moves to ready")
    func grantTransitionsToReady() async {
        let camera = FakeCamera(.notDetermined, afterPrompt: .authorized)
        let model = model(camera: camera)
        model.refresh()

        await model.requestCameraAccess()

        #expect(camera.requestCount == 1)
        #expect(model.state == .readyToScan)
        #expect(!model.isRequestingAccess)
    }

    @Test("Declining access after the explanation moves to denied")
    func declineTransitionsToDenied() async {
        let camera = FakeCamera(.notDetermined, afterPrompt: .denied)
        let model = model(camera: camera)
        model.refresh()

        await model.requestCameraAccess()

        #expect(model.state == .cameraPermissionDenied)
    }

    @Test("Denied and restricted are distinct states and do not prompt again",
          arguments: [(CameraAuthorization.denied, ScannerReadinessState.cameraPermissionDenied),
                      (.restricted, .cameraRestricted)])
    func deniedAndRestricted(status: CameraAuthorization, expected: ScannerReadinessState) async {
        let camera = FakeCamera(status)
        let model = model(camera: camera)
        model.refresh()
        #expect(model.state == expected)

        await model.requestCameraAccess()
        #expect(camera.requestCount == 0)
        #expect(model.state == expected)
    }

    @Test("Unknown future authorization values surface as an unexpected error")
    func unknownStatus() {
        let model = model(camera: FakeCamera(.unknown))
        model.refresh()
        #expect(model.state == .unexpectedError)
        #expect(model.isDeviceSupported == nil)
    }

    @Test("Refresh picks up changes made in Settings while the app was in the background")
    func refreshAfterSettings() {
        let camera = FakeCamera(.denied)
        let model = model(camera: camera)
        model.refresh()
        #expect(model.state == .cameraPermissionDenied)

        camera.status = .authorized // user enabled the camera in Settings
        model.refresh()
        #expect(model.state == .readyToScan)

        camera.status = .denied // and turned it off again
        model.refresh()
        #expect(model.state == .cameraPermissionDenied)
    }

    @Test("Opening the scanner does not create or change any local data")
    func noDataSideEffects() throws {
        let env = try TestEnvironment()
        let project = try env.projects.create(name: "Untouched")
        let updatedAt = project.updatedAt
        let appModel = AppModel()

        appModel.openScanner(projectID: project.id, floorID: project.floors.first?.id)
        let scanner = model(camera: FakeCamera(.authorized))
        scanner.refresh()

        #expect(appModel.scanner?.projectID == project.id)
        #expect(scanner.state == .readyToScan)
        #expect(try env.count(Project.self) == 1)
        #expect(try env.count(Room.self) == 0)
        #expect(try env.count(LocalAsset.self) == 0)
        #expect(project.updatedAt == updatedAt)
        #expect(project.status == .draft)
    }

    @Test("Scan choice preserves project and floor context for FotoScan")
    func photoChoicePreservesContext() {
        let projectID = UUID()
        let floorID = UUID()
        let appModel = AppModel()

        appModel.openScanPicker(projectID: projectID, floorID: floorID)
        let context = appModel.scanPicker
        #expect(context?.projectID == projectID)
        #expect(context?.floorID == floorID)

        if let context { appModel.choosePhotoScan(from: context) }
        #expect(appModel.scanPicker == nil)
        #expect(appModel.photoScan == nil)
        appModel.presentPendingScanDestination()

        #expect(appModel.photoScan?.projectID == projectID)
        #expect(appModel.photoScan?.floorID == floorID)
        #expect(appModel.scanner == nil)
    }

    @Test("Scan choice preserves project and floor context for LiDARScan")
    func lidarChoicePreservesContext() {
        let projectID = UUID()
        let floorID = UUID()
        let appModel = AppModel()

        appModel.openScanPicker(projectID: projectID, floorID: floorID)
        if let context = appModel.scanPicker { appModel.chooseLidarScan(from: context) }
        appModel.presentPendingScanDestination()

        #expect(appModel.scanner?.projectID == projectID)
        #expect(appModel.scanner?.floorID == floorID)
        #expect(appModel.photoScan == nil)
    }

    @Test("Closing scan choice without selection opens no workflow")
    func closingChoiceDoesNotNavigate() {
        let appModel = AppModel()
        appModel.openScanPicker()
        appModel.scanPicker = nil
        appModel.presentPendingScanDestination()

        #expect(appModel.photoScan == nil)
        #expect(appModel.scanner == nil)
    }
}
