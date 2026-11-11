import SwiftUI

/// A choice of one from a few, in an ink box split into equal parts, the chosen one filled
/// with ink. Screen 03: Four seasons, Two seasons, No seasons.
struct SegmentedChoice<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let isOn = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.text(14, weight: .medium, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isOn ? Color.onInk : Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isOn ? Color.ink : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])

                if index < options.count - 1 {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        .overlay(RoundedRectangle(cornerRadius: CaroLayout.tileRadius).strokeBorder(Color.ink, lineWidth: 1))
    }
}

#Preview {
    @Previewable @State var count = SeasonCount.two
    SegmentedChoice(options: SeasonCount.allCases, selection: $count) { $0.label }
        .padding(CaroLayout.pageMargin)
        .background(Color.paper)
}
