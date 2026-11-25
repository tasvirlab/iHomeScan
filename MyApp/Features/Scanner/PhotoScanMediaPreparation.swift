@preconcurrency import AVFoundation
import CoreTransferable
import ImageIO
import UniformTypeIdentifiers

/// File copies keep large provider assets off the main actor and out of memory.
nonisolated struct PhotoScanImport: Transferable, Sendable {
    let url: URL
    let kind: PhotoScanMediaKind

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try copy(received.file, kind: .photo)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try copy(received.file, kind: .video)
        }
    }

    private static func copy(_ original: URL, kind: PhotoScanMediaKind) throws -> Self {
        let copied = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(original.pathExtension.isEmpty ? kind.fileExtension : original.pathExtension)
        try FileManager.default.copyItem(at: original, to: copied)
        return Self(url: copied, kind: kind)
    }
}

enum PhotoScanMediaPreparation {
    nonisolated static let videoLimitSeconds: Double = 60

    /// Normalize orientation and discard library metadata such as GPS.
    nonisolated static func photo(from url: URL, to target: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PhotoScanDraftError.unreadableMedia
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3072
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let writer = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoScanDraftError.unreadableMedia
        }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw PhotoScanDraftError.unreadableMedia }
    }

    /// Export the video track alone, preserving its display transform and omitting audio and location metadata.
    static func video(from url: URL, to target: URL, captured: Bool) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0,
              let source = try await asset.loadTracks(withMediaType: .video).first else {
            throw PhotoScanDraftError.unreadableMedia
        }
        let limit = CMTime(seconds: videoLimitSeconds, preferredTimescale: 600)
        guard captured || duration <= limit else { throw PhotoScanDraftError.videoTooLong }
        let sourceRange = try await source.load(.timeRange)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw PhotoScanDraftError.unreadableMedia }
        track.preferredTransform = try await source.load(.preferredTransform)
        let range = CMTimeRange(start: sourceRange.start, duration: min(sourceRange.duration, limit))
        try track.insertTimeRange(range, of: source, at: .zero)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw PhotoScanDraftError.unreadableMedia
        }
        export.metadata = []
        if #available(iOS 18, macOS 15, visionOS 2, *) {
            try await export.export(to: target, as: .mov)
        } else {
            export.outputURL = target
            export.outputFileType = .mov
            await export.export()
            guard export.status == .completed else { throw export.error ?? PhotoScanDraftError.unreadableMedia }
        }
    }
}
