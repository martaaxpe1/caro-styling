import SwiftUI

/// Caro's pill buttons: 52 points high, full width.
/// Primary is filled with ink, secondary is outlined. While it cannot be pressed, either one is a
/// hairline pill with muted words: warm, readable, and clearly not ready.
/// Use: `Button("Continue") { ... }.buttonStyle(.pill)` or `.buttonStyle(.pillOutlined)`.
struct PillButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, filled: filled)
    }

    // A view of its own, so it can read whether the button is enabled.
    private struct Pill: View {
        let configuration: Configuration
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.caroButton)
                .foregroundStyle(textColour)
                .frame(maxWidth: .infinity, minHeight: CaroLayout.buttonHeight)
                .background(fillColour, in: Capsule())
                .overlay {
                    if !filled && isEnabled {
                        Capsule().strokeBorder(Color.ink, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
                // Paper behind the pill, so it stays solid while pressed and nothing shows through it.
                .background(Color.paper, in: Capsule())
        }

        private var textColour: Color {
            if !isEnabled { return .muted }
            return filled ? .onInk : .ink
        }

        private var fillColour: Color {
            if !isEnabled { return .hairline }
            return filled ? .ink : .clear
        }
    }
}

extension View {
    /// The pill button pinned to the bottom of a screen: page margins, and a strip of paper
    /// behind it, so text scrolling underneath never shows through, also with the keyboard up.
    /// Use inside `.safeAreaInset(edge: .bottom) { Button(...).buttonStyle(.pill).bottomButtonBar() }`.
    func bottomButtonBar() -> some View {
        self
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.paper)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle(filled: true) }
    static var pillOutlined: PillButtonStyle { PillButtonStyle(filled: false) }
}

#Preview {
    VStack(spacing: 12) {
        Button("Continue") {}.buttonStyle(.pill)
        Button("Continue") {}.buttonStyle(.pill).disabled(true)
        Button("Choose from library") {}.buttonStyle(.pillOutlined)
    }
    .padding(CaroLayout.pageMargin)
    .background(Color.paper)
}
