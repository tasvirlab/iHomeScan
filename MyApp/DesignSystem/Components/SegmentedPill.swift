import SwiftUI

/// Segmented control styled after the design: a recessed track with a raised card-colored thumb.
struct SegmentedPill<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value
    var height: CGFloat = 36

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(Typography.control)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Palette.ink : Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: height / 4)
                                    .fill(Palette.segmentThumb)
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.surface, in: .rect(cornerRadius: height / 3))
    }
}
