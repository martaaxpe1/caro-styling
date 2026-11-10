import SwiftUI

/// Caro's pill buttons: 52 points high, full width.
/// Primary is filled with ink, secondary is outlined.
/// Use: `Button("Continue") { ... }.buttonStyle(.pill)` or `.buttonStyle(.pillOutlined)`.
struct PillButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caroButton)
            .foregroundStyle(filled ? Color.onInk : Color.ink)
            .frame(maxWidth: .infinity, minHeight: CaroLayout.buttonHeight)
            .background(filled ? Color.ink : Color.clear, in: Capsule())
            .overlay {
                if !filled {
                    Capsule().strokeBorder(Color.ink, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle(filled: true) }
    static var pillOutlined: PillButtonStyle { PillButtonStyle(filled: false) }
}

#Preview {
    VStack(spacing: 12) {
        Button("Continue") {}.buttonStyle(.pill)
        Button("Choose from library") {}.buttonStyle(.pillOutlined)
    }
    .padding(CaroLayout.pageMargin)
    .background(Color.paper)
}
