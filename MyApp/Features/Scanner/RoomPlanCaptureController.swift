#if canImport(RoomPlan) && canImport(UIKit)
import UIKit
import RoomPlan

/// Live capture through Apple's `RoomCaptureView`, which provides the camera feed, native
/// coaching instructions and the detected-surface overlay.
///
/// The view is created lazily in `start()`, so nothing touches the camera before the user
/// explicitly starts a scan on a supported device.
final class RoomPlanCaptureController: NSObject, RoomCaptureControlling {
    var onEvent: ((RoomCaptureEvent) -> Void)?

    private var captureView: RoomCaptureView?
    /// True between `run` and the session's end callback; prevents duplicate sessions.
    private var isRunning = false
    /// Set by `cancel()`; results arriving afterwards are dropped and not processed.
    private var isCancelled = false

    override init() {
        super.init()
    }

    /// `RoomCaptureViewDelegate` inherits `NSCoding`; this controller is never archived.
    required init?(coder: NSCoder) {
        nil
    }

    var previewView: UIView? { captureView }

    func start() {
        guard !isRunning else { return }
        let view = captureView ?? RoomCaptureView(frame: .zero)
        view.delegate = self
        captureView = view
        isCancelled = false
        isRunning = true

        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        view.captureSession.run(configuration: configuration)
        onEvent?(.started)
    }

    func finish() {
        guard isRunning, let captureView else { return }
        isRunning = false
        // Stops capture and pauses the AR session (camera off); RoomPlan then calls
        // captureView(shouldPresent:error:) followed by captureView(didPresent:error:).
        captureView.captureSession.stop()
    }

    func cancel() {
        isCancelled = true
        guard isRunning, let captureView else { return }
        isRunning = false
        captureView.captureSession.stop(pauseARSession: true)
    }

    func invalidate() {
        cancel()
        captureView?.delegate = nil
        captureView = nil
        onEvent = nil
    }
}

// RoomCaptureViewDelegate is main-actor isolated in the SDK; callbacks arrive on the main thread.
extension RoomPlanCaptureController: RoomCaptureViewDelegate {
    func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        // The session has ended (by finish, cancel, or on its own because of an error).
        isRunning = false
        if isCancelled { return false }
        if let error {
            onEvent?(.failed(RoomScanFailure(roomPlanError: error, duringProcessing: false)))
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        guard !isCancelled else { return }
        if let error {
            onEvent?(.failed(RoomScanFailure(roomPlanError: error, duringProcessing: true)))
            return
        }
        do {
            let floorPlan = try RoomGeometryProcessor().process(
                RoomGeometrySource(capturedRoom: processedResult)
            )
            onEvent?(.completed(RoomScanOutput(
                scanID: UUID(),
                summary: RoomScanSummary(processedResult),
                floorPlan: floorPlan,
                capturedAt: .now,
                capturedRoom: processedResult
            )))
        } catch {
            onEvent?(.failed(.processingFailed))
        }
    }
}
#endif
