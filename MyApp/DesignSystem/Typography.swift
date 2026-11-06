import SwiftUI

/// Type scale based on SF Pro text styles so it scales with Dynamic Type.
/// Measurements use SF Mono (`.monospaced`) as in the design.
enum Typography {
    static let screenTitle = Font.largeTitle.weight(.bold)
    static let detailTitle = Font.title2.weight(.bold)
    static let sheetTitle = Font.title2.weight(.bold)
    static let brand = Font.title3.weight(.bold)
    static let cardTitle = Font.headline
    static let rowTitle = Font.callout.weight(.semibold)
    static let gridTitle = Font.subheadline.weight(.semibold)
    static let sectionHeader = Font.subheadline.weight(.semibold)
    static let settingsHeader = Font.footnote.weight(.semibold)
    static let body = Font.subheadline
    static let meta = Font.footnote
    static let badge = Font.caption2.weight(.semibold)
    static let control = Font.subheadline.weight(.semibold)
    static let button = Font.headline
    static let measurement = Font.footnote.monospaced().weight(.medium)
    static let measurementEmphasis = Font.subheadline.monospaced().weight(.semibold)
}
