#if os(iOS)
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// A serial queue owns the session, outputs, and capture completion handlers.
nonisolated final class PhotoScanCameraSession: NSObject, @unchecked Sendable {
    typealias PhotoCompletion = @Sendable (Data?) -> Void
    typealias VideoCompletion = @Sendable (URL?) -> Void

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "iHomeScan.photoScan.camera")
    private let photos = AVCapturePhotoOutput()
    private let movie = AVCaptureMovieFileOutput()
    private var photoCompletion: PhotoCompletion?
    private var videoCompletion: VideoCompletion?
    private var stopRequested = false

    func start() async -> Bool {
        await withCheckedContinuation { completion in
            queue.async {
                let ready = !self.session.inputs.isEmpty || self.configure()
                if ready && !self.session.isRunning { self.session.startRunning() }
                completion.resume(returning: ready && self.session.isRunning)
            }
        }
    }

    func stop() {
        queue.async {
            if self.movie.isRecording { self.movie.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func takePhoto(angle: CGFloat, completion: @escaping PhotoCompletion) {
        queue.async {
            guard self.session.isRunning, self.photoCompletion == nil else { completion(nil); return }
            self.photoCompletion = completion
            self.setAngle(angle, on: self.photos.connection(with: .video))
            self.photos.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func recordVideo(angle: CGFloat, completion: @escaping VideoCompletion) {
        queue.async {
            guard self.session.isRunning, self.videoCompletion == nil else { completion(nil); return }
            self.videoCompletion = completion
            self.stopRequested = false
            self.setAngle(angle, on: self.movie.connection(with: .video))
            let target = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString).appendingPathExtension("mov")
            self.movie.startRecording(to: target, recordingDelegate: self)
        }
    }

    func finishVideo() {
        queue.async {
            self.stopRequested = true
            if self.movie.isRecording { self.movie.stopRecording() }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        guard session.canAddOutput(photos) else {
            session.removeInput(input)
            return false
        }
        session.addOutput(photos)
        guard session.canAddOutput(movie) else {
            session.removeOutput(photos)
            session.removeInput(input)
            return false
        }
        session.addOutput(movie)
        movie.maxRecordedDuration = CMTime(seconds: PhotoScanMediaPreparation.videoLimitSeconds, preferredTimescale: 600)
        return true
    }

    private func setAngle(_ angle: CGFloat, on connection: AVCaptureConnection?) {
        if let connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}

extension PhotoScanCameraSession: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            let completion = self.photoCompletion
            self.photoCompletion = nil
            completion?(data)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]
    ) {
        queue.async {
            if self.stopRequested && self.movie.isRecording { self.movie.stopRecording() }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection], error: Error?
    ) {
        let successfullyFinished = error == nil ||
            ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        queue.async {
            let completion = self.videoCompletion
            self.videoCompletion = nil
            self.stopRequested = false
            if !successfullyFinished { try? FileManager.default.removeItem(at: fileURL) }
            completion?(successfullyFinished ? fileURL : nil)
        }
    }
}

struct PhotoScanCameraView: View {
    @Binding var draft: PhotoScanDraft
    let onRequestSave: () -> Void
    let onCapture: (URL, PhotoScanMediaKind) async -> Bool

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = PhotoScanCameraSession()
    @State private var kind: PhotoScanMediaKind = .photo
    @State private var ready = false
    @State private var busy = false
    @State private var recording = false
    @State private var showsCameraError = false
    @State private var startDate: Date?
    private var photoCount: Int { draft.kind == .photo ? draft.media.count : 0 }
    private var canSavePhotos: Bool { kind == .photo && photoCount > 0 }

    var body: some View {
        VStack(spacing: 13) {
            HStack {
                Button(settings.t(canSavePhotos ? "common.save" : "common.close")) {
                    if canSavePhotos { onRequestSave() }
                    dismiss()
                }
                .font(Typography.control)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .disabled(busy || recording)
                .accessibilityIdentifier(canSavePhotos ? "photoscan.camera.save" : "photoscan.camera.close")
                Spacer()
                if let startDate, recording {
                    TimelineView(.periodic(from: startDate, by: 1)) { timeline in
                        let seconds = min(60, max(0, Int(timeline.date.timeIntervalSince(startDate))))
                        Text("\(seconds) / 60 s").monospacedDigit().accessibilityAddTraits(.updatesFrequently)
                    }
                } else if kind == .photo {
                    Text(settings.t("photoscan.count", photoCount))
                        .font(Typography.control)
                        .monospacedDigit()
                        .accessibilityIdentifier("photoscan.camera.count")
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            CameraPreview(session: ready ? camera.session : nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .accessibilityHidden(true)
            if draft.media.isEmpty {
                Picker(settings.t("photoscan.kind"), selection: $kind) {
                    ForEach(PhotoScanMediaKind.allCases) { Text(settings.t($0.titleKey)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(busy || recording)
                .padding(.horizontal, Spacing.screenEdge)
            }
            Text(settings.t(kind == .photo ? "photoscan.photo.tip" : "photoscan.video.tip"))
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenEdge)

            Button(action: shutter) {
                Image(systemName: recording ? "stop.fill" : kind == .photo ? "camera.fill" : "record.circle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 64, height: 64)
                    .background(Palette.accent, in: .circle)
            }
            .accessibilityLabel(settings.t(recording ? "photoscan.camera.stop" :
                                           kind == .photo ? "photoscan.camera.shutter" : "photoscan.camera.record"))
            .disabled(!ready || busy)
            .overlay { if busy { ProgressView().tint(Palette.onAccent).allowsHitTesting(false) } }
            .padding(.bottom, 4)
        }
        .background(Palette.background.ignoresSafeArea())
        .tint(Palette.accentText)
        .task {
            kind = draft.kind ?? .photo
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            ready = await camera.start()
            if Task.isCancelled { camera.stop() }
            else { showsCameraError = !ready }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && recording { shutter() }
        }
        .onDisappear {
            camera.stop()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .alert(settings.t("photoscan.camera.error"), isPresented: $showsCameraError) {
            Button(settings.t("common.close"), role: .cancel) { if !ready { dismiss() } }
        }
    }

    private func shutter() {
        if recording {
            recording = false
            busy = true
            camera.finishVideo()
            return
        }
        if kind == .video {
            startDate = .now
            recording = true
            camera.recordVideo(angle: captureAngle) { url in
                Task { @MainActor in
                    recording = false
                    busy = true
                    await accept(url, kind: .video)
                }
            }
        } else {
            busy = true
            camera.takePhoto(angle: captureAngle) { data in
                Task { @MainActor in
                    guard let data else { busy = false; showsCameraError = true; return }
                    let url = FileManager.default.temporaryDirectory
                        .appending(path: UUID().uuidString)
                    do {
                        try data.write(to: url)
                        await accept(url, kind: .photo)
                    } catch {
                        busy = false
                        showsCameraError = true
                    }
                }
            }
        }
    }

    private var captureAngle: CGFloat {
        switch UIDevice.current.orientation {
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .portraitUpsideDown: 270
        default: 90
        }
    }

    private func accept(_ url: URL?, kind: PhotoScanMediaKind) async {
        defer { busy = false }
        guard let url else { showsCameraError = true; return }
        defer { try? FileManager.default.removeItem(at: url) }
        if await onCapture(url, kind) {
            if kind == .video { dismiss() }
        } else {
            showsCameraError = true
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewSurface { PreviewSurface() }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        view.setNeedsLayout()
    }

    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            let orientation: UIInterfaceOrientation?
            if #available(iOS 26, *) { orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation }
            else { orientation = window?.windowScene?.interfaceOrientation }
            let angle: CGFloat
            switch orientation {
            case .landscapeLeft: angle = 180
            case .landscapeRight: angle = 0
            case .portraitUpsideDown: angle = 270
            default: angle = 90
            }
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}
#endif
