@preconcurrency import AVFoundation
import AVKit
import ImageIO
import SwiftUI

struct PhotoScanThumbnail: View {
    let url: URL
    let kind: PhotoScanMediaKind
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: kind == .video ? "video" : "photo")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay {
                if kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
        }
        .task(id: url) {
            image = await PhotoScanPreviewImage.load(url, kind: kind, size: 384)
        }
        .accessibilityHidden(true)
    }
}

struct PhotoScanMediaPreview: View {
    let item: PhotoScanMedia
    let url: URL
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var image: CGImage?

    var body: some View {
        NavigationStack {
            Group {
                if let player { VideoPlayer(player: player) }
                else if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
                else if failed {
                    ContentUnavailableView(settings.t(item.kind == .photo
                        ? "photoscan.preview.photoError" : "photoscan.preview.videoError"),
                        systemImage: "exclamationmark.circle")
                } else { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle(settings.t(item.kind.titleKey))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("common.close")) { dismiss() }
                }
            }
        }
        .task {
            if item.kind == .video {
                let asset = AVURLAsset(url: url)
                if (try? await asset.load(.isPlayable)) == true {
                    player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                } else { failed = true }
            } else {
                image = await PhotoScanPreviewImage.load(url, kind: .photo, size: 1400)
                failed = image == nil
            }
        }
    }
}

private enum PhotoScanPreviewImage {
    static func load(_ url: URL, kind: PhotoScanMediaKind, size: CGFloat) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            if kind == .video {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: size, height: size)
                return try? await generator.image(at: .zero).image
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(size)
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}
