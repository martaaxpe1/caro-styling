import SwiftUI

/// Sizes and shapes from design/tokens.json, in points.
enum CaroLayout {
    static let pageMargin: CGFloat = 20
    static let tileRadius: CGFloat = 4
    static let buttonHeight: CGFloat = 52
    static let chipHeight: CGFloat = 32
    static let minTouchTarget: CGFloat = 44
}

extension View {
    /// The soft shadow under pieces on the styling table and large cut-outs.
    func cutOutShadow() -> some View {
        shadow(color: Color(red: 70 / 255, green: 50 / 255, blue: 30 / 255).opacity(0.22), radius: 4.5, x: 0, y: 8)
    }

    /// The smaller shadow under cut-outs in lists.
    func smallShadow() -> some View {
        shadow(color: Color(red: 60 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.18), radius: 2, x: 0, y: 3)
    }
}
