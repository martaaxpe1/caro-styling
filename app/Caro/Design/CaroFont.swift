import SwiftUI

/// Caro's text styles, from design/tokens.json.
/// Bodoni Moda for display, Inter for everything else. Every style grows with
/// the iPhone's text size setting (Dynamic Type), anchored to a system style.
/// Use them like any font: `.font(.caroScreenTitle)`.
extension Font {
    // Display, Bodoni Moda. Add `.italic()` to a word for emphasis: "Your *version*".
    static let caroScreenTitle = display(32, relativeTo: .largeTitle)
    static let caroPieceTitle = display(34, relativeTo: .largeTitle)
    static let caroChapterNumber = display(30, relativeTo: .title)
    static let caroChapterName = display(21, relativeTo: .title2)
    static let caroSectionTitle = display(18, relativeTo: .title3).italic()

    // Text, Inter.
    static let caroBody = text(14, relativeTo: .body)
    static let caroButton = text(15, weight: .medium, relativeTo: .body)
    static let caroTab = text(14, weight: .medium, relativeTo: .body)
    static let caroTabSelected = text(14, weight: .semibold, relativeTo: .body)
    static let caroMeta = text(12, relativeTo: .footnote)
    static let caroLabel = text(11, relativeTo: .caption) // Use with .caroLabelStyle()

    static func display(_ size: CGFloat, relativeTo style: TextStyle) -> Font {
        .custom("Bodoni Moda", size: size, relativeTo: style)
    }

    static func text(_ size: CGFloat, weight: Weight = .regular, relativeTo style: TextStyle) -> Font {
        .custom("Inter", size: size, relativeTo: style).weight(weight)
    }
}

extension View {
    /// Labels: small capitals with wide spacing, in muted ink. "STEP 1 OF 6".
    func caroLabelStyle() -> some View {
        self
            .font(.caroLabel)
            .textCase(.uppercase)
            .tracking(11 * 0.16)
            .foregroundStyle(Color.muted)
    }

    /// Screen titles are set slightly tight, as in the design.
    func caroTitleTracking() -> some View {
        tracking(32 * -0.01)
    }
}
