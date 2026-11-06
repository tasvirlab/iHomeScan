import SwiftUI

/// Card background with the design's soft two-layer shadow.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.card
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        content
            .background(Palette.card, in: .rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(isDark ? 0.4 : 0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(isDark ? 0.25 : 0.07), radius: 9, y: 6)
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

/// Button style that dims slightly while pressed — used for custom tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
