import SwiftUI

struct RadialMeasurementMenu: View {
    let onDimension: () -> Void
    let onAdd: () -> Void
    let onProperties: () -> Void
    let onFit: () -> Void
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            HalfMoonShape()
                .fill(.ultraThinMaterial)
                .overlay(HalfMoonShape().strokeBorder(Palette.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 14, y: 6)

            tool("ruler", label: "precision.radial.dimension", action: onDimension)
                .position(x: 28, y: 100)
            tool("plus", label: "precision.radial.add", action: onAdd)
                .position(x: 78, y: 55)
            tool("slider.horizontal.3", label: "precision.radial.properties", action: onProperties)
                .position(x: 135, y: 36)
            tool("arrow.down.left.and.arrow.up.right", label: "precision.radial.fit", action: onFit)
                .position(x: 192, y: 55)
            tool("xmark", label: "common.close", action: onClose)
                .position(x: 242, y: 100)
        }
        .frame(width: 270, height: 140)
        .contentShape(HalfMoonShape())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("precision.radial.menu")
    }

    private func tool(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        RadialToolButton(systemImage: systemImage, label: settings.t(label), action: action)
    }
}

private struct HalfMoonShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.maxY))
        path.addArc(
            center: CGPoint(x: insetRect.midX, y: insetRect.maxY),
            radius: insetRect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> HalfMoonShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct RadialToolButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.surface.opacity(0.9), in: .circle)
                .overlay(Circle().strokeBorder(Palette.line.opacity(0.7), lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
