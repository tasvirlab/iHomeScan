import SwiftUI

/// Interactive floor plan: drag to pan, pinch or use the buttons to zoom, tap a room to select it.
struct FloorPlanViewer: View {
    /// Plan geometry in meters.
    let plan: FloorPlan
    var labels: [String: PlanRoomLabel] = [:]
    @Binding var selectedRoomID: String?
    var precisionPlan: ParametricFloorPlan?
    @Binding var selectedPrecisionWallID: UUID?
    var onPrecisionWallSelected: ((UUID) -> Void)?

    init(
        plan: FloorPlan,
        labels: [String: PlanRoomLabel] = [:],
        selectedRoomID: Binding<String?>,
        precisionPlan: ParametricFloorPlan? = nil,
        selectedPrecisionWallID: Binding<UUID?> = .constant(nil),
        onPrecisionWallSelected: ((UUID) -> Void)? = nil
    ) {
        self.plan = plan
        self.labels = labels
        _selectedRoomID = selectedRoomID
        self.precisionPlan = precisionPlan
        _selectedPrecisionWallID = selectedPrecisionWallID
        self.onPrecisionWallSelected = onPrecisionWallSelected
    }

    @Environment(AppSettings.self) private var settings

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let zoomRange: ClosedRange<CGFloat> = 0.6...3
    /// Keeps the fitted plan clear of the zoom controls on the trailing edge.
    private let planInsets = EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 52)

    private var effectiveZoom: CGFloat { clampedZoom(zoom * pinch) }
    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
    }
    private var alignmentRotation: CGFloat {
        FloorPlanAlignmentEngine.alignment(for: plan).rotation
    }

    var body: some View {
        GeometryReader { proxy in
            FloorPlanCanvas(
                plan: plan,
                style: .draft,
                labels: labels,
                selectedRoomID: selectedRoomID,
                zoom: effectiveZoom,
                offset: effectiveOffset,
                rotation: alignmentRotation,
                precisionPlan: precisionPlan,
                selectedPrecisionWallID: selectedPrecisionWallID,
                contentInsets: planInsets
            )
            .contentShape(.rect)
            .gesture(panGesture.simultaneously(with: zoomGesture))
            .onTapGesture(coordinateSpace: .local) { location in
                selectRoom(at: location, in: proxy.size)
            }
        }
        .overlay(alignment: .bottomLeading) { unitBadge }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(settings.t("plan.accessibility"))
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = clampedZoom(zoom * value.magnification) }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private func selectRoom(at location: CGPoint, in size: CGSize) {
        let transform = FloorPlanCanvas.transform(for: plan, in: size, insets: planInsets,
                                                  zoom: effectiveZoom, offset: effectiveOffset,
                                                  rotation: alignmentRotation)
        if let wallID = precisionWall(at: location, transform: transform, size: size) {
            selectedPrecisionWallID = wallID
            onPrecisionWallSelected?(wallID)
            return
        }
        let point = location.applying(transform.inverted())
        let room = plan.rooms.first { $0.rect.contains(point) }
        withAnimation(.easeOut(duration: 0.2)) {
            selectedRoomID = room?.id == selectedRoomID ? nil : room?.id
        }
    }

    private func precisionWall(at location: CGPoint, transform: CGAffineTransform, size: CGSize) -> UUID? {
        guard let precisionPlan else { return nil }
        let dimensions = FloorPlanCanvas.precisionDimensions(precisionPlan)
        let annotations = FloorPlanDimensionLayoutEngine.layout(
            dimensions: dimensions, transform: transform,
            canvasBounds: CGRect(origin: .zero, size: size),
            planCenter: CGPoint(x: plan.bounds.midX, y: plan.bounds.midY),
            textForValue: settings.lengthValue
        )
        if let annotation = annotations.first(where: { $0.labelBounds.insetBy(dx: -8, dy: -8).contains(location) }),
           annotation.sourceIndex < precisionPlan.walls.count {
            return precisionPlan.walls[annotation.sourceIndex].id
        }
        let vertices = Dictionary(uniqueKeysWithValues: precisionPlan.vertices.map { ($0.id, $0.position) })
        let targets = precisionPlan.walls.compactMap { wall -> PrecisionWallHitTarget? in
            guard let start = vertices[wall.startVertexID], let end = vertices[wall.endVertexID] else { return nil }
            return PrecisionWallHitTarget(
                wallID: wall.id,
                start: CGPoint(x: start.x, y: start.y).applying(transform),
                end: CGPoint(x: end.x, y: end.y).applying(transform)
            )
        }
        return PrecisionWallHitTesting.selectedWall(at: location, targets: targets)
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.snappy) { zoom = clampedZoom(value) }
    }

    // MARK: - Overlays

    private var unitBadge: some View {
        Text(settings.t(settings.units == .millimeters ? "plan.units.mm" : "plan.units.m"))
            .font(.caption.monospaced().weight(.medium))
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
            .padding(12)
    }

    private var zoomControls: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                controlButton("plus", labelKey: "plan.zoomIn") { setZoom(zoom * 1.25) }
                Rectangle().fill(Palette.line).frame(width: 22, height: 0.5)
                controlButton("minus", labelKey: "plan.zoomOut") { setZoom(zoom / 1.25) }
            }
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))

            controlButton("arrow.down.left.and.arrow.up.right", labelKey: "plan.reset") {
                withAnimation(.snappy) {
                    zoom = 1
                    offset = .zero
                }
            }
            .background(.ultraThinMaterial, in: .circle)
            .overlay(Circle().strokeBorder(Palette.line, lineWidth: 0.5))
        }
        .padding(12)
    }

    private func controlButton(_ systemImage: String, labelKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.t(labelKey))
    }
}
