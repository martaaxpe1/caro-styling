import SwiftUI

/// A chip that can be on or off, 32 points high: ink when chosen, an outline when not.
/// Screen 04's sections: Women's, Men's, Unisex.
struct Chip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.text(14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: CaroLayout.chipHeight)
                .background(isOn ? Color.ink : Color.clear, in: Capsule())
                .overlay {
                    if !isOn {
                        Capsule().strokeBorder(Color.outline, lineWidth: 1)
                    }
                }
                // A taller area to tap than the chip itself.
                .frame(minHeight: CaroLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    HStack(spacing: 8) {
        Chip(title: "Women's", isOn: true) {}
        Chip(title: "Men's", isOn: false) {}
        Chip(title: "Unisex", isOn: false) {}
    }
    .padding(CaroLayout.pageMargin)
    .background(Color.paper)
}
