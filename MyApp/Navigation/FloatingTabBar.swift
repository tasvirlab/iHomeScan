import SwiftUI

/// Floating graphite capsule with the three tabs and the accent Scan button.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onScan: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }

            Spacer(minLength: 4)

            scanButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 64)
        .background(Palette.graphite, in: .capsule)
        // Hairline keeps the capsule distinct from the near-black ground in dark mode.
        .overlay(Capsule().strokeBorder(Palette.onGraphite.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 15, y: 12)
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.3)) { selection = tab }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 24)
                if isSelected && !dynamicTypeSize.isAccessibilitySize {
                    Text(settings.t(tab.titleKey))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .foregroundStyle(isSelected ? Palette.onGraphite : Palette.onGraphiteSecondary)
            .padding(.horizontal, 13)
            .frame(height: 48)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Palette.onGraphite.opacity(0.14))
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settings.t(tab.titleKey))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var scanButton: some View {
        Button(action: onScan) {
            // On Home the button shows its label when there is room for it
            // (e.g. "Skanerlash" in Uzbek is long); otherwise only the icon.
            if selection == .home && !dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    scanLabel(showsTitle: true)
                    scanLabel(showsTitle: false)
                }
            } else {
                scanLabel(showsTitle: false)
            }
        }
        .buttonStyle(.pressable)
        .layoutPriority(1)
        .accessibilityLabel(settings.t("action.scan"))
    }

    private func scanLabel(showsTitle: Bool) -> some View {
        HStack(spacing: 8) {
            ScanFrameGlyph(showsCenterLine: true, cornerColor: Palette.onAccent, lineColor: Palette.onAccent, lineWidth: 2.3)
                .frame(width: 24, height: 24)
            if showsTitle {
                Text(settings.t("action.scan"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(Palette.onAccent)
        .padding(.horizontal, showsTitle ? 18 : 14)
        .frame(minWidth: 52, minHeight: 52)
        .background(Palette.accent, in: .capsule)
    }
}
