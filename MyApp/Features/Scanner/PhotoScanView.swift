@preconcurrency import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PhotoScanView: View {
    let context: ScannerContext

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fileStorage) private var files
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var draft = PhotoScanDraft()
    @State private var showExit = false
    @State private var closeAfterDestination = false
    @State private var busy = false
    @State private var showCamera = false
    @State private var saveAfterCamera = false
    @State private var showGallery = false
    @State private var showDestination = false
    @State private var showCameraSettings = false
    @State private var galleryKind: PhotoScanMediaKind = .photo
    @State private var selection: [PhotosPickerItem] = []
    @State private var previewItem: PhotoScanMedia?
    @State private var pendingRemoval: PhotoScanMedia?
    @State private var showRemoval = false
    @State private var errorKey: String?

    private var archive: PhotoScanDraftArchive { PhotoScanDraftArchive(root: files.rootURL) }
    private var store: PhotoScanDraftStore { PhotoScanDraftArchive.workspace(for: context) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                header
                if draft.kind != .video { addMedia }
                if !draft.media.isEmpty { mediaList }
                if let errorKey {
                    Label(settings.t(errorKey), systemImage: "exclamationmark.circle")
                        .font(Typography.meta)
                        .foregroundStyle(Palette.error)
                        .accessibilityIdentifier("photoscan.error")
                }
                if busy { ProgressView().accessibilityLabel(settings.t("photoscan.preparing")) }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.bottom, 24)
        }
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) {
            if !draft.media.isEmpty { draftBar }
        }
        .tint(Palette.accentText)
        .photosPicker(isPresented: $showGallery, selection: $selection,
                      maxSelectionCount: galleryKind == .video ? 1 : nil, selectionBehavior: .ordered,
                      matching: galleryKind == .video ? .videos : .images, preferredItemEncoding: .current)
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            selection = []
            let kind = galleryKind
            busy = true
            Task { await importItems(items, kind: kind) }
        }
        .sheet(isPresented: $showDestination, onDismiss: {
            if closeAfterDestination { finish() }
        }) {
            ScanDestinationSheet(
                scannerContext: context,
                isPhotoDraft: true,
                onSaveWithoutLocation: {
                    try publish(destination: nil)
                    closeAfterDestination = true
                }
            ) { request in
                try publish(destination: request)
                closeAfterDestination = true
            }
        }
        .sheet(item: $previewItem) { item in
            PhotoScanMediaPreview(item: item, url: store.url(for: item))
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera, onDismiss: cameraDidClose) {
            PhotoScanCameraView(draft: $draft, onRequestSave: { saveAfterCamera = true }) { url, kind in
                await add(url, kind: kind, captured: true)
            }
        }
        .alert(settings.t("photoscan.camera.permission"), isPresented: $showCameraSettings) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button(settings.t("photoscan.camera.settings")) { openURL(url) }
            }
            Button(settings.t("common.close"), role: .cancel) {}
        }
        #endif
        .confirmationDialog(settings.t("photoscan.remove.title"), isPresented: $showRemoval,
                            presenting: pendingRemoval) { item in
            Button(settings.t("photoscan.remove"), role: .destructive) { remove(item) }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Palette.surface, in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(settings.t("common.close"))
            .accessibilityIdentifier("photoscan.close")
            .disabled(busy)
            .alert(settings.t("photoscan.exit.title"), isPresented: $showExit) {
                if !draft.media.isEmpty {
                    Button(settings.t("photoscan.save"), action: beginSave)
                }
                Button(settings.t("photoscan.exit.discard"), role: .destructive) { finish() }
                Button(settings.t("photoscan.exit.continue"), role: .cancel) {}
            }
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, 8)
        .background(Palette.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("scan.choice.photo.title"))
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(settings.t("photoscan.description"))
                .font(Typography.body)
                .foregroundStyle(Palette.inkSecondary)
            if let location {
                Text(location).font(Typography.meta).foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private var addMedia: some View {
        VStack(spacing: 13) {
            Button(action: requestCamera) {
                captureLabel(
                    draft.kind == .photo ? "photoscan.camera.shutter" : "photoscan.camera.open",
                    icon: "camera", primary: true
                )
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("photoscan.camera")
            if draft.kind == .photo {
                Button { openGallery(.photo) } label: {
                    captureLabel("photoscan.gallery", icon: "photo.on.rectangle")
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("photoscan.gallery")
            } else {
                Menu {
                    ForEach(PhotoScanMediaKind.allCases) { kind in
                        Button(settings.t(kind == .photo ? "photoscan.gallery.photos" : "photoscan.gallery.video")) {
                            openGallery(kind)
                        }
                        .accessibilityIdentifier("photoscan.gallery.\(kind.rawValue)")
                    }
                } label: {
                    captureLabel("photoscan.gallery", icon: "photo.on.rectangle")
                }
                .accessibilityIdentifier("photoscan.gallery")
            }
        }
        .disabled(busy)
    }

    private func captureLabel(_ key: String, icon: String, primary: Bool = false) -> some View {
        Label(settings.t(key), systemImage: icon)
            .font(Typography.button)
            .multilineTextAlignment(.center)
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
            .background(primary ? Palette.accent : Palette.card, in: .rect(cornerRadius: Radius.card))
    }

    private var mediaList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.kind == .video ? settings.t("photoscan.kind.video") : settings.t("photoscan.count", draft.media.count))
                .font(Typography.cardTitle)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                ForEach(draft.media) { item in
                    Button { previewItem = item } label: {
                        PhotoScanThumbnail(url: store.url(for: item), kind: item.kind)
                            .frame(height: 112)
                            .frame(maxWidth: .infinity)
                            .background(Palette.surface)
                            .clipShape(.rect(cornerRadius: Radius.small))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(settings.t(item.kind.titleKey))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            pendingRemoval = item
                            showRemoval = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Palette.onGraphite)
                                .frame(width: 36, height: 36)
                                .background(Palette.graphite, in: .circle)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(settings.t("photoscan.remove"))
                    }
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .disabled(busy)
    }

    private var draftBar: some View {
        Button(action: beginSave) {
            captureLabel("photoscan.save", icon: "folder", primary: true)
        }
        .buttonStyle(.pressable)
        .disabled(busy)
        .accessibilityIdentifier("photoscan.save")
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, 8)
        .background(Palette.background)
    }

    private var location: String? {
        PhotoScanLocation.label(for: draft, context: context, settings: settings) { id in
            try? ProjectRepository(context: modelContext, files: files).project(id: id)
        }
    }

    private func requestClose() {
        if !draft.media.isEmpty { showExit = true }
        else { finish() }
    }

    private func finish() {
        store.discardWorkingCopy()
        dismiss()
    }

    private func beginSave() {
        guard !draft.media.isEmpty else { return }
        closeAfterDestination = false
        showDestination = true
    }

    private func cameraDidClose() {
        guard saveAfterCamera else { return }
        saveAfterCamera = false
        beginSave()
    }

    private func publish(destination: ScanSaveRequest?) throws {
        var proposed = draft
        proposed.destination = destination
        try archive.save(proposed, context: context, workspace: store)
        errorKey = nil
    }

    private func openGallery(_ kind: PhotoScanMediaKind) {
        galleryKind = kind
        errorKey = nil
        showGallery = true
    }

    private func requestCamera() {
        #if os(iOS)
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            errorKey = "photoscan.camera.unavailable"
            return
        }
        busy = true
        errorKey = nil
        Task {
            defer { busy = false }
            let permission = SystemCameraAuthorization()
            switch permission.status {
            case .authorized: showCamera = true
            case .notDetermined:
                showCamera = await permission.requestAccess()
                showCameraSettings = !showCamera
            default: showCameraSettings = true
            }
        }
        #else
        errorKey = "photoscan.camera.unavailable"
        #endif
    }

    private func importItems(_ items: [PhotosPickerItem], kind: PhotoScanMediaKind) async {
        defer { busy = false }
        var firstError: String?
        for item in items {
            do {
                guard let imported = try await item.loadTransferable(type: PhotoScanImport.self) else {
                    throw PhotoScanDraftError.unreadableMedia
                }
                defer { try? FileManager.default.removeItem(at: imported.url) }
                guard imported.kind == kind else { throw PhotoScanDraftError.incompatibleMedia }
                if await !add(imported.url, kind: kind, captured: false) {
                    firstError = firstError ?? errorKey
                }
            } catch {
                firstError = firstError ?? "photoscan.importError"
            }
        }
        errorKey = firstError
    }

    private func add(_ url: URL, kind: PhotoScanMediaKind, captured: Bool) async -> Bool {
        guard draft.accepts(kind) else { errorKey = "photoscan.incompatible"; return false }
        let prepared = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString).appendingPathExtension(kind.fileExtension)
        defer { try? FileManager.default.removeItem(at: prepared) }
        do {
            if kind == .photo {
                try await Task.detached(priority: .userInitiated) {
                    try PhotoScanMediaPreparation.photo(from: url, to: prepared)
                }.value
            } else {
                try await PhotoScanMediaPreparation.video(from: url, to: prepared, captured: captured)
            }
            draft.media = try store.append(from: prepared, kind: kind).media
            errorKey = nil
            return true
        } catch PhotoScanDraftError.videoTooLong {
            errorKey = "photoscan.video.tooLong"
        } catch {
            errorKey = "photoscan.importError"
        }
        return false
    }

    private func remove(_ item: PhotoScanMedia) {
        do {
            draft.media = try store.remove(item).media
            errorKey = nil
        } catch { errorKey = "photoscan.importError" }
        self.pendingRemoval = nil
    }
}
