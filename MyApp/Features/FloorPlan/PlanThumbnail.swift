import SwiftUI
import SwiftData

/// Loads a floor's stored plan geometry from disk and exposes it to a view.
struct FloorPlanLoader: ViewModifier {
    let asset: LocalAsset?
    @Binding var plan: FloorPlan?
    @Binding var error: Error?

    @Environment(\.modelContext) private var context
    @Environment(\.fileStorage) private var files

    func body(content: Content) -> some View {
        content.task(id: asset?.id) {
            guard let asset else {
                plan = nil
                error = nil
                return
            }
            do {
                plan = try AssetRepository(context: context, files: files).loadPlan(asset)
                error = nil
            } catch {
                plan = nil
                self.error = error
            }
        }
    }
}

extension View {
    func loadsFloorPlan(_ asset: LocalAsset?, into plan: Binding<FloorPlan?>, error: Binding<Error?> = .constant(nil)) -> some View {
        modifier(FloorPlanLoader(asset: asset, plan: plan, error: error))
    }
}

extension Floor {
    /// Database room names and areas keyed by their plan geometry identifiers.
    var planLabels: [String: PlanRoomLabel] {
        var labels: [String: PlanRoomLabel] = [:]
        for room in rooms {
            guard let id = room.geometryIdentifier else { continue }
            labels[id] = PlanRoomLabel(name: room.name, area: room.effectiveArea)
        }
        return labels
    }
}

/// Small line drawing of a project's first scanned floor, or a scan glyph if nothing is scanned.
struct PlanThumbnail: View {
    let project: Project

    @State private var plan: FloorPlan?

    private var planAsset: LocalAsset? {
        project.sortedFloors.lazy.compactMap(\.planAsset).first
    }

    var body: some View {
        Group {
            if let plan {
                FloorPlanCanvas(plan: plan, style: .thumbnail)
            } else {
                ScanFrameGlyph(cornerColor: Palette.inkTertiary, lineWidth: 2)
                    .padding(10)
                    .frame(maxWidth: 34, maxHeight: 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.planBackground)
            }
        }
        .loadsFloorPlan(planAsset, into: $plan)
        .accessibilityHidden(true)
    }
}
