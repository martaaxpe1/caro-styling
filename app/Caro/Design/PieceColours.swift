import SwiftUI

/// How the fixed lists read on screen, and a swatch for each of the 21 colours (PRD section 8).
enum PieceWords {
    /// "smart casual" reads "Smart casual", "t-shirt" reads "T-shirt".
    static func title(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    /// The swatch shown next to a colour. Pale ones get an outline, so they show on paper.
    static func swatch(_ colour: String) -> Color {
        swatches[colour].map { Color(hex: $0) } ?? .outline
    }

    static func isPale(_ colour: String) -> Bool {
        ["white", "cream", "silver"].contains(colour)
    }

    private static let swatches: [String: UInt32] = [
        "black": 0x22211F,
        "white": 0xFBF9F4,
        "cream": 0xEDE3CF,
        "beige": 0xD8C7A8,
        "camel": 0xB88A5E,
        "brown": 0x5A4033,
        "grey": 0xA9A8A3,
        "navy": 0x2E3A55,
        "blue": 0x4A6FA5,
        "light blue": 0xB9CCE0,
        "green": 0x4F7A4A,
        "olive": 0x6B6B3A,
        "red": 0xB03A2E,
        "burgundy": 0x6E2232,
        "pink": 0xE8B4B8,
        "terracotta": 0xB4765F,
        "orange": 0xD9823B,
        "yellow": 0xE3C45A,
        "purple": 0x6B4E8A,
        "silver": 0xC4C4C4,
        "gold": 0xC9A54C,
    ]
}

/// A small square of a colour, as on screen 07.
struct ColourSwatch: View {
    let colour: String
    var size: CGFloat = 10

    var body: some View {
        Rectangle()
            .fill(PieceWords.swatch(colour))
            .frame(width: size, height: size)
            .overlay {
                if PieceWords.isPale(colour) {
                    Rectangle().strokeBorder(Color.outline, lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }
}
