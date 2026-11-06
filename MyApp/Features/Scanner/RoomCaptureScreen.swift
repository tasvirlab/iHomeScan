import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Full-screen live RoomPlan capture: camera with Apple's native coaching, Cancel and Finish,
/// then either an in-memory result summary or a localized failure.
struct RoomCaptureScreen: View {
    let context: ScannerContext

    @Environment(AppModel.self) private var appModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var model: RoomScanSessionModel
    @State private var confirmsCancel = false
    @State private var confirmsDiscard = false
    @State private var showsSaveSheet = false
    @State private var savedAssociation: SavedScanAssociation?

    init(context: ScannerContext, model: RoomScanSessionModel? = nil) {
        self.context = context
        _model = State(initialValue: model ?? Self.makeLiveModel())
    }

    private static func makeLiveModel() -> RoomScanSessionModel {
        #if canImport(RoomPlan) && canImport(UIKit)
        RoomScanSessionModel(controller: RoomPlanCaptureController())
        #else
        RoomScanSessionModel(controller: UnavailableCaptureController())
        #endif
    }

    var body: some View {
        content
            .task { model.begin() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.appDidEnterBackground() }
            }
            .onChange(of: model.state) { _, state in
                setIdleTimerDisabled(state.isActive)
                if state == .cancelled { dismiss() }
            }
            .onDisappear {
                model.tearDown()
                setIdleTimerDisabled(false)
            }
            .animation(.easeInOut(duration: 0.2), value: model.state)
            .sheet(isPresented: $showsSaveSheet) {
                if let output = model.output {
                    ScanSaveSheet(output: output, scannerContext: context) { association in
                        savedAssociation = association
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .preparing, .scanning, .processing, .cancelled:
            captureLayer
        case .completed(let summary):
            if let output = model.output {
                ScanResultView(
                    summary: summary,
                    completeness: output.floorPlan.roomPlanMetadata?.completeness ?? .incomplete,
                    floorArea: output.floorPlan.roomPlanMetadata?.floorArea,
                    savedAssociation: savedAssociation,
                    onSave: { showsSaveSheet = true },
                    onScanAgain: {
                        savedAssociation = nil
                        model.scanAgain()
                    },
                    onDiscard: {
                        if savedAssociation == nil {
                            confirmsDiscard = true
                        } else {
                            dismiss()
                        }
                    },
                    onOpenProject: openSavedProject
                )
                .confirmationDialog(
                    settings.t("scan.discard.title"),
                    isPresented: $confirmsDiscard,
                    titleVisibility: .visible
                ) {
                    Button(settings.t("scan.discard.action"), role: .destructive) {
                        model.discardResult()
                        dismiss()
                    }
                    Button(settings.t("common.cancel"), role: .cancel) {}
                } message: {
                    Text(settings.t("scan.discard.message"))
                }
            } else {
                ScanFailureView(
                    failure: .processingFailed,
                    onRetry: { model.scanAgain() },
                    onOpenSettings: openAppSettings,
                    onClose: { dismiss() }
                )
            }
        case .failed(let failure):
            ScanFailureView(
                failure: failure,
                onRetry: { model.scanAgain() },
                onOpenSettings: openAppSettings,
                onClose: { dismiss() }
            )
        }
    }

    // MARK: - Live capture

    private var captureLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if canImport(UIKit)
            if let preview = model.controller.previewView {
                RoomCapturePreviewHost(view: preview)
                    .ignoresSafeArea()
                    .accessibilityLabel(settings.t("scan.camera.accessibility"))
            }
            #endif

            VStack {
                HStack {
                    Button { requestCancel() } label: {
                        Text(settings.t("common.cancel"))
                            .font(Typography.control)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(.ultraThinMaterial, in: .capsule)
                            .environment(\.colorScheme, .dark)
                    }
                    .buttonStyle(.pressable)
                    .disabled(!model.state.isActive)
                    Spacer()
                }
                .padding(.horizontal, Spacing.screenEdge)
                .padding(.top, 8)

                Spacer()

                if model.state == .preparing || model.state == .idle {
                    statusPill(settings.t("scan.preparing"))
                }

                Button { model.finish() } label: {
                    Label(settings.t("scan.finish"), systemImage: "checkmark")
                        .font(Typography.button)
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 28)
                        .frame(minHeight: 56)
                        .background(Palette.accent, in: .capsule)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                }
                .buttonStyle(.pressable)
                .disabled(model.state != .scanning)
                .opacity(model.state == .scanning ? 1 : 0.4)
                .padding(.bottom, 24)
                .accessibilityHint(settings.t("scan.finish.hint"))
            }

            if model.state == .processing {
                processingOverlay
            }
        }
        .confirmationDialog(settings.t("scan.cancel.title"), isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button(settings.t("scan.cancel.action"), role: .destructive) { model.cancel() }
            Button(settings.t("scan.continue"), role: .cancel) {}
        } message: {
            Text(settings.t("scan.cancel.message"))
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.onGraphite)
                Text(settings.t("scan.processing.title"))
                    .font(.headline)
                    .foregroundStyle(Palette.onGraphite)
                Text(settings.t("scan.processing.body"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.onGraphiteSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Palette.graphite, in: .rect(cornerRadius: Radius.large))
            .accessibilityElement(children: .combine)
        }
    }

    private func statusPill(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: .capsule)
        .environment(\.colorScheme, .dark)
        .padding(.bottom, 16)
    }

    /// Cancelling a running capture discards it, so ask first; while starting, cancel directly.
    private func requestCancel() {
        if model.state == .preparing || model.state == .idle {
            model.cancel()
            if model.state != .cancelled { dismiss() }
        } else {
            confirmsCancel = true
        }
    }

    private func openSavedProject() {
        guard let savedAssociation else { return }
        appModel.selectedTab = .projects
        appModel.path.removeAll()
        appModel.path.append(.project(savedAssociation.projectID))
        appModel.scanner = nil
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }

    /// Keep the screen awake while the camera is capturing.
    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

#if canImport(UIKit)
/// Hosts a UIKit camera view (RoomPlan's `RoomCaptureView`) in SwiftUI.
private struct RoomCapturePreviewHost: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif

#if !(canImport(RoomPlan) && canImport(UIKit))
/// Used on platforms without RoomPlan; `begin()` fails before this is ever started.
private final class UnavailableCaptureController: RoomCaptureControlling {
    var onEvent: ((RoomCaptureEvent) -> Void)?
    var previewView: UIView? { nil }
    func start() { onEvent?(.failed(.unsupportedDevice)) }
    func finish() {}
    func cancel() {}
    func invalidate() { onEvent = nil }
}
#endif
