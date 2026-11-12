import SwiftUI

/// Screen 09, Your wardrobe is open: shown once, when a confirm opens Looks and Get the look.
/// Up to six of the member's own cut-outs laid out as a flat lay, as in the design, then the
/// title, a line, Go to the edit and Style your first look.
struct WardrobeOpenView: View {
    let pieces: Int
    /// true: Style your first look (opens Looks); false: Go to the edit.
    let done: (_ openLooks: Bool) -> Void

    @Environment(WardrobeStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Wordmark(height: 18)
                .padding(.top, 18)

            OpenFlatLay(thumbs: flatLayThumbs)
                .frame(height: 340)
                .padding(.top, 28)

            VStack(spacing: 0) {
                Text(pieces == 1 ? "1 piece" : "\(pieces) pieces")
                    .caroLabelStyle()
                Text("Your wardrobe is \(Text("open").italic())")
                    .font(.caroPieceTitle)
                    .caroTitleTracking()
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Text("Looks and Get the look are ready. Keep adding pieces whenever you like: the more of your wardrobe Caro knows, the more of an inspiration it can match.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Button("Go to the edit") { done(false) }
                    .buttonStyle(.pillOutlined)
                Button("Style your first look") { done(true) }
                    .buttonStyle(.pill)
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.bottom, 8)
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        .task { await store.load() }
    }

    /// One cut-out per place in the flat lay, in the design's order: a top, outerwear, a skirt
    /// or dress, trousers, a bag, shoes. Empty places take other pieces.
    private var flatLayThumbs: [String] {
        let chapters = store.wardrobe?.chapters ?? []
        let byName = Dictionary(uniqueKeysWithValues: chapters.map { ($0.name, $0.thumbs) })
        let wanted: [[String]] = [
            ["tops", "knitwear"], ["outerwear"], ["dresses and skirts"], ["trousers"], ["accessories"], ["shoes"],
        ]
        var used = Set<String>()
        var places: [String?] = wanted.map { names in
            let thumb = names.compactMap { byName[$0]?.first }.first
            if let thumb { used.insert(thumb) }
            return thumb
        }
        var spare = chapters.flatMap(\.thumbs).filter { !used.contains($0) }
        for index in places.indices where places[index] == nil && !spare.isEmpty {
            places[index] = spare.removeFirst()
        }
        return places.compactMap { $0 }
    }
}

/// The pieces laid out on paper with soft shadows, at the design's places and angles
/// (screen 09, 390 points wide; scaled to the screen).
private struct OpenFlatLay: View {
    let thumbs: [String]

    // x, y, size, angle, from design/screens/09-wardrobe-open.dc.html
    private let places: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (150, 6, 124, 4),
        (28, 4, 178, -5),
        (238, 20, 128, 7),
        (156, 112, 150, -2),
        (34, 186, 112, -6),
        (236, 212, 124, -10),
    ]

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 390
            ZStack(alignment: .topLeading) {
                ForEach(Array(thumbs.prefix(places.count).enumerated()), id: \.offset) { index, thumb in
                    let place = places[index]
                    PieceImage(path: thumb, shadow: .large)
                        .frame(width: place.2 * scale, height: place.2 * scale)
                        .rotationEffect(.degrees(place.3))
                        .offset(x: place.0 * scale, y: place.1 * scale)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
}
