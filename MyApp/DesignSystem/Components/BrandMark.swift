import SwiftUI

/// The iHomeScan logo: scan-frame corners with an accent line, on a graphite tile.
struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(Palette.graphite)
            .frame(width: size, height: size)
            .overlay {
                ScanFrameGlyph(showsCenterLine: true)
                    .frame(width: size * 0.66, height: size * 0.66)
            }
            .accessibilityHidden(true)
    }
}

/// Four scan-frame corners (and optionally a center line) drawn in a 24-point grid.
struct ScanFrameGlyph: View {
    var showsCenterLine = false
    var cornerColor: Color = Palette.brandMarkStroke
    var lineColor: Color = Palette.brandMarkAccent
    var lineWidth: CGFloat = 2.2

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            var corners = Path()
            corners.addLines([CGPoint(x: 8, y: 4), CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 8)])
            corners.addLines([CGPoint(x: 16, y: 4), CGPoint(x: 20, y: 4), CGPoint(x: 20, y: 8)])
            corners.addLines([CGPoint(x: 4, y: 16), CGPoint(x: 4, y: 20), CGPoint(x: 8, y: 20)])
            corners.addLines([CGPoint(x: 20, y: 16), CGPoint(x: 20, y: 20), CGPoint(x: 16, y: 20)])
            context.stroke(corners, with: .color(cornerColor), style: style)

            if showsCenterLine {
                var line = Path()
                line.addLines([CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12)])
                context.stroke(line, with: .color(lineColor), style: style)
            }
        }
    }
}

/// Placeholder avatar shown until a profile photo exists.
struct AvatarView: View {
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(Palette.surface)
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.6)
                    .foregroundStyle(Palette.inkTertiary)
                    .offset(y: -size * 0.12)
            }
            .clipShape(.circle)
    }
}
