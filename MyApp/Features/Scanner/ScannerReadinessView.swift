import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Entry point of the scanning workflow. Shows whether this device can scan and guides the
/// user through camera permission. The RoomPlan capture session itself arrives in Stage 2.2,
/// so the ready state never shows progress or produces scan data.
struct ScannerReadinessView: View {
    let context: ScannerContext

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.fileStorage) private var files
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model: ScannerReadinessModel
    @State private var showsCapture = false

    init(context: ScannerContext, model: ScannerReadinessModel = ScannerReadinessModel()) {
        self.context = context
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                deviceStatusCard
                if model.state == .readyToScan {
                    tipsCard
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .task { model.refresh() }
        // Returning from Settings (or any other app) may have changed camera access.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .animation(.snappy(duration: 0.25), value: model.state)
        .fullScreenCover(isPresented: $showsCapture, onDismiss: { model.refresh() }) {
            RoomCaptureScreen(context: context)
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Palette.surface, in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(settings.t("common.close"))
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, 8)
        .background(Palette.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("scanner.title"))
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let contextText {
                Text(contextText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, Spacing.titleEdge - Spacing.screenEdge)
    }

    /// "Chilonzor 9, 2-room flat · Floor 1" when the scan was started from a project.
    private var contextText: String? {
        guard let projectID = context.projectID,
              let project = try? ProjectRepository(context: modelContext, files: files).project(id: projectID)
        else { return nil }
        var parts = [project.name]
        if let floor = project.floors.first(where: { $0.id == context.floorID }) {
            parts.append(settings.floorName(floor))
        }
        return parts.joined(separator: " · ")
    }

    private var statusCard: some View {
        let content = StatusContent(state: model.state)
        return VStack(spacing: 14) {
            statusIcon(content)
                .padding(.top, 6)

            VStack(spacing: 8) {
                Text(settings.t(content.titleKey))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(settings.t(content.bodyKey))
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            if let note = content.noteKey {
                Text(settings.t(note))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Palette.surface, in: .rect(cornerRadius: Radius.small))
            }

            action(for: model.state)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    @ViewBuilder
    private func statusIcon(_ content: StatusContent) -> some View {
        ZStack {
            Circle()
                .fill(content.isPositive ? Palette.accentTint : Palette.surface)
                .frame(width: 84, height: 84)
            if model.state == .checkingDevice {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.inkSecondary)
            } else if let symbol = content.systemImage {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(content.isPositive ? Palette.accentText : Palette.inkSecondary)
            } else {
                ScanFrameGlyph(showsCenterLine: true, cornerColor: Palette.accentText,
                               lineColor: Palette.accent, lineWidth: 2.3)
                    .frame(width: 40, height: 40)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func action(for state: ScannerReadinessState) -> some View {
        switch state {
        case .cameraPermissionRequired:
            ActionButton(
                title: settings.t("scanner.permission.allow"),
                systemImage: "camera",
                isLoading: model.isRequestingAccess
            ) {
                Task { await model.requestCameraAccess() }
            }
        case .cameraPermissionDenied:
            ActionButton(title: settings.t("scanner.openSettings"), systemImage: "gear") {
                openAppSettings()
            }
        case .unexpectedError:
            ActionButton(title: settings.t("scanner.retry"), systemImage: "arrow.clockwise", kind: .secondary) {
                model.refresh()
            }
        case .readyToScan:
            ActionButton(title: settings.t("scan.start"), systemImage: "viewfinder") {
                showsCapture = true
            }
        case .unsupportedDevice, .cameraRestricted:
            ActionButton(title: settings.t("common.close"), kind: .secondary) { dismiss() }
        case .checkingDevice:
            EmptyView()
        }
    }

    /// Real device and permission facts, so the user (and testers) can see why a state was chosen.
    private var deviceStatusCard: some View {
        VStack(spacing: 0) {
            statusRow(titleKey: "scanner.status.lidar", valueKey: lidarValueKey, positive: model.isDeviceSupported == true)
            Rectangle().fill(Palette.line).frame(height: 0.5).padding(.leading, 16)
            statusRow(titleKey: "scanner.status.camera", valueKey: cameraValueKey, positive: model.state == .readyToScan)
        }
        .cardSurface()
    }

    private var lidarValueKey: String {
        switch model.isDeviceSupported {
        case .some(true): "scanner.value.supported"
        case .some(false): "scanner.value.notSupported"
        case .none: "scanner.value.checking"
        }
    }

    private var cameraValueKey: String {
        switch model.state {
        case .readyToScan: "scanner.value.allowed"
        case .cameraPermissionRequired: "scanner.value.notAsked"
        case .cameraPermissionDenied: "scanner.value.denied"
        case .cameraRestricted: "scanner.value.restricted"
        case .unsupportedDevice: "scanner.value.notNeeded"
        case .checkingDevice, .unexpectedError: "scanner.value.checking"
        }
    }

    private func statusRow(titleKey: String, valueKey: String, positive: Bool) -> some View {
        let label = Text(settings.t(titleKey))
            .font(Typography.body)
            .foregroundStyle(Palette.inkSecondary)
        let value = Text(settings.t(valueKey))
            .font(Typography.rowTitle)
            .foregroundStyle(positive ? Palette.success : Palette.ink)
        // Side by side (the label may wrap, the value stays whole); stacked at accessibility sizes.
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    label
                    value
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    value
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("scanner.tips.title"))
                .font(Typography.settingsHeader)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(["scanner.tip1", "scanner.tip2", "scanner.tip3"].enumerated()), id: \.offset) { index, key in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 26, height: 26)
                        .background(Palette.accentTint, in: .circle)
                    Text(settings.t(key))
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }
}

/// Text and icon for each readiness state.
private struct StatusContent {
    let titleKey: String
    let bodyKey: String
    var noteKey: String?
    /// nil uses the scan-frame brand glyph.
    var systemImage: String?
    var isPositive = false

    init(state: ScannerReadinessState) {
        switch state {
        case .checkingDevice:
            self.init(titleKey: "scanner.checking.title", bodyKey: "scanner.checking.body")
        case .unsupportedDevice(isSimulator: true):
            self.init(titleKey: "scanner.simulator.title", bodyKey: "scanner.simulator.body",
                      noteKey: "scanner.unsupported.note", systemImage: "desktopcomputer")
        case .unsupportedDevice(isSimulator: false):
            self.init(titleKey: "scanner.unsupported.title", bodyKey: "scanner.unsupported.body",
                      noteKey: "scanner.unsupported.note", systemImage: "iphone.slash")
        case .cameraPermissionRequired:
            self.init(titleKey: "scanner.permission.title", bodyKey: "scanner.permission.body",
                      noteKey: "scanner.permission.note", systemImage: "camera")
        case .cameraPermissionDenied:
            self.init(titleKey: "scanner.denied.title", bodyKey: "scanner.denied.body", systemImage: "camera.badge.ellipsis")
        case .cameraRestricted:
            self.init(titleKey: "scanner.restricted.title", bodyKey: "scanner.restricted.body", systemImage: "lock")
        case .readyToScan:
            self.init(titleKey: "scanner.ready.title", bodyKey: "scanner.ready.body",
                      noteKey: "scanner.ready.stageNote", systemImage: nil, isPositive: true)
        case .unexpectedError:
            self.init(titleKey: "scanner.error.title", bodyKey: "scanner.error.body", systemImage: "exclamationmark.triangle")
        }
    }

    private init(titleKey: String, bodyKey: String, noteKey: String? = nil,
                 systemImage: String? = "viewfinder", isPositive: Bool = false) {
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.noteKey = noteKey
        self.systemImage = systemImage
        self.isPositive = isPositive
    }
}
