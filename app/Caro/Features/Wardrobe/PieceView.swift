import SwiftUI

/// Screen 11, a piece: its chapter, the cut-out large and slightly turned, its name with the last
/// word in italics, brand, material and warmth, its seasons, occasions and colour, the looks it
/// is in, and Edit.
///
/// Added to the design: the button that turns a photo taken sideways (from T5), the member's
/// note under the details, and two small links at the bottom, Mark as maybe and Remove.
/// Style a look with it opens the styling table with this piece on it (T7).
/// Not yet: the Size row (size is not filled in yet).
struct PieceView: View {
    let pieceID: Int

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page: PiecePage?
    @State private var errorMessage: String?
    @State private var working = false
    @State private var confirmingRemove = false
    @State private var styling: StyleStart?

    var body: some View {
        Group {
            if let page {
                content(page)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caroNote)
                    .foregroundStyle(Color.terracotta)
                    .padding(CaroLayout.pageMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let piece = page?.piece {
                    NavigationLink("Edit", value: WardrobeRoute.editPiece(piece))
                        .font(.caroButton)
                        .disabled(working)
                }
            }
        }
        .task { await store.loadLists() }
        // Again each time it shows: after Edit, the page shows what was saved.
        .onAppear { Task { await load() } }
        // Looks open with the wardrobe (checked on the server): until then there is no pill.
        .safeAreaInset(edge: .bottom) {
            if page != nil, store.progress?.unlocked == true {
                Button("Style a look with it") { styling = .piece(id: pieceID) }
                    .buttonStyle(.pill)
                    .disabled(working)
                    .bottomButtonBar()
            }
        }
        .fullScreenCover(item: $styling) { start in
            StyleLookView(start: start) { _ in
                Task { await load() }
            }
        }
        .alert("Remove this piece?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(page?.piece.name ?? "This piece") and its photos are deleted.")
        }
    }

    private func content(_ page: PiecePage) -> some View {
        let piece = page.piece
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(label(piece))
                    .caroLabelStyle()

                picture(piece)

                PieceName(name: piece.name ?? "")
                    .padding(.top, 4)

                if let line = subline(piece) {
                    Text(line)
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 6)
                }

                VStack(spacing: 0) {
                    if !page.seasons.isEmpty {
                        DetailRow(label: "Seasons", value: names(piece.seasons, in: page.seasons))
                    }
                    DetailRow(label: "Occasions", value: names(piece.occasions, in: page.occasions))
                    DetailRow(label: "Colour") { colourValue(piece) }
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .padding(.top, 16)

                if let notes = piece.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 12)
                }

                looks(page.looks)
                    .padding(.top, 18)

                HStack {
                    Button(piece.status == .maybe ? "No longer a maybe" : "Mark as maybe") {
                        Task { await setStatus(piece.status == .maybe ? .confirmed : .maybe) }
                    }
                    Spacer()
                    Button("Remove") { confirmingRemove = true }
                }
                .font(.caroLink)
                .foregroundStyle(Color.terracotta)
                .underline()
                .frame(minHeight: CaroLayout.minTouchTarget)
                .padding(.top, 20)
                .disabled(working)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    // MARK: Parts

    /// The cut-out large, turned a little, with its soft shadow; a photo where nothing lifted.
    private func picture(_ piece: Piece) -> some View {
        PieceImage(path: piece.images.large, isCutout: piece.hasCutout, shadow: .large)
            .frame(width: 226, height: 226)
            .rotationEffect(.degrees(piece.hasCutout ? -3 : 0))
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .overlay(alignment: .bottomTrailing) {
                // For a photo taken sideways: each tap turns it a quarter turn.
                Button {
                    Task { await rotate() }
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.ink)
                        .frame(width: 36, height: 36)
                        .background(Color.tile, in: Circle())
                        .frame(width: CaroLayout.minTouchTarget, height: CaroLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .disabled(working)
                .accessibilityLabel("Turn the photo")
            }
    }

    @ViewBuilder
    private func looks(_ looks: [LookSummary]) -> some View {
        if looks.isEmpty {
            Text("Not in a look yet.")
                .font(.caroSectionTitle)
                .foregroundStyle(Color.muted)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(looks.count == 1 ? "In 1 look" : "In \(looks.count) looks")
                        .font(.caroSectionTitle)
                    Spacer()
                    if let piece = page?.piece {
                        NavigationLink("See all", value: WardrobeRoute.looksWith(pieceID: piece.id, name: piece.name ?? ""))
                            .font(.text(13, weight: .medium, relativeTo: .subheadline))
                            .foregroundStyle(Color.terracotta)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(looks.prefix(3)) { look in
                        NavigationLink(value: WardrobeRoute.look(id: look.id)) {
                            LookTile(look: look)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func colourValue(_ piece: Piece) -> some View {
        HStack(spacing: 6) {
            if piece.colours.isEmpty {
                Text("None yet").foregroundStyle(Color.muted)
            } else {
                ForEach(piece.colours, id: \.self) { ColourSwatch(colour: $0) }
                Text(colourText(piece))
            }
        }
    }

    // MARK: Words

    /// "01 · Outerwear", and "· Maybe" when it is one.
    private func label(_ piece: Piece) -> String {
        guard let chapter = piece.chapter, let number = store.lists?.chapters.first(where: { $0.name == chapter })?.number else {
            return piece.status == .maybe ? "Maybe" : ""
        }
        let label = ChapterWords.label(chapter, number)
        return piece.status == .maybe ? "\(label) · Maybe" : label
    }

    /// "Arket · Wool · Warm"
    private func subline(_ piece: Piece) -> String? {
        let parts = [piece.brand, piece.material.map { PieceWords.title($0) }, piece.warmth.map { PieceWords.title($0) }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Autumn, winter": the names in the member's order, as one sentence.
    private func names(_ ids: [Int], in items: [NamedItem]) -> String? {
        let words = items.filter { ids.contains($0.id) }.map(\.name)
        guard let first = words.first else { return nil }
        let rest = words.dropFirst().map { $0.prefix(1).lowercased() + $0.dropFirst() }
        return ([first] + rest).joined(separator: ", ")
    }

    private func colourText(_ piece: Piece) -> String {
        let colours = piece.colours.enumerated().map { $0.offset == 0 ? PieceWords.title($0.element) : $0.element }.joined(separator: ", ")
        guard let pattern = piece.pattern, pattern != "plain" else { return colours }
        return "\(colours) · \(PieceWords.title(pattern))"
    }

    // MARK: Actions

    private func load() async {
        do {
            page = try await store.piecePage(pieceID)
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func setStatus(_ status: Piece.Status) async {
        working = true
        defer { working = false }
        do {
            _ = try await store.setStatus(of: pieceID, to: status)
            await load()
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func rotate() async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            _ = try await store.rotate(pieceID)
            await load()
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func remove() async {
        guard let piece = page?.piece else { return }
        working = true
        defer { working = false }
        if let failed = await store.remove(piece) {
            errorMessage = failed
        } else {
            dismiss()
        }
    }
}

/// A piece's name in Bodoni, 34, with its last word in italics: "Camel wool *coat*".
struct PieceName: View {
    let name: String

    var body: some View {
        let words = name.split(separator: " ")
        Group {
            if words.count > 1, let last = words.last {
                Text("\(words.dropLast().joined(separator: " ")) \(Text(last).italic())")
            } else {
                Text(name).italic()
            }
        }
        .font(.caroPieceTitle)
        .caroTitleTracking()
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One line of details: a label in capitals on the left, the value on the right, a hairline above.
struct DetailRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caroLabel)
                .textCase(.uppercase)
                .tracking(11 * 0.14)
                .foregroundStyle(Color.muted)
            Spacer(minLength: 0)
            value()
                .font(.caroBody)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6) // Room above and below when the text is large; no change at the normal size.
        .frame(minHeight: 38)
        .padding(.vertical, 2)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension DetailRow where Value == Text {
    init(label: String, value: String?) {
        self.label = label
        self.value = {
            Text(value ?? "None yet").foregroundStyle(value == nil ? Color.muted : Color.ink)
        }
    }
}

/// A look as a small flat lay on the tile colour, for the piece page.
struct LookTile: View {
    let look: LookSummary

    var body: some View {
        FlatLay(items: look.pieces.map {
            FlatLayItem(id: $0.id, slot: Slot(rawValue: $0.slot) ?? .accessories, path: $0.thumb, isCutout: $0.hasCutout)
        })
        .frame(height: 100)
        .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        .accessibilityElement()
        .accessibilityLabel(["Look \(look.number)", look.occasions.first?.lowercased()].compactMap { $0 }.joined(separator: ", "))
    }
}
