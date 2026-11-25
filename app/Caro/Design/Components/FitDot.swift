import SwiftUI

/// The small indigo dot of a piece that doesn't fit yet (T13), at the bottom right of its picture.
/// A thin ring in the tile colour keeps it readable on top of a photo. VoiceOver says the words.
struct FitDot: View {
    static let words = "Doesn't fit yet"

    var body: some View {
        Circle()
            .fill(Color.indigo)
            .frame(width: 8, height: 8)
            .padding(1.5)
            .background(Color.tile, in: Circle())
            .accessibilityElement()
            .accessibilityLabel(Self.words)
    }
}

extension View {
    /// Puts the dot on a piece's picture, only when the piece doesn't fit yet.
    func fitDot(_ piece: Piece, inset: CGFloat) -> some View {
        overlay(alignment: .bottomTrailing) {
            if !piece.fits {
                FitDot().padding(inset)
            }
        }
    }
}
