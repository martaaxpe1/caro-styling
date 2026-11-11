import SwiftUI

/// A short note on the tile colour, like the privacy note on screen 01.
/// An optional SF Symbol sits on the left.
struct NoteBox: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .light))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caroNote)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
    }
}

#Preview {
    NoteBox(text: "Your photos are private. Caro uses an AI service to recognise your pieces in them.", systemImage: "lock")
        .padding(CaroLayout.pageMargin)
        .background(Color.paper)
}
