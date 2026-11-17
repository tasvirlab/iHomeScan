import SwiftUI

struct ParametricPlanInspectorScreen: View {
    let scan: SavedScan
    let floorPlan: FloorPlan

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fileStorage) private var files
    @State private var session: GeometryRevisionSession?
    @State private var selectedWallID: UUID?
    @State private var input = ""
    @State private var anchor: WallLengthAnchorStrategy = .keepStart
    @State private var source: GeometrySourceKind = .manualEntered
    @State private var loadFailed = false
    @State private var saveError = false
    @State private var hasUnsavedChanges = false
    @State private var showsDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    PrecisionEditorContent(
                        session: session,
                        selectedWallID: $selectedWallID,
                        input: $input,
                        anchor: $anchor,
                        source: $source,
                        onApply: applyPreview,
                        onCancel: cancelPreview,
                        onUndo: undo,
                        onRedo: redo,
                        hasUnsavedChanges: hasUnsavedChanges
                    )
                } else if loadFailed {
                    ContentUnavailableView(
                        settings.t("precision.editor.error.title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(settings.t("precision.editor.error.body"))
                    )
                } else {
                    ProgressView(settings.t("scan.viewer.loading"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .navigationTitle(settings.t("precision.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(settings.t("common.save")) { save() }
                        .disabled(!hasUnsavedChanges)
                        .accessibilityIdentifier("precision.save")
                    Button(settings.t("common.done")) { requestDismiss() }
                        .accessibilityIdentifier("precision.done")
                }
            }
        }
        .task(id: scan.id) { loadPlan() }
        .task(id: PreviewRequest(input: input, wallID: selectedWallID, anchor: anchor, source: source)) {
            guard session != nil else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            updatePreview()
        }
        .onChange(of: selectedWallID) { _, _ in resetInput() }
        .alert(settings.t("precision.editor.saveError.title"), isPresented: $saveError) {
            Button(settings.t("common.ok"), role: .cancel) {}
        } message: {
            Text(settings.t("precision.editor.saveError.body"))
        }
        .confirmationDialog(settings.t("precision.editor.unsaved.title"), isPresented: $showsDiscardConfirmation) {
            Button(settings.t("precision.editor.unsaved.save")) { saveAndDismiss() }
            Button(settings.t("precision.editor.unsaved.discard"), role: .destructive) { dismiss() }
            Button(settings.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("precision.editor.unsaved.body"))
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    private var repository: ParametricPlanRepository { ParametricPlanRepository(files: files) }

    private func loadPlan() {
        do {
            let document = try repository.loadPrecisionDocument(scan: scan, floorPlan: floorPlan)
            session = GeometryRevisionSession(document: document)
            selectedWallID = nil
            resetInput()
        } catch {
            loadFailed = true
        }
    }

    private func resetInput() {
        guard let plan = session?.document.currentPlan,
              let wallID = selectedWallID,
              let wall = plan.wall(id: wallID) else {
            input = ""
            return
        }
        session?.cancelPreview()
        input = settings.editableLength(wall.length(in: plan))
    }

    private func updatePreview() {
        guard var working = session, let wallID = selectedWallID,
              case .success(let parsed) = settings.parseLength(input), let target = parsed else {
            session?.cancelPreview()
            return
        }
        let status: GeometryVerificationStatus = source == .laserVerified ? .verified : .unverified
        let command = SetWallLengthCommand(
            id: UUID(),
            wallID: wallID,
            targetLength: target,
            anchor: anchor,
            provenance: .init(source: source, verificationStatus: status, timestamp: Date(), uncertainty: nil),
            createdAt: Date()
        )
        _ = working.propose(command)
        session = working
    }

    private func applyPreview() {
        guard var candidate = session, candidate.applyPreview() != nil else { return }
        session = candidate
        hasUnsavedChanges = true
        resetInput()
    }

    private func cancelPreview() {
        session?.cancelPreview()
        resetInput()
    }

    private func undo() {
        guard var candidate = session, candidate.undo() else { return }
        session = candidate
        hasUnsavedChanges = true
        resetInput()
    }

    private func redo() {
        guard var candidate = session, candidate.redo() else { return }
        session = candidate
        hasUnsavedChanges = true
        resetInput()
    }

    private func save() {
        guard let session else { return }
        persist(session)
    }

    private func requestDismiss() {
        if hasUnsavedChanges { showsDiscardConfirmation = true } else { dismiss() }
    }

    private func saveAndDismiss() {
        guard let session else { return }
        do {
            try repository.savePrecisionDocument(session.document, scan: scan)
            hasUnsavedChanges = false
            dismiss()
        } catch { saveError = true }
    }

    private func persist(_ candidate: GeometryRevisionSession) {
        do {
            try repository.savePrecisionDocument(candidate.document, scan: scan)
            session = candidate
            hasUnsavedChanges = false
            resetInput()
        } catch {
            saveError = true
        }
    }
}

private struct PreviewRequest: Equatable {
    let input: String
    let wallID: UUID?
    let anchor: WallLengthAnchorStrategy
    let source: GeometrySourceKind
}

private struct PrecisionEditorContent: View {
    let session: GeometryRevisionSession
    @Binding var selectedWallID: UUID?
    @Binding var input: String
    @Binding var anchor: WallLengthAnchorStrategy
    @Binding var source: GeometrySourceKind
    let onApply: () -> Void
    let onCancel: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let hasUnsavedChanges: Bool

    var body: some View {
        VStack(spacing: 0) {
            if session.displayedPlan.completeness != .complete {
                ParametricIncompleteBanner()
                    .padding(.horizontal, Spacing.screenEdge)
                    .padding(.vertical, 8)
            }
            RevisionToolbar(
                canUndo: session.canUndo,
                canRedo: session.canRedo,
                onUndo: onUndo,
                onRedo: onRedo,
                hasUnsavedChanges: hasUnsavedChanges
            )
            ParametricWallCanvas(
                plan: session.displayedPlan,
                committedPlan: session.document.currentPlan,
                selectedWallID: $selectedWallID,
                anchor: anchor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.planBackground)
            .clipShape(.rect(cornerRadius: Radius.large))
            .overlay(RoundedRectangle(cornerRadius: Radius.large).strokeBorder(Palette.line, lineWidth: 0.5))
            .padding(.horizontal, 12)

            if let id = selectedWallID, let wall = session.displayedPlan.wall(id: id) {
                WallDimensionInspector(
                    wall: wall,
                    plan: session.displayedPlan,
                    input: $input,
                    anchor: $anchor,
                    source: $source,
                    conflicts: session.conflicts,
                    hasPreview: session.preview != nil,
                    onApply: onApply,
                    onCancel: onCancel,
                    onDeselect: { selectedWallID = nil }
                )
                .padding(12)
            } else {
                SelectWallPrompt()
            }
        }
    }
}

private struct ParametricIncompleteBanner: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.accentText)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("precision.editor.incomplete.title"))
                    .font(Typography.rowTitle)
                    .foregroundStyle(Palette.ink)
                Text(settings.t("precision.editor.incomplete.body"))
                    .font(Typography.meta)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.accentTint, in: .rect(cornerRadius: Radius.medium))
    }
}

private struct RevisionToolbar: View {
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let hasUnsavedChanges: Bool
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUndo) {
                Label(settings.t("precision.editor.undo"), systemImage: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            Button(action: onRedo) {
                Label(settings.t("precision.editor.redo"), systemImage: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            Spacer()
            if hasUnsavedChanges {
                Label(settings.t("precision.editor.unsaved.status"), systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Palette.accentText)
                    .accessibilityIdentifier("precision.unsavedStatus")
            }
            Text(settings.t("precision.editor.original3D"))
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSecondary)
        }
        .font(Typography.control)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct WallDimensionInspector: View {
    let wall: ParametricWall
    let plan: ParametricFloorPlan
    @Binding var input: String
    @Binding var anchor: WallLengthAnchorStrategy
    @Binding var source: GeometrySourceKind
    let conflicts: [ConstraintConflict]
    let hasPreview: Bool
    let onApply: () -> Void
    let onCancel: () -> Void
    let onDeselect: () -> Void
    @Environment(AppSettings.self) private var settings

    private var currentLength: Double? {
        plan.wall(id: wall.id)?.length(in: plan)
    }

    private var inputIsValid: Bool {
        if case .success(let value) = settings.parseLength(input) { return value != nil }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(settings.t("precision.editor.wallDetails"))
                    .font(Typography.cardTitle)
                Spacer()
                Button(action: onDeselect) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("precision.editor.deselect"))
                .accessibilityIdentifier("precision.deselect")
                Text(currentLength.map(settings.length) ?? "—")
                    .font(Typography.control.monospacedDigit())
                    .foregroundStyle(Palette.accentText)
            }
            HStack(spacing: 8) {
                TextField(settings.t("precision.editor.dimension"), text: $input)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("precision.dimensionInput")
                Text(settings.lengthUnitSymbol)
                    .font(Typography.control)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if !input.isEmpty && !inputIsValid {
                Label(settings.t("precision.editor.invalidMeasurement"), systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.error)
            }
            Picker(settings.t("precision.editor.anchor"), selection: $anchor) {
                Text(settings.t("precision.anchor.start")).tag(WallLengthAnchorStrategy.keepStart)
                Text(settings.t("precision.anchor.end")).tag(WallLengthAnchorStrategy.keepEnd)
            }
            .pickerStyle(.segmented)
            Picker(settings.t("precision.editor.source"), selection: $source) {
                Text(settings.t("precision.source.manual")).tag(GeometrySourceKind.manualEntered)
                Text(settings.t("precision.source.laserVerified")).tag(GeometrySourceKind.laserVerified)
            }
            .pickerStyle(.segmented)
            if !conflicts.isEmpty {
                Label(settings.t("precision.editor.conflict"), systemImage: "exclamationmark.octagon.fill")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.error)
            }
            ViewThatFits {
                HStack { actionButtons }
                VStack { actionButtons }
            }
        }
        .padding(14)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.large))
        .overlay(RoundedRectangle(cornerRadius: Radius.large).strokeBorder(Palette.line, lineWidth: 0.5))
    }

    private var actionButtons: some View {
        Group {
            Button(settings.t("common.cancel"), action: onCancel)
                .buttonStyle(.bordered)
            Button(settings.t("precision.editor.apply"), action: onApply)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(!hasPreview || !conflicts.isEmpty)
                .accessibilityIdentifier("precision.apply")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SelectWallPrompt: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Text(settings.t("precision.editor.selectWall"))
            .font(Typography.body)
            .foregroundStyle(Palette.inkSecondary)
            .padding()
    }
}

private struct ParametricWallCanvas: View {
    let plan: ParametricFloorPlan
    let committedPlan: ParametricFloorPlan
    @Binding var selectedWallID: UUID?
    let anchor: WallLengthAnchorStrategy
    @Environment(AppSettings.self) private var settings
    @State private var zoom = 1.0
    @State private var lastZoom = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    private var vertexMap: [UUID: PlanVertex] {
        Dictionary(uniqueKeysWithValues: plan.vertices.map { ($0.id, $0) })
    }

    private var affectedWallIDs: Set<UUID> {
        Set(plan.walls.compactMap { wall in
            guard let current = wall.length(in: plan),
                  let previous = committedPlan.wall(id: wall.id)?.length(in: committedPlan),
                  abs(current - previous) > 0.000_1 else { return nil }
            return wall.id
        })
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let transform = drawingTransform(in: size)
                drawGrid(context: &context, size: size)
                if plan != committedPlan {
                    let committedVertices = Dictionary(uniqueKeysWithValues: committedPlan.vertices.map { ($0.id, $0) })
                    for wall in committedPlan.walls {
                        guard let start = committedVertices[wall.startVertexID]?.position,
                              let end = committedVertices[wall.endVertexID]?.position else { continue }
                        var original = Path()
                        original.move(to: CGPoint(x: start.x, y: start.y).applying(transform))
                        original.addLine(to: CGPoint(x: end.x, y: end.y).applying(transform))
                        context.stroke(original, with: .color(Palette.inkTertiary.opacity(0.45)), style: .init(lineWidth: 2, dash: [5, 4]))
                    }
                }
                for wall in plan.walls {
                    guard let segment = segment(for: wall, transform: transform) else { continue }
                    var path = Path()
                    path.move(to: segment.start)
                    path.addLine(to: segment.end)
                    let selected = wall.id == selectedWallID
                    let affected = affectedWallIDs.contains(wall.id)
                    context.stroke(
                        path,
                        with: .color(selected ? Palette.accent : (affected ? Palette.accentText : Palette.wall)),
                        style: StrokeStyle(lineWidth: selected ? 8 : 5, lineCap: .square, lineJoin: .miter)
                    )
                    if selected, let length = wall.length(in: plan) {
                        let midpoint = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2 - 18)
                        context.draw(Text(settings.length(length)).font(Typography.meta).foregroundStyle(Palette.ink), at: midpoint)
                        let fixed = anchor == .keepStart ? segment.start : segment.end
                        context.fill(Path(ellipseIn: CGRect(x: fixed.x - 7, y: fixed.y - 7, width: 14, height: 14)), with: .color(Palette.accent))
                        context.stroke(Path(ellipseIn: CGRect(x: fixed.x - 11, y: fixed.y - 11, width: 22, height: 22)), with: .color(Palette.accentText), lineWidth: 2)
                    }
                }
            }
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { selectWall(at: $0, in: proxy.size) }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { zoom = min(max(lastZoom * $0.magnification, 0.75), 6) }
                    .onEnded { _ in lastZoom = zoom }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged {
                        offset = .init(
                            width: lastOffset.width + $0.translation.width,
                            height: lastOffset.height + $0.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
        }
        .accessibilityLabel(settings.t("precision.editor.canvas"))
        .accessibilityIdentifier("precision.canvas")
    }

    private func selectWall(at point: CGPoint, in size: CGSize) {
        let transform = drawingTransform(in: size)
        let targets = plan.walls.compactMap { wall -> PrecisionWallHitTarget? in
            guard let segment = segment(for: wall, transform: transform) else { return nil }
            return PrecisionWallHitTarget(wallID: wall.id, start: segment.start, end: segment.end)
        }
        selectedWallID = PrecisionWallHitTesting.selectedWall(at: point, targets: targets)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 28
        var grid = Path()
        var x = offset.width.truncatingRemainder(dividingBy: spacing)
        while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
        var y = offset.height.truncatingRemainder(dividingBy: spacing)
        while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
        context.stroke(grid, with: .color(Palette.planGrid.opacity(0.55)), lineWidth: 0.5)
    }

    private func drawingTransform(in size: CGSize) -> CGAffineTransform {
        let points = plan.vertices.map(\.position).filter(\.isFinite)
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return .identity }
        let width = max(maxX - minX, 0.1)
        let height = max(maxY - minY, 0.1)
        let fit = min(max(size.width - 56, 1) / width, max(size.height - 56, 1) / height)
        return CGAffineTransform.identity
            .translatedBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
            .scaledBy(x: fit * zoom, y: fit * zoom)
            .translatedBy(x: -(minX + maxX) / 2, y: -(minY + maxY) / 2)
    }

    private func segment(for wall: ParametricWall, transform: CGAffineTransform) -> (start: CGPoint, end: CGPoint)? {
        guard let start = vertexMap[wall.startVertexID]?.position,
              let end = vertexMap[wall.endVertexID]?.position else { return nil }
        return (
            CGPoint(x: start.x, y: start.y).applying(transform),
            CGPoint(x: end.x, y: end.y).applying(transform)
        )
    }

}
