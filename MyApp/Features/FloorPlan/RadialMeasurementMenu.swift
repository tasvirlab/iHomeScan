import SwiftUI

struct RadialMeasurementMenu: View {
    let onDimension: () -> Void
    let onProperties: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            tool("ruler", label: "precision.radial.dimension", action: onDimension)
                .position(x: 34, y: 82)
            tool("slider.horizontal.3", label: "precision.radial.properties", action: onProperties)
                .position(x: 88, y: 42)
            tool("xmark", label: "common.close", action: onClose)
                .position(x: 142, y: 82)
        }
        .frame(width: 176, height: 112)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("precision.radial.menu")
    }

    private func tool(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        RadialToolButton(systemImage: systemImage, label: settings.t(label), action: action)
    }
}

private struct RadialToolButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: .circle)
                .overlay(Circle().strokeBorder(Palette.line.opacity(0.75), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
