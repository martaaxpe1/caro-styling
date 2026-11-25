import SwiftUI

/// S9, Look from a photo (to design, in the style of the styling table and the look's page):
/// your photo, and next to it what Caro found; the pieces Caro spotted as numbered credits,
/// each with a tick; a piece it is less sure of asked about ("Is this your pale pink
/// t-shirt?"), never ticked by itself; Add a piece by chapter; occasions in the title and the
/// season chip, as on the styling table; Save look.
///
/// Caro only recognises your pieces in the photo: you confirm every one. If the ticked main
/// pieces (outer layer, top, bottom or dress, shoes) are those of a look you have, the photo is
/// added to that look instead ("You already have this look: No. 12."). The server decides.
struct LookFromPhotoView: View {
    /// The photo as JPEG, upright, at most 2000 pixels.
    let photo: Data

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Finding, then the answer, or why there is none.
    @State private var spotted: SpottedLook?
    @State private var finding = true
    @State private var findError: String?

    /// Everything the styling table chooses from: for Add a piece, the occasions and seasons.
    @State private var table: StylingTable?
    @State private var loadError: String?
    /// The member's looks, to say "You already have this look" before saving.
    @State private var looks: [Look] = []

    /// The pieces in the list, in order: spotted ones first, then the ones added by hand.
    @State private var listed: [Piece] = []
    @State private var ticked: Set<Int> = []
    /// Pieces Caro is less sure of, still waiting for Yes or No.
    @State private var asking: Set<Int> = []
    @State private var occasions: Set<Int> = []
    @State private var seasons: Set<Int> = []
    @State private var addingPiece = false
    @State private var saveError: String?
    @State private var saving = false
    @State private var started = false

    private let image: UIImage?

    init(photo: Data) {
        self.photo = photo
        self.image = UIImage(data: photo)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let table {
                content(table)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(loadError)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                    Button("Try again") { Task { await loadTable() } }
                        .font(.caroLink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        // Started once, outside the view's own task: the screen settles while the photo picker
        // closes, and a view's task would be cancelled then, losing Claude's answer.
        .onAppear {
            guard !started else { return }
            started = true
            Task { await loadTable() }
            Task { await find() }
        }
        .sheet(isPresented: $addingPiece) {
            if let table {
                AddPieceSheet(pieces: table.pieces, listed: Set(listed.map(\.id))) { piece in
                    add(piece)
                }
            }
        }
    }

    // MARK: Parts

    private var header: some View {
        ZStack {
            Text("From a photo")
                .caroLabelStyle()
                .foregroundStyle(Color.ink)
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.text(15, relativeTo: .body))
                    .topBarButtonStyle()
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private func content(_ table: StylingTable) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock(table)
                    .padding(.top, 10)

                HStack(alignment: .top, spacing: 16) {
                    photoTile
                    found
                }
                .padding(.top, 18)

                Text("The pieces")
                    .font(.caroSectionTitle)
                    .padding(.top, 22)

                pieces
                    .padding(.top, 8)

                Button {
                    addingPiece = true
                } label: {
                    Label("Add a piece", systemImage: "plus")
                        .font(.caroLink)
                        .frame(minHeight: CaroLayout.minTouchTarget)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                if let same = sameLook {
                    NoteBox(text: "You already have this look: No. \(same.number). Your photo is added to it.")
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if let saveError {
                    Text(saveError)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(saveTitle) {
                    Task { await save() }
                }
                .buttonStyle(.pill)
                .disabled(ticked.count < 2 || saving || finding)
            }
            .bottomButtonBar()
        }
    }

    /// "A new look", or "A look for the *office*": a menu that ticks occasions, and the season
    /// chip, as on the styling table.
    private func titleBlock(_ table: StylingTable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(table.occasions) { occasion in
                    Toggle(occasion.name, isOn: binding(occasion.id, in: $occasions))
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title(table)
                        .font(.display(30, relativeTo: .largeTitle))
                        .caroTitleTracking()
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .iconFont(15, weight: .light)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.ink)
            }
            .menuActionDismissBehavior(.disabled)
            .accessibilityHint("Choose the occasions")

            if !table.seasons.isEmpty {
                Menu {
                    ForEach(table.seasons) { season in
                        Toggle(season.name, isOn: binding(season.id, in: $seasons))
                    }
                } label: {
                    Text(seasonTitle(table))
                        .font(.text(12, weight: .medium, relativeTo: .footnote))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 1))
                        .frame(minHeight: CaroLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .menuActionDismissBehavior(.disabled)
                .accessibilityLabel("Seasons, \(seasonTitle(table))")
            }
        }
    }

    /// Your photo, in a 4 point tile.
    private var photoTile: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.photo
            }
        }
        .frame(width: 132, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        .accessibilityLabel("Your photo")
    }

    /// Next to the photo: finding, what was found, or why nothing was.
    @ViewBuilder
    private var found: some View {
        VStack(alignment: .leading, spacing: 8) {
            if finding {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Finding your pieces")
                    .font(.caroRowTitle)
                Text("Caro looks for them in your edit. This takes about half a minute.")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            } else if let findError {
                Text(findError)
                    .font(.caroNote)
                    .foregroundStyle(Color.terracotta)
                Button("Try again") { Task { await find() } }
                    .font(.caroLink)
                    .underline()
                    .frame(minHeight: CaroLayout.minTouchTarget)
            } else if let spotted {
                Text(foundLine(spotted))
                    .font(.caroRowTitle)
                if let quality = qualityLine(spotted.photoQuality) {
                    Text(quality)
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                if !spotted.notInWardrobe.isEmpty {
                    Text("Not in your edit: " + sentence(spotted.notInWardrobe.map(\.description)) + ".")
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pieces: some View {
        if listed.isEmpty {
            Text(finding ? "Your pieces will show here." : "Add the pieces you are wearing.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(listed.enumerated()), id: \.element.id) { index, piece in
                    if asking.contains(piece.id) {
                        question(piece)
                    } else {
                        credit(index + 1, piece)
                    }
                }
            }
        }
    }

    /// A numbered credit with a tick: "01", the piece on the tile colour, its name and slot.
    private func credit(_ number: Int, _ piece: Piece) -> some View {
        let on = ticked.contains(piece.id)
        return Button {
            toggle(piece)
        } label: {
            HStack(spacing: 14) {
                Text(ChapterWords.number(number))
                    .font(.display(18, relativeTo: .title3))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 28, alignment: .leading)
                pieceTile(piece)
                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.name ?? "Piece")
                        .font(.caroRowTitle)
                    Text(slotTitle(piece))
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .iconFont(22, weight: .light)
                    .foregroundStyle(on ? Color.ink : Color.outline)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(on ? Color.ink : Color.muted)
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(piece.name ?? "Piece")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Takes it off the look" : "Puts it on the look")
    }

    /// "Is this your pale pink t-shirt?", with Yes and No. Yes ticks it; No takes it off the list.
    private func question(_ piece: Piece) -> some View {
        HStack(spacing: 14) {
            pieceTile(piece)
            VStack(alignment: .leading, spacing: 6) {
                Text("Is this your \(lowercasedFirst(piece.name ?? "piece"))?")
                    .font(.display(17, relativeTo: .headline))
                    .italic()
                    .foregroundStyle(Color.terracotta)
                HStack(spacing: 18) {
                    Button("Yes") {
                        asking.remove(piece.id)
                        tick(piece)
                    }
                    Button("No") {
                        asking.remove(piece.id)
                        listed.removeAll { $0.id == piece.id }
                    }
                }
                .font(.caroLink)
                .underline()
                .buttonStyle(.plain)
                .frame(minHeight: 32)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private func pieceTile(_ piece: Piece) -> some View {
        PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
            .padding(4)
            .frame(width: 52, height: 52)
            .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
    }

    // MARK: Words

    private var saveTitle: String {
        if saving { return "Saving" }
        if let same = sameLook { return "Add photo to No. \(same.number)" }
        return "Save look"
    }

    /// "Caro found 4 of your pieces." Questions count too: they are pieces it found.
    private func foundLine(_ spotted: SpottedLook) -> String {
        switch spotted.spotted.count {
        case 0: "Caro found none of your pieces. Add them yourself."
        case 1: "Caro found 1 of your pieces."
        default: "Caro found \(spotted.spotted.count) of your pieces."
        }
    }

    private func qualityLine(_ quality: String?) -> String? {
        switch quality {
        case "partly hidden": "Some of the look is hidden in the photo."
        case "too dark": "The photo is quite dark."
        case "blurry": "The photo is a little blurry."
        default: nil
        }
    }

    /// "A new look", "A look for the *office*": as on the styling table.
    private func title(_ table: StylingTable) -> Text {
        let names = table.occasions.filter { occasions.contains($0.id) }.map { OccasionWords.phrase($0.name) }
        let sentence: String
        switch names.count {
        case 0: sentence = "A new look"
        case 1: sentence = "A look for \(names[0])"
        case 2: sentence = "A look for \(names[0]) and \(names[1])"
        default: sentence = "A look for \(names.count) occasions"
        }
        var words = sentence.split(separator: " ").map(String.init)
        let last = words.removeLast()
        return Text("\(words.joined(separator: " ")) \(Text(last).italic())")
    }

    private func seasonTitle(_ table: StylingTable) -> String {
        let names = table.seasons.filter { seasons.contains($0.id) }.map(\.name)
        guard let first = names.first else { return "Any season" }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }

    private func slotTitle(_ piece: Piece) -> String {
        (piece.slot.flatMap(Slot.init) ?? .accessories).title
    }

    private func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    /// "Blue jeans, white trainers and a belt" style: commas and a last "and", the first word kept.
    private func sentence(_ items: [String]) -> String {
        let words = items.enumerated().map { $0.offset == 0 ? $0.element : lowercasedFirst($0.element) }
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    // MARK: Choosing

    /// The look with the same main pieces as the ticked ones, if you have one.
    private var sameLook: Look? {
        let main = Set(listed.filter { ticked.contains($0.id) && Look.mainSlots.contains($0.slot ?? "") }.map(\.id))
        guard !main.isEmpty else { return nil }
        return looks.first { $0.mainPieces == main }
    }

    private func toggle(_ piece: Piece) {
        if ticked.contains(piece.id) {
            ticked.remove(piece.id)
        } else {
            tick(piece)
        }
    }

    /// Ticks a piece. One piece per slot except accessories; a dress takes the bottom's place,
    /// and a bottom the dress's. The piece it replaces stays in the list, unticked.
    private func tick(_ piece: Piece) {
        saveError = nil
        guard let slot = piece.slot.flatMap(Slot.init) else { return }
        var replaced: Set<Slot> = slot.holdsSeveral ? [] : [slot]
        if slot == .onePiece { replaced.insert(.bottom) }
        if slot == .bottom { replaced.insert(.onePiece) }
        for other in listed where ticked.contains(other.id) {
            if let otherSlot = other.slot.flatMap(Slot.init), replaced.contains(otherSlot) {
                ticked.remove(other.id)
            }
        }
        ticked.insert(piece.id)
    }

    /// A piece added by hand goes at the end of the list, ticked.
    private func add(_ piece: Piece) {
        if !listed.contains(where: { $0.id == piece.id }) {
            listed.append(piece)
        }
        asking.remove(piece.id)
        tick(piece)
    }

    private func binding(_ id: Int, in set: Binding<Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in
                if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }

    // MARK: Server

    private func loadTable() async {
        do {
            async let tableAnswer = store.stylingTable()
            async let looksAnswer = store.looks()
            let (table, page) = try await (tableAnswer, looksAnswer)
            if self.table == nil {
                seasons = Set([table.currentSeason?.id].compactMap { $0 })
            }
            looks = page.looks
            self.table = table
            loadError = nil
        } catch {
            loadError = store.message(for: error)
        }
    }

    private func find() async {
        finding = true
        findError = nil
        defer { finding = false }
        do {
            let answer = try await store.spotPieces(photo: photo)
            spotted = answer
            // Spotted pieces first, in Caro's order; any added by hand while waiting stay after.
            let handAdded = listed.filter { piece in !answer.spotted.contains { $0.piece.id == piece.id } }
            listed = answer.spotted.map(\.piece) + handAdded
            for item in answer.spotted {
                if item.ticked {
                    tick(item.piece)
                } else if !ticked.contains(item.piece.id) {
                    asking.insert(item.piece.id)
                }
            }
        } catch {
            findError = store.message(for: error)
        }
    }

    private func save() async {
        guard let table else { return }
        saving = true
        defer { saving = false }
        let draft = LookDraft(
            pieces: listed.map(\.id).filter(ticked.contains),
            occasions: table.occasions.map(\.id).filter(occasions.contains),
            seasons: table.seasons.map(\.id).filter(seasons.contains)
        )
        do {
            let saved = try await store.saveLookFromPhoto(draft, photo: photo)
            store.lookToOpen = saved.look.id
            dismiss()
        } catch {
            saveError = store.message(for: error)
        }
    }
}

/// Add a piece: the chapters with how many pieces each has, then that chapter's pieces as
/// cut-outs, those that don't fit yet last and with the dot (T13). Tapping one adds it to the look
/// and closes. Also used on Your version (T10).
struct AddPieceSheet: View {
    let pieces: [Piece]
    let listed: Set<Int>
    /// "Add a piece" on S9; "Choose your piece" on Your version.
    var title = "Add a piece"
    let add: (Piece) -> Void

    @Environment(\.dismiss) private var dismiss

    private var chapters: [(name: String, pieces: [Piece])] {
        let order = ChapterWords.order
        let grouped = Dictionary(grouping: pieces.filter { $0.chapter != nil }, by: { $0.chapter! })
        return grouped.keys
            .sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
            .map { (name: $0, pieces: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(chapters.enumerated()), id: \.element.name) { _, chapter in
                    NavigationLink {
                        grid(chapter.name, chapter.pieces)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(ChapterWords.number(ChapterWords.order.firstIndex(of: chapter.name).map { $0 + 1 } ?? 0))
                                .font(.display(18, relativeTo: .title3))
                                .foregroundStyle(Color.muted)
                            Text(ChapterWords.title(chapter.name))
                                .font(.caroChapterName)
                            Spacer()
                            Text("\(chapter.pieces.count)")
                                .font(.caroMeta)
                                .foregroundStyle(Color.muted)
                        }
                        .foregroundStyle(Color.ink)
                    }
                    .listRowBackground(Color.paper)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.caroButton)
                }
            }
        }
        .tint(Color.ink)
    }

    private func grid(_ chapter: String, _ pieces: [Piece]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(pieces) { piece in
                    let on = listed.contains(piece.id)
                    Button {
                        add(piece)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
                                .padding(10)
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                                .overlay {
                                    RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                                        .strokeBorder(on ? Color.ink : Color.clear, lineWidth: 2)
                                }
                                .fitDot(piece, inset: 6)
                            Text(piece.name ?? "Piece")
                                .font(.caroMeta)
                                .lineLimit(2)
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(piece.spokenName)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(CaroLayout.pageMargin)
        }
        .background(Color.paper)
        .navigationTitle(ChapterWords.title(chapter))
        .navigationBarTitleDisplayMode(.inline)
    }
}
