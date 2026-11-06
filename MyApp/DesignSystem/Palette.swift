import SwiftUI

/// iHomeScan color palette (60–30–10):
/// - 60% warm neutrals — `background`, `card`, `surface`
/// - 30% graphite — tab bar, brand mark, toasts, primary text (`ink`)
/// - 10% terracotta accent — primary actions, selection, highlights
///
/// Every color has light and dark variants defined in `Assets.xcassets`.
enum Palette {
    // Neutrals
    static let background = Color(.paletteBackground)
    static let card = Color(.paletteCard)
    static let surface = Color(.paletteSurface)
    static let line = Color(.paletteLine)
    /// Raised thumb of segmented controls (lighter than `surface` in dark mode).
    static let segmentThumb = Color(.paletteSegmentThumb)

    // Graphite
    static let graphite = Color(.paletteGraphite)
    static let onGraphite = Color(.paletteOnGraphite)
    static let onGraphiteSecondary = Color(.paletteOnGraphiteSecondary)

    // Text
    static let ink = Color(.paletteInk)
    static let inkSecondary = Color(.paletteInkSecondary)
    static let inkTertiary = Color(.paletteInkTertiary)

    // Accent
    static let accent = Color(.accent)
    static let accentPressed = Color(.paletteAccentPressed)
    /// Accent tuned for text-sized content (sufficient contrast on light/dark grounds).
    static let accentText = Color(.paletteAccentText)
    static let accentTint = Color(.paletteAccentTint)
    static let onAccent = Color(.paletteOnAccent)

    // Status
    static let success = Color(.paletteSuccess)
    static let error = Color(.paletteError)

    // Floor plan
    static let planBackground = Color(.palettePlanBackground)
    static let planFloor = Color(.palettePlanFloor)
    static let planGrid = Color(.palettePlanGrid)
    static let wall = Color(.paletteWall)

    /// Brand mark colors — identical in light and dark mode.
    static let brandMarkStroke = Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEB / 255)
    static let brandMarkAccent = Color(red: 0xE5 / 255, green: 0x54 / 255, blue: 0x2F / 255)
}

/// Corner radii used across the app.
enum Radius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 15
    static let card: CGFloat = 20
    static let large: CGFloat = 22
    static let hero: CGFloat = 26
}

/// Spacing scale.
enum Spacing {
    static let screenEdge: CGFloat = 16
    static let titleEdge: CGFloat = 20
    static let grid: CGFloat = 12
}
