import SwiftUI

/// Caro's colours, from design/tokens.json.
/// Use them by name, for example `.foregroundStyle(Color.ink)` or `.background(Color.paper)`.
extension Color {
    static let paper = Color(hex: 0xF7F2E9)       // App background
    static let ink = Color(hex: 0x161514)         // Text, primary buttons, rules, selected chips
    static let muted = Color(hex: 0x6B645C)       // Secondary text, labels, inactive tabs
    static let hairline = Color(hex: 0xDCD2C2)    // Row dividers, empty progress
    static let tile = Color(hex: 0xEFE7DB)        // Behind cut-outs, the styling table, notes
    static let photo = Color(hex: 0xD3C7B6)       // Inspiration photo placeholder
    static let outline = Color(hex: 0xB9AE9C)     // Unselected chip borders
    static let emptySlot = Color(hex: 0x9A8F7F)   // Dashed empty slots and add buttons
    static let terracotta = Color(hex: 0x9A5E48)  // Missing pieces, Find it, warnings, small links
    static let onInk = Color(hex: 0xF7F2E9)       // Text on ink buttons and chips

    // Season swatches, decorative only.
    static let seasonTerracotta = Color(hex: 0xB4765F)
    static let seasonSand = Color(hex: 0xD9B986)

    /// Makes a colour from a hex value, written like in the design: 0xF7F2E9.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
