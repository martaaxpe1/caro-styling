import SwiftUI

/// Where the styling table starts: empty, with the piece you came from, or with a saved look
/// to change.
enum StyleStart: Identifiable, Hashable {
    case empty
    case piece(id: Int)
    case look(Look)

    var id: String {
        switch self {
        case .empty: "empty"
        case .piece(let id): "piece-\(id)"
        case .look(let look): "look-\(look.id)"
        }
    }
}

/// Screen 12, Style a look: the styling table. The occasions in the title, the season chip,
/// the pieces laid out as a flat lay, the rail of slots, the tray of your pieces for the chosen
/// slot (the season's first), and Save look. You choose every piece: Caro never proposes one.
///
/// Added to the design: Dress in the rail (a dress takes the bottom's place, a top can stay);
/// the tray scrolls sideways, the season's pieces first and the others after a hairline; tap a
/// piece in the tray to place it, again to take it off; tap a piece on the table to choose its
/// slot; "A new look" when no occasion is ticked. Save look is ready at two pieces.
struct StyleLookView: View {
    let start: StyleStart
    /// Called with the saved look, before the table closes.
    var onSaved: (Look) -> Void = { _ in }

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var table: StylingTable?
    @State private var picked: [Int] = []
    @State private var occasions: Set<Int> = []
    @State private var seasons: Set<Int> = []
    @State private var slot: Slot = .outerLayer
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var saving = false

    private static let rail: [Slot] = [.outerLayer, .top, .bottom, .onePiece, .shoes, .bag, .accessories]

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
                    Button("Try again") { Task { await load() } }
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
        .task { await load() }
    }

    // MARK: Parts

    private var header: some View {
        ZStack {
            Text(lookNumber.map { "Look No. \($0)" } ?? "Style a look")
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
                    .padding(.horizontal, CaroLayout.pageMargin)
                    .padding(.top, 10)

                FlatLay(
                    items: items(table),
                    shadow: .large,
                    emptySlot: slot,
                    startingPieceID: startingPieceID,
                    onTap: { slot = $0.slot }
                )
                .frame(height: 340)
                .background(Color.tile)
                .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
                .padding(.top, 18)
                .accessibilityElement()
                .accessibilityLabel(tableDescription(table))

                railOfSlots
                    .padding(.top, 10)

                tray(table)
                    .padding(.top, 8)
            }
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
                Button(saving ? "Saving" : "Save look") {
                    Task { await save() }
                }
                .buttonStyle(.pill)
                .disabled(picked.count < 2 || saving)
            }
            .bottomButtonBar()
        }
    }

    /// "A look for the *office*", a menu that ticks occasions; the season chip, and the line
    /// on where the look started.
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

            HStack(spacing: 10) {
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
                if let line = startedLine(table) {
                    Text(line)
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Outer layer, Top, Bottom, Dress, Shoes, Bag, Accessories: the chosen one underlined.
    private var railOfSlots: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Self.rail, id: \.self) { item in
                    let current = item == slot
                    Button {
                        slot = item
                    } label: {
                        Text(item.title)
                            .font(.text(13, weight: current ? .semibold : .medium, relativeTo: .subheadline))
                            .foregroundStyle(current ? Color.ink : Color.muted)
                            .overlay(alignment: .bottom) {
                                if current {
                                    Rectangle().fill(Color.ink).frame(height: 1).offset(y: 5)
                                }
                            }
                            .frame(minHeight: CaroLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
        }
    }

    /// Your pieces for the chosen slot: the season's first, then the others after a hairline.
    private func tray(_ table: StylingTable) -> some View {
        let (inSeason, others) = trayPieces(table)
        return VStack(alignment: .leading, spacing: 8) {
            Text(trayTitle(table, count: inSeason.count, all: inSeason.count + others.count))
                .font(.caroMeta)
                .foregroundStyle(Color.muted)
                .padding(.horizontal, CaroLayout.pageMargin)

            if !inSeason.isEmpty || !others.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(inSeason) { trayTile($0) }
                        if !inSeason.isEmpty && !others.isEmpty {
                            Rectangle().fill(Color.hairline).frame(width: 1, height: 56)
                                .accessibilityHidden(true)
                        }
                        ForEach(others) { trayTile($0) }
                    }
                    .padding(.horizontal, CaroLayout.pageMargin)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func trayTile(_ piece: Piece) -> some View {
        let on = picked.contains(piece.id)
        return Button {
            toggle(piece)
        } label: {
            PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
                .padding(8)
                .frame(width: 78, height: 74)
                .background(Color.tile, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(on ? Color.ink : Color.hairline, lineWidth: on ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(piece.name ?? "Piece")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Words

    private var lookNumber: Int? {
        if case .look(let look) = start { return look.number }
        return nil
    }

    private var startingPieceID: Int? {
        if case .piece(let id) = start, picked.contains(id) { return id }
        return nil
    }

    /// "A new look", "A look for the *office*", "A look for the office and *day out*",
    /// "A look for 3 *occasions*": the last word in italics, as in the design.
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

    /// "Started with your camel wool coat", while it is on the table.
    private func startedLine(_ table: StylingTable) -> String? {
        guard let id = startingPieceID, let name = table.pieces.first(where: { $0.id == id })?.name else { return nil }
        return "Started with your \(name.prefix(1).lowercased() + name.dropFirst())"
    }

    /// The season the tray puts first: the first one ticked, or the current one.
    private func traySeason(_ table: StylingTable) -> NamedItem? {
        table.seasons.first { seasons.contains($0.id) } ?? table.currentSeason
    }

    private func trayPieces(_ table: StylingTable) -> (inSeason: [Piece], others: [Piece]) {
        let forSlot = table.pieces.filter { $0.slot == slot.rawValue }
        guard let season = traySeason(table) else { return (forSlot, []) }
        return (forSlot.filter { $0.seasons.contains(season.id) }, forSlot.filter { !$0.seasons.contains(season.id) })
    }

    /// "Your shoes for autumn · 4", or "Your shoes · 6" with no seasons.
    private func trayTitle(_ table: StylingTable, count: Int, all: Int) -> String {
        if all == 0 { return "No \(slot.plural) in your edit yet." }
        guard let season = traySeason(table) else { return "Your \(slot.plural) · \(all)" }
        if count == 0 { return "No \(slot.plural) for \(season.name.lowercased()) yet. Your others:" }
        return "Your \(slot.plural) for \(season.name.lowercased()) · \(count)"
    }

    private func tableDescription(_ table: StylingTable) -> String {
        let names = picked.compactMap { id in table.pieces.first { $0.id == id }?.name }
        return names.isEmpty ? "The styling table, empty" : "On the table: " + names.joined(separator: ", ")
    }

    // MARK: Choosing

    private func items(_ table: StylingTable) -> [FlatLayItem] {
        picked.compactMap { id in
            guard let piece = table.pieces.first(where: { $0.id == id }), let slot = piece.slot.flatMap(Slot.init) else { return nil }
            return FlatLayItem(id: piece.id, slot: slot, path: piece.images.large, isCutout: piece.hasCutout)
        }
    }

    /// Places a piece, or takes it off again. One piece per slot except accessories; a dress
    /// takes the bottom's place, and a bottom the dress's.
    private func toggle(_ piece: Piece) {
        saveError = nil
        if let index = picked.firstIndex(of: piece.id) {
            picked.remove(at: index)
            return
        }
        guard let table, let pieceSlot = piece.slot.flatMap(Slot.init) else { return }
        let slotOf = { (id: Int) in table.pieces.first { $0.id == id }?.slot.flatMap(Slot.init) }
        var replaced: Set<Slot> = pieceSlot.holdsSeveral ? [] : [pieceSlot]
        if pieceSlot == .onePiece { replaced.insert(.bottom) }
        if pieceSlot == .bottom { replaced.insert(.onePiece) }
        picked.removeAll { id in slotOf(id).map(replaced.contains) ?? false }
        picked.append(piece.id)
    }

    private func binding(_ id: Int, in set: Binding<Set<Int>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in
                if on { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }

    /// The first slot in the rail with nothing in it (a dress fills the bottom too).
    private func firstOpenSlot(_ table: StylingTable) -> Slot {
        let filled = Set(picked.compactMap { id in table.pieces.first { $0.id == id }?.slot.flatMap(Slot.init) })
        return Self.rail.first { slot in
            !filled.contains(slot) && !(slot == .bottom && filled.contains(.onePiece)) && !(slot == .onePiece && filled.contains(.bottom))
        } ?? .accessories
    }

    // MARK: Server

    private func load() async {
        do {
            let table = try await store.stylingTable()
            switch start {
            case .empty:
                seasons = Set([table.currentSeason?.id].compactMap { $0 })
            case .piece(let id):
                let piece = table.pieces.first { $0.id == id }
                picked = piece.map { [$0.id] } ?? []
                occasions = Set(piece?.occasions ?? [])
                seasons = Set([table.currentSeason?.id].compactMap { $0 })
            case .look(let look):
                picked = look.pieces.map(\.id).filter { id in table.pieces.contains { $0.id == id } }
                occasions = Set(look.occasions)
                seasons = Set(look.seasons)
            }
            self.table = table
            slot = firstOpenSlot(table)
            loadError = nil
        } catch {
            loadError = store.message(for: error)
        }
    }

    private func save() async {
        guard let table else { return }
        saving = true
        defer { saving = false }
        let draft = LookDraft(
            pieces: picked,
            occasions: table.occasions.map(\.id).filter(occasions.contains),
            seasons: table.seasons.map(\.id).filter(seasons.contains)
        )
        var lookID: Int?
        if case .look(let look) = start { lookID = look.id }
        do {
            let look = try await store.saveLook(draft, lookID: lookID)
            onSaved(look)
            dismiss()
        } catch {
            saveError = store.message(for: error)
        }
    }
}
