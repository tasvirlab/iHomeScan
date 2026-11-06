import Foundation
import Observation

/// State machine for one scanning screen.
///
/// Guarantees:
/// - Only one capture runs at a time: `begin()` works only from `.idle`, and the controller is
///   asked to start only from there.
/// - A result is accepted only while capturing/processing; anything arriving after cancel,
///   failure or backgrounding is ignored, so a failed scan is never shown as completed.
/// - Results stay in memory only (Stage 2.2) and are dropped on cancel, discard and teardown.
@Observable
final class RoomScanSessionModel {
    private(set) var state: RoomScanState = .idle
    /// The finished scan, present only in `.completed`.
    private(set) var output: RoomScanOutput?

    @ObservationIgnored let controller: RoomCaptureControlling
    @ObservationIgnored private let capabilities: DeviceCapabilityChecking
    @ObservationIgnored private let camera: CameraAuthorizationProviding

    init(
        controller: RoomCaptureControlling,
        capabilities: DeviceCapabilityChecking = RoomPlanCapabilityChecker(),
        camera: CameraAuthorizationProviding = SystemCameraAuthorization()
    ) {
        self.controller = controller
        self.capabilities = capabilities
        self.camera = camera
        // Weak capture: the controller must not keep the model alive.
        controller.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - User intents

    /// Starts a scan after re-checking device support and camera access.
    func begin() {
        guard state == .idle else { return }
        guard capabilities.isRoomCaptureSupported else {
            state = .failed(.unsupportedDevice)
            return
        }
        guard camera.status == .authorized else {
            state = .failed(.cameraPermissionDenied)
            return
        }
        state = .preparing
        controller.start()
    }

    /// Ends capturing and asks RoomPlan for the final result.
    func finish() {
        guard state == .scanning else { return }
        state = .processing
        controller.finish()
    }

    /// Discards the running scan.
    func cancel() {
        guard state.isActive else { return }
        state = .cancelled
        output = nil
        controller.cancel()
    }

    /// Starts over after a finished, cancelled or failed scan.
    func scanAgain() {
        guard state.isFinal else { return }
        output = nil
        state = .idle
        begin()
    }

    /// Drops a completed result (the user chose to close it).
    func discardResult() {
        guard case .completed = state else { return }
        output = nil
        state = .idle
    }

    // MARK: - System events

    /// The app moved to the background: a live capture cannot continue, so stop the camera.
    /// Processing that already started is allowed to finish.
    func appDidEnterBackground() {
        guard state == .preparing || state == .scanning else { return }
        state = .failed(.interrupted)
        controller.cancel()
    }

    /// The scan screen is going away: make sure the camera is off and nothing is retained.
    func tearDown() {
        if state.isActive {
            state = .cancelled
            controller.cancel()
        }
        output = nil
        controller.invalidate()
    }

    // MARK: - Controller events

    private func handle(_ event: RoomCaptureEvent) {
        switch event {
        case .started:
            guard state == .preparing else { return }
            state = .scanning

        case .completed(let result):
            // RoomPlan may also end a capture on its own, so accept results while scanning too.
            guard state == .processing || state == .scanning else { return }
            guard result.summary.hasContent else {
                state = .failed(.emptyResult)
                return
            }
            output = result
            state = .completed(result.summary)

        case .failed(let failure):
            guard state.isActive else { return }
            state = .failed(failure)
            output = nil
            controller.cancel()
        }
    }
}
