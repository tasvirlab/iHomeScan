import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import iHomeScan

private final class FakeRoomCaptureController: RoomCaptureControlling {
    var onEvent: ((RoomCaptureEvent) -> Void)?
    #if canImport(UIKit)
    var previewView: UIView? { nil }
    #endif

    private(set) var startCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private(set) var invalidateCount = 0

    func start() {
        startCount += 1
    }

    func finish() {
        finishCount += 1
    }

    func cancel() {
        cancelCount += 1
    }

    func invalidate() {
        invalidateCount += 1
        onEvent = nil
    }

    func send(_ event: RoomCaptureEvent) {
        onEvent?(event)
    }
}

private struct CaptureCapabilities: DeviceCapabilityChecking {
    var isRoomCaptureSupported: Bool
    var isSimulator = false
}

private struct CaptureCamera: CameraAuthorizationProviding {
    var status: CameraAuthorization

    func requestAccess() async -> Bool {
        status == .authorized
    }
}

@MainActor
@Suite("Room scan session")
struct RoomScanSessionTests {
    private func model(
        controller: FakeRoomCaptureController,
        supported: Bool = true,
        authorization: CameraAuthorization = .authorized
    ) -> RoomScanSessionModel {
        RoomScanSessionModel(
            controller: controller,
            capabilities: CaptureCapabilities(isRoomCaptureSupported: supported),
            camera: CaptureCamera(status: authorization)
        )
    }

    private func output(walls: Int = 1, objects: Int = 0) -> RoomScanOutput {
        RoomScanOutput(
            scanID: UUID(),
            summary: RoomScanSummary(
                walls: walls,
                doors: 0,
                windows: 0,
                openings: 0,
                objects: objects,
                floors: 0
            ),
            floorPlan: FloorPlan(
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                rooms: [],
                outerWalls: [],
                innerWalls: [],
                doors: [],
                windows: [],
                dimensions: []
            ),
            capturedAt: .now,
            capturedRoom: nil
        )
    }

    @Test("Begins only when RoomPlan and camera access are available")
    func beginChecksPrerequisites() {
        let unsupportedController = FakeRoomCaptureController()
        let unsupported = model(controller: unsupportedController, supported: false)
        unsupported.begin()
        #expect(unsupported.state == .failed(.unsupportedDevice))
        #expect(unsupportedController.startCount == 0)

        let deniedController = FakeRoomCaptureController()
        let denied = model(controller: deniedController, authorization: .denied)
        denied.begin()
        #expect(denied.state == .failed(.cameraPermissionDenied))
        #expect(deniedController.startCount == 0)

        let readyController = FakeRoomCaptureController()
        let ready = model(controller: readyController)
        ready.begin()
        #expect(ready.state == .preparing)
        #expect(readyController.startCount == 1)
    }

    @Test("Start, finish and processed result follow the expected state sequence")
    func successfulCapture() {
        let controller = FakeRoomCaptureController()
        let model = model(controller: controller)

        model.begin()
        controller.send(.started)
        #expect(model.state == .scanning)

        model.finish()
        #expect(model.state == .processing)
        #expect(controller.finishCount == 1)

        let result = output(walls: 4, objects: 2)
        controller.send(.completed(result))
        #expect(model.state == .completed(result.summary))
        #expect(model.output?.summary == result.summary)
    }

    @Test("An empty processed room is rejected")
    func emptyResult() {
        let controller = FakeRoomCaptureController()
        let model = model(controller: controller)

        model.begin()
        controller.send(.started)
        model.finish()
        controller.send(.completed(output(walls: 0)))

        #expect(model.state == .failed(.emptyResult))
        #expect(model.output == nil)
    }

    @Test("Cancel discards the scan and ignores late callbacks")
    func cancelIgnoresLateResult() {
        let controller = FakeRoomCaptureController()
        let model = model(controller: controller)

        model.begin()
        controller.send(.started)
        model.cancel()
        controller.send(.completed(output()))

        #expect(model.state == .cancelled)
        #expect(model.output == nil)
        #expect(controller.cancelCount == 1)
    }

    @Test("Backgrounding stops a live scan with an interruption error")
    func backgroundInterruption() {
        let controller = FakeRoomCaptureController()
        let model = model(controller: controller)

        model.begin()
        controller.send(.started)
        model.appDidEnterBackground()

        #expect(model.state == .failed(.interrupted))
        #expect(controller.cancelCount == 1)
    }

    @Test("Teardown stops capture, releases callbacks and drops output")
    func teardown() {
        let controller = FakeRoomCaptureController()
        let model = model(controller: controller)

        model.begin()
        controller.send(.started)
        model.tearDown()
        controller.send(.completed(output()))

        #expect(model.state == .cancelled)
        #expect(model.output == nil)
        #expect(controller.cancelCount == 1)
        #expect(controller.invalidateCount == 1)
    }
}
