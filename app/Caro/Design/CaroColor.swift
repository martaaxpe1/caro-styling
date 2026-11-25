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
    static let placeholder = Color(hex: 0x786D5F) // Example text in an empty field. 4.5 to 1 on paper
    static let terracottaOnTile = Color(hex: 0x8E5642) // Small terracotta text on the tile colour. 4.8 to 1
    static let indigo = Color(hex: 0x3C5387)      // The dot of a piece that doesn't fit yet

    // Details from the design files, by name.
    static let drawingNavy = Color(hex: 0x2E3A55)   // Drawn sample pieces, like the tee on screen 05
    static let addingWaiting = Color(hex: 0xD9D0C2) // Adding pieces: a tile waiting its turn (screen 06)
    static let addingWorking = Color(hex: 0xC9BFB0) // Adding pieces: a tile being cut out or read
    static let tagPaper = Color(hex: 0xFBF7F0)      // The "Your starting piece" tag on the styling table
    static let tagEdge = Color(hex: 0xD8CEBF)       // Its edge
    static let shadowBrown = Color(red: 70 / 255, green: 50 / 255, blue: 30 / 255) // Warm brown of the cut-out shadows

    // Season swatches, decorative only. Two seasons use terracotta and sand (screen 03).
    // Four seasons add brown and indigo, from Sara Caro's palette (design/tokens.json, brandPalette).
    static let seasonTerracotta = Color(hex: 0xB4765F)
    static let seasonSand = Color(hex: 0xD9B986)
    static let seasonBrown = Color(hex: 0x917057)
    static let seasonIndigo = Color(hex: 0x3C5387)

    /// The swatch for a season, by its place in the year. Spring sand, summer terracotta,
    /// autumn brown, winter indigo; with two seasons, terracotta then sand.
    static func season(_ index: Int, of count: Int) -> Color {
        let swatches: [Color] = count == 4
            ? [.seasonSand, .seasonTerracotta, .seasonBrown, .seasonIndigo]
            : [.seasonTerracotta, .seasonSand]
        return swatches.indices.contains(index) ? swatches[index] : .outline
    }

    /// Makes a colour from a hex value, written like in the design: 0xF7F2E9.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
