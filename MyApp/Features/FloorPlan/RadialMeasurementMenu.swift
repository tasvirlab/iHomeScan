import SwiftUI

struct RadialMeasurementMenu: View {
    let onDimension: () -> Void
    let onAdd: () -> Void
    let onProperties: () -> Void
    let onFit: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 4) {
            RadialToolButton(systemImage: "ruler", label: settings.t("precision.radial.dimension"), action: onDimension)
            RadialToolButton(systemImage: "plus", label: settings.t("precision.radial.add"), action: onAdd)
            RadialToolButton(systemImage: "slider.horizontal.3", label: settings.t("precision.radial.properties"), action: onProperties)
            RadialToolButton(systemImage: "arrow.down.left.and.arrow.up.right", label: settings.t("precision.radial.fit"), action: onFit)
            RadialToolButton(systemImage: "xmark", label: settings.t("common.close"), action: onClose)
        }
        .padding(7)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("precision.radial.menu")
    }
}

private struct RadialToolButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.surface.opacity(0.82), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
