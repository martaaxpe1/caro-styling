import SwiftUI

/// S6, a chapter (designed here, in the style of screens 10 and 11): all the pieces of one
/// chapter as cut-outs, with filters. The season filter starts on the current season, and
/// "All seasons" is always one tap away: the current season never hides pieces for good.
///
/// The filters work on the phone: the chapter's pieces are loaded once, and each filter only
/// chooses which of them to show, so changing one is instant. Each filter is a native iOS menu
/// in the shape of a Caro chip; a chip turns ink when its filter is on.
///
/// Pieces that don't fit yet (T13) come last, as the server sends them, with the indigo dot.
struct ChapterView: View {
    let name: String
    let number: Int

    @Environment(WardrobeStore.self) private var store
    @State private var page: ChapterPage?
    @State private var errorMessage: String?
    @State private var removing: Piece?

    // The filters. Nil means all.
    @State private var season: Int?
    @State private var occasion: Int?
    @State private var colour: String?
    @State private var kind: String?
    @State private var maybeOnly = false
    @State private var doesntFitOnly = false
    /// The season filter starts on the current season once, at the first load.
    @State private var seasonChosen = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 2)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Chapter \(ChapterWords.number(number))")
                    .caroLabelStyle()

                Text(ChapterWords.title(name))
                    .font(.caroPieceTitle)
                    .caroTitleTracking()
                    .padding(.top, 6)

                if let page {
                    Text(countLine(page))
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 4)

                    filters(page)
                        .padding(.top, 14)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                    }

                    grid(page)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 16)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .task { await store.loadLists() }
        // Again each time it shows, so a piece changed, turned or removed shows as it is now.
        .onAppear { Task { await load() } }
        .alert(
            "Remove this piece?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { piece in
            Button("Remove", role: .destructive) {
                Task { await remove(piece) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { piece in
            Text("\(piece.name ?? "This piece") and its photos are deleted.")
        }
    }

    // MARK: Filters

    private func shown(_ page: ChapterPage) -> [Piece] {
        page.pieces.filter { piece in
            (season.map { piece.seasons.contains($0) } ?? true)
                && (occasion.map { piece.occasions.contains($0) } ?? true)
                && (colour.map { piece.colours.contains($0) } ?? true)
                && (kind.map { piece.kind == $0 } ?? true)
                && (!maybeOnly || piece.status == .maybe)
                && (!doesntFitOnly || !piece.fits)
        }
    }

    private var filtered: Bool {
        season != nil || occasion != nil || colour != nil || kind != nil || maybeOnly || doesntFitOnly
    }

    /// "11 pieces", or "6 of 11 pieces" with a filter on.
    private func countLine(_ page: ChapterPage) -> String {
        let all = countText(page.pieces.count, "piece", "pieces")
        let count = shown(page).count
        return count == page.pieces.count ? all : "\(count) of \(all)"
    }

    private func filters(_ page: ChapterPage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !page.seasons.isEmpty {
                    FilterMenu(
                        title: page.seasons.first { $0.id == season }?.name ?? "All seasons",
                        isOn: season != nil,
                        allTitle: "All seasons",
                        options: page.seasons.map { ($0.id, $0.name) },
                        selection: $season
                    )
                }
                if !page.occasions.isEmpty {
                    FilterMenu(
                        title: page.occasions.first { $0.id == occasion }?.name ?? "Occasion",
                        isOn: occasion != nil,
                        allTitle: "All occasions",
                        options: page.occasions.map { ($0.id, $0.name) },
                        selection: $occasion
                    )
                }
                let colours = coloursIn(page)
                if colours.count > 1 || colour != nil {
                    FilterMenu(
                        title: colour.map { PieceWords.title($0) } ?? "Colour",
                        isOn: colour != nil,
                        allTitle: "All colours",
                        options: colours.map { ($0, PieceWords.title($0)) },
                        selection: $colour
                    )
                }
                let kinds = kindsIn(page)
                if kinds.count > 1 || kind != nil {
                    FilterMenu(
                        title: kind.map { PieceWords.title($0) } ?? "Kind",
                        isOn: kind != nil,
                        allTitle: "All kinds",
                        options: kinds.map { ($0, PieceWords.title($0)) },
                        selection: $kind
                    )
                }
                if page.pieces.contains(where: { $0.status == .maybe }) || maybeOnly {
                    Chip(title: "Maybe", isOn: maybeOnly) { maybeOnly.toggle() }
                }
                if page.pieces.contains(where: { !$0.fits }) || doesntFitOnly {
                    Chip(title: FitDot.words, isOn: doesntFitOnly) { doesntFitOnly.toggle() }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    /// The colours on this chapter's pieces, in the order of the fixed list.
    private func coloursIn(_ page: ChapterPage) -> [String] {
        let present = Set(page.pieces.flatMap(\.colours))
        let order = store.lists?.colours ?? present.sorted()
        return order.filter { present.contains($0) }
    }

    /// The kinds of this chapter's pieces, in the order of the fixed list.
    private func kindsIn(_ page: ChapterPage) -> [String] {
        let present = Set(page.pieces.compactMap(\.kind))
        let order = store.lists?.chapters.first { $0.name == name }?.kinds.map(\.name) ?? present.sorted()
        return order.filter { present.contains($0) }
    }

    private func showAll() {
        season = nil
        occasion = nil
        colour = nil
        kind = nil
        maybeOnly = false
        doesntFitOnly = false
    }

    // MARK: Pieces

    @ViewBuilder
    private func grid(_ page: ChapterPage) -> some View {
        let pieces = shown(page)
        if page.pieces.isEmpty {
            Text("No pieces in this chapter now.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
                .padding(.top, 24)
        } else if pieces.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No pieces with these filters.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                Button("Show all") { showAll() }
                    .font(.caroLink)
                    .foregroundStyle(Color.terracotta)
                    .underline()
                    .frame(minHeight: CaroLayout.minTouchTarget)
            }
            .padding(.top, 20)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(pieces) { piece in
                    NavigationLink(value: WardrobeRoute.piece(id: piece.id)) {
                        ChapterTile(piece: piece)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove piece", systemImage: "trash", role: .destructive) {
                            removing = piece
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: Actions

    private func load() async {
        do {
            let loaded = try await store.chapter(name)
            if !seasonChosen {
                season = loaded.currentSeason?.id
                seasonChosen = true
            }
            // A season or occasion removed meanwhile in Settings: drop its filter.
            if let season, !loaded.seasons.contains(where: { $0.id == season }) { self.season = nil }
            if let occasion, !loaded.occasions.contains(where: { $0.id == occasion }) { self.occasion = nil }
            page = loaded
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func remove(_ piece: Piece) async {
        if let failed = await store.remove(piece) {
            errorMessage = failed
        } else {
            await load()
        }
    }
}

/// One filter as a chip that opens a native menu: All, then each choice, with a tick on the
/// chosen one.
struct FilterMenu<Value: Hashable>: View {
    let title: String
    let isOn: Bool
    let allTitle: String
    let options: [(Value, String)]
    @Binding var selection: Value?

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                Text(allTitle).tag(Value?.none)
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(Value?.some(option.0))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.down")
                    .iconFont(10, weight: .medium)
                    .accessibilityHidden(true)
            }
            .font(.text(14, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(isOn ? Color.onInk : Color.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: CaroLayout.chipHeight)
            .background(isOn ? Color.ink : Color.clear, in: Capsule())
            .overlay {
                if !isOn {
                    Capsule().strokeBorder(Color.outline, lineWidth: 1)
                }
            }
            .frame(minHeight: CaroLayout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityValue(isOn ? title : allTitle)
    }
}

/// A piece on the chapter page: its cut-out on the tile colour, its name, "Maybe" when it is one,
/// and the dot when it doesn't fit yet.
struct ChapterTile: View {
    let piece: Piece

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                .fill(Color.tile)
                .aspectRatio(0.9, contentMode: .fit)
                .overlay {
                    PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
                        .padding(piece.hasCutout ? 18 : 8)
                }
                .overlay(alignment: .topLeading) {
                    if piece.status == .maybe {
                        Text("Maybe")
                            .caroLabelStyle()
                            .padding(8)
                    }
                }
                .fitDot(piece, inset: 8)
            Text(piece.name ?? "")
                .font(.caroNote)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the piece")
    }
}
