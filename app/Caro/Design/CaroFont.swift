import SwiftUI

/// Caro's text styles, from design/tokens.json.
/// Newsreader for display, Inter for everything else. Every style grows with
/// the iPhone's text size setting (Dynamic Type), anchored to a system style.
/// Use them like any font: `.font(.caroScreenTitle)`.
extension Font {
    // Display, Newsreader. Add `.italic()` to a word for emphasis: "Your *version*".
    static let caroScreenTitle = display(32, relativeTo: .largeTitle)
    static let caroPieceTitle = display(34, relativeTo: .largeTitle)
    static let caroChapterNumber = display(30, relativeTo: .title)
    static let caroChapterName = display(21, relativeTo: .title2)
    static let caroSectionTitle = display(18, relativeTo: .title3).italic()
    static let caroLead = display(26, relativeTo: .title).italic()  // The line under the wordmark: welcome, sign in
    static let caroField = display(22, relativeTo: .title2)         // Text typed into an underlined field
    static let caroCode = display(30, relativeTo: .title)           // The 6-digit sign-in code

    // Text, Inter.
    static let caroBody = text(14, relativeTo: .body)
    static let caroRowTitle = text(15, weight: .medium, relativeTo: .body)    // The main line of a list row
    static let caroNote = text(13, relativeTo: .subheadline)                  // Notes and error lines
    static let caroLink = text(13, weight: .medium, relativeTo: .subheadline) // Small links, like Send a new code
    static let caroButton = text(15, weight: .medium, relativeTo: .body)
    static let caroTab = text(14, weight: .medium, relativeTo: .body)
    static let caroTabSelected = text(14, weight: .semibold, relativeTo: .body)
    static let caroMeta = text(12, relativeTo: .footnote)
    static let caroLabel = text(11, relativeTo: .caption) // Use with .caroLabelStyle()

    static func display(_ size: CGFloat, relativeTo style: TextStyle) -> Font {
        .custom("Newsreader", size: size, relativeTo: style)
    }

    static func text(_ size: CGFloat, weight: Weight = .regular, relativeTo style: TextStyle) -> Font {
        .custom("Inter", size: size, relativeTo: style).weight(weight)
    }
}

/// An SF Symbol that grows with the iPhone's text size, like the words next to it.
/// `size` is its size at the normal text size; it grows at most to twice that.
private struct IconFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let baseSize: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        baseSize = size
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(size, baseSize * 2), weight: weight))
    }
}

extension View {
    /// The font for an icon next to text: `Image(systemName: "plus").iconFont(17, weight: .light)`.
    func iconFont(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(IconFont(size: size, weight: weight, relativeTo: style))
    }

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
