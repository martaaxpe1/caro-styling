import SwiftUI

/// Screen 15, Your version, with S10 (pieces found) on the same page: the inspiration with
/// numbered pins, then your version as numbered credits. Each credit is the piece Caro saw
/// ("For their grey oversized blazer") and your piece for it, marked Yours or Close; a missing
/// one says "Not in your wardrobe", your nearest piece of that kind and the fact "in 3 of your
/// inspirations", with Mark as key. Each credit opens a native menu: choose one of your pieces,
/// back to Caro's match, mark as key, take it out. Under the credits: occasion, seasons, link and
/// note. Save makes your version a look (From an inspiration), and opens it.
///
/// Caro only describes and compares. You decide every piece, and which missing one is key.
/// T11: marking a piece as key starts the store search for it at once (one tap, one piece);
/// its credit then says how the search is doing, and its menu opens what Caro found.
struct InspirationView: View {
    let inspirationID: Int

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var inspiration: Inspiration?
    /// Your pieces, occasions and seasons, from the styling table.
    @State private var table: StylingTable?
    @State private var errorMessage: String?
    @State private var seasons: Set<Int> = []
    @State private var choosingFor: InspirationPiece?
    @State private var working = false
    @State private var sameLook: (message: String, lookID: Int)?
    @State private var showingSameLook = false
    @State private var confirmingDelete = false
    @State private var editingNote = false
    @State private var editingLink = false
    @State private var draft = ""
    /// A change or a save the server refused, shown in an alert.
    @State private var actionError: String?
    /// Your version folds open and closed.
    @State private var versionOpen = true
    /// The piece whose pin was tapped, shown on the photo.
    @State private var shownPin: Int?

    var body: some View {
        Group {
            if let inspiration, let table {
                content(inspiration, table)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                    Button("Try again") { Task { await load() } }
                        .font(.caroLink)
                }
                .padding(CaroLayout.pageMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ToolbarItem(placement: .principal) {
                Text("Get the look").caroLabelStyle()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(working ? "Saving" : (inspiration?.look == nil ? "Save" : "Update")) { Task { await save() } }
                    .font(.text(15, weight: .semibold, relativeTo: .body))
                    .disabled(!canSave || working)
            }
        }
        .onAppear { Task { await load() } }
        // While Caro reads it, ask again every few seconds.
        .task(id: isBusy) {
            while isBusy, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if let fresh = try? await store.inspiration(inspirationID) { inspiration = fresh }
            }
        }
        .sheet(item: $choosingFor) { piece in
            if let table {
                AddPieceSheet(pieces: table.pieces, listed: Set([piece.piece?.id].compactMap { $0 }), title: "Choose your piece") { chosen in
                    change { try await store.fillInspirationPiece(inspirationID, number: piece.number, piece: chosen.id) }
                }
            }
        }
        .alert(sameLook?.message ?? "", isPresented: $showingSameLook) {
            Button("Open it") {
                if let id = sameLook?.lookID { store.lookToOpen = id }
            }
            Button("OK", role: .cancel) {}
        }
        .alert(actionError ?? "", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .alert("Delete this inspiration?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(inspiration?.look != nil ? "Its pieces leave To find. The look you saved from it stays." : "Its pieces leave To find.")
        }
        .alert("Note", isPresented: $editingNote) {
            TextField("Why you like it", text: $draft)
            Button("Save") { saveDetails(note: draft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Link", isPresented: $editingLink) {
            TextField("https://", text: $draft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { saveDetails(link: draft) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Parts

    private func content(_ inspiration: Inspiration, _ table: StylingTable) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InspirationPhoto(
                    path: inspiration.photo,
                    pins: inspiration.pieces.filter { !$0.removed },
                    caption: inspiration.source.map { "Saved from \($0)" },
                    selected: $shownPin
                )
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 0) {
                    if inspiration.isReading {
                        reading
                    } else if inspiration.notRead {
                        notRead
                    } else {
                        version(inspiration)
                    }
                    details(inspiration, table)
                        .padding(.top, 22)
                    takenOut(inspiration)

                    Button("Delete inspiration") { confirmingDelete = true }
                        .font(.caroLink)
                        .foregroundStyle(Color.terracotta)
                        .underline()
                        .frame(minHeight: CaroLayout.minTouchTarget)
                        .padding(.top, 16)
                        .disabled(working)
                }
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView()
            Text("Caro is reading this look")
                .font(.caroRowTitle)
            Text("It describes each piece and finds your closest. This takes about half a minute.")
                .font(.caroMeta)
                .foregroundStyle(Color.muted)
        }
    }

    private var notRead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Caro could not read this look this time.")
                .font(.caroNote)
                .foregroundStyle(Color.terracotta)
            Button("Try again") {
                change { try await store.readInspirationAgain(inspirationID) }
            }
            .font(.caroLink)
            .underline()
            .frame(minHeight: CaroLayout.minTouchTarget)
        }
    }

    /// "Your *version*", "4 of 5 from your wardrobe", and the credits. The title folds the
    /// credits open and closed.
    @ViewBuilder
    private func version(_ inspiration: Inspiration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { versionOpen.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Your \(Text("version").italic())")
                    .font(.display(28, relativeTo: .title))
                    .caroTitleTracking()
                Image(systemName: "chevron.down")
                    .iconFont(14, weight: .light)
                    .rotationEffect(.degrees(versionOpen ? 0 : -90))
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Text("\(inspiration.owned) of \(inspiration.total) from your wardrobe")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
            .foregroundStyle(Color.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(versionOpen ? "Folds the pieces away" : "Shows the pieces")

        let kept = inspiration.pieces.filter { !$0.removed }
        if !versionOpen {
            EmptyView()
        } else if inspiration.pieces.isEmpty {
            Text("Caro found no pieces in this image.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
                .padding(.top, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(kept) { piece in
                    credit(piece)
                }
            }
            .padding(.top, 12)
        }
    }

    /// "Taken out: grey blazer", with Put back. Under the details.
    @ViewBuilder
    private func takenOut(_ inspiration: Inspiration) -> some View {
        let removed = inspiration.pieces.filter(\.removed)
        if !removed.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(removed) { piece in
                    HStack {
                        Text("Taken out: \(lowercasedFirst(piece.description))")
                            .font(.caroMeta)
                            .foregroundStyle(Color.muted)
                        Spacer(minLength: 8)
                        Button("Put back") {
                            change { try await store.removeInspirationPiece(inspirationID, number: piece.number, removed: false) }
                        }
                        .font(.caroLink)
                        .underline()
                    }
                    .frame(minHeight: CaroLayout.minTouchTarget)
                }
            }
            .padding(.top, 10)
        }
    }

    /// A numbered credit. The row opens a menu of what you can change; a missing piece also has
    /// Mark as key next to it.
    private func credit(_ piece: InspirationPiece) -> some View {
        HStack(spacing: 10) {
            Menu {
                creditMenu(piece)
            } label: {
                HStack(spacing: 10) {
                    Text("\(piece.number)")
                        .font(.display(18, relativeTo: .title3))
                        .frame(minWidth: 22, alignment: .leading)
                    creditTile(piece)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(piece.piece?.name ?? piece.description)
                            .font(.text(14, weight: .medium, relativeTo: .body))
                            .foregroundStyle(piece.isMissing ? Color.terracotta : Color.ink)
                        ForEach(subLines(piece), id: \.self) { line in
                            Text(line)
                                .font(.caroMeta)
                                .foregroundStyle(piece.toFind?.searchStatus == "failed" && line == piece.toFind?.words ? Color.terracotta : Color.muted)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if !piece.isMissing {
                        matchLabel(piece)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(working)
            .accessibilityHint("Shows what you can change")

            if piece.isMissing {
                keyButton(piece)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private func creditMenu(_ piece: InspirationPiece) -> some View {
        Button(piece.isMissing ? "Choose one of your pieces" : "Choose another of your pieces", systemImage: "square.grid.2x2") {
            choosingFor = piece
        }
        if piece.match == "filled" {
            Button("Back to Caro's match", systemImage: "arrow.uturn.backward") {
                change { try await store.fillInspirationPiece(inspirationID, number: piece.number, piece: nil) }
            }
        }
        if let toFind = piece.toFind {
            Button("See what Caro found", systemImage: "bag") {
                store.toFindToOpen = toFind.id
            }
        }
        if piece.isMissing {
            Button(piece.key ? "Not key" : "Mark as key", systemImage: piece.key ? "star.slash" : "star") {
                change { try await store.markInspirationPiece(inspirationID, number: piece.number, key: !piece.key) }
            }
        }
        Button("Take out of your version", systemImage: "minus.circle", role: .destructive) {
            change { try await store.removeInspirationPiece(inspirationID, number: piece.number, removed: true) }
        }
    }

    /// "For their grey oversized blazer"; for a missing piece: "Not in your wardrobe · in 3 of
    /// your inspirations" and "Your nearest: black knit jumper".
    private func subLines(_ piece: InspirationPiece) -> [String] {
        guard piece.isMissing else { return ["For their \(lowercasedFirst(piece.description))"] }
        var first = "Not in your wardrobe"
        if let count = piece.inspirations { first += " · in \(count) of your inspirations" }
        var lines = [first]
        if let nearest = piece.nearest?.name { lines.append("Your nearest: \(lowercasedFirst(nearest))") }
        // A key piece: how the store search is doing (T11).
        if let search = piece.toFind { lines.append(search.words) }
        return lines
    }

    private func creditTile(_ piece: InspirationPiece) -> some View {
        Group {
            if let own = piece.piece {
                PieceImage(path: own.images.thumb, isCutout: own.hasCutout)
                    .padding(4)
                    .frame(width: 48, height: 48)
                    .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
            } else {
                RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                    .strokeBorder(Color.terracotta, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 48, height: 48)
            }
        }
        .accessibilityHidden(true)
    }

    /// A dot and YOURS or CLOSE, in label style.
    private func matchLabel(_ piece: InspirationPiece) -> some View {
        let close = piece.match == "close"
        return HStack(spacing: 6) {
            Circle()
                .fill(close ? Color.seasonSand : Color.ink)
                .frame(width: 7, height: 7)
            Text(close ? "Close" : "Yours")
                .font(.text(11, relativeTo: .caption))
                .textCase(.uppercase)
                .tracking(11 * 0.12)
                .foregroundStyle(Color.muted)
        }
        .fixedSize()
    }

    /// Mark as key: a small outlined terracotta pill; once key, filled, saying Key.
    private func keyButton(_ piece: InspirationPiece) -> some View {
        Button {
            change { try await store.markInspirationPiece(inspirationID, number: piece.number, key: !piece.key) }
        } label: {
            Text(piece.key ? "Key" : "Mark as key")
                .font(.text(13, weight: .semibold, relativeTo: .subheadline))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(piece.key ? Color.onInk : Color.terracotta)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(Capsule().fill(piece.key ? Color.terracotta : Color.clear))
                .overlay(Capsule().strokeBorder(Color.terracotta, lineWidth: 1))
                .frame(minHeight: CaroLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working)
        .accessibilityLabel(piece.key ? "Key piece, on To find" : "Mark as key")
        .accessibilityHint(piece.key ? "Takes it off To find" : "Puts it on To find")
    }

    /// Your look (once saved), occasion, seasons, link and note.
    private func details(_ inspiration: Inspiration, _ table: StylingTable) -> some View {
        VStack(spacing: 0) {
            if let look = inspiration.look, let number = look.number {
                DetailRow(label: "Your look") {
                    Button {
                        store.lookToOpen = look.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(inProgress(inspiration) ? "No. \(number) · In progress" : "No. \(number)")
                                .foregroundStyle(Color.ink)
                            Image(systemName: "chevron.right")
                                .iconFont(12, weight: .light)
                                .foregroundStyle(Color.muted)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            DetailRow(label: "Occasion") {
                Menu {
                    Picker("Occasion", selection: Binding(
                        get: { inspiration.occasion },
                        set: { value in saveDetails(occasion: .some(value)) }
                    )) {
                        Text("None").tag(Int?.none)
                        ForEach(table.occasions) { occasion in
                            Text(occasion.name).tag(Int?.some(occasion.id))
                        }
                    }
                } label: {
                    menuValue(table.occasions.first { $0.id == inspiration.occasion }?.name)
                }
            }
            if !table.seasons.isEmpty {
                DetailRow(label: "Seasons") {
                    Menu {
                        ForEach(table.seasons) { season in
                            Toggle(season.name, isOn: Binding(
                                get: { seasons.contains(season.id) },
                                set: { on in if on { seasons.insert(season.id) } else { seasons.remove(season.id) } }
                            ))
                        }
                    } label: {
                        menuValue(seasonText(table))
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            }
            DetailRow(label: "Link") {
                HStack(spacing: 10) {
                    if let link = inspiration.link, let url = URL(string: link) {
                        Link(inspiration.source ?? "Open", destination: url)
                            .foregroundStyle(Color.ink)
                            .underline()
                    }
                    Button(inspiration.link == nil ? "Add" : "Change") {
                        draft = inspiration.link ?? ""
                        editingLink = true
                    }
                    .foregroundStyle(inspiration.link == nil ? Color.ink : Color.muted)
                }
            }
            DetailRow(label: "Note") {
                Button {
                    draft = inspiration.note ?? ""
                    editingNote = true
                } label: {
                    Text(inspiration.note ?? "Add")
                        .foregroundStyle(Color.ink)
                        .lineLimit(3)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    /// Pieces still missing in your version: the look is in progress.
    /// Caro is reading the inspiration, or searching the stores for a key piece: ask again
    /// every few seconds.
    private var isBusy: Bool {
        guard let inspiration else { return false }
        return inspiration.isReading || inspiration.pieces.contains { $0.toFind?.searchStatus == "searching" }
    }

    private func inProgress(_ inspiration: Inspiration) -> Bool {
        inspiration.pieces.contains { !$0.removed && $0.isMissing }
    }

    private func menuValue(_ text: String?) -> some View {
        HStack(spacing: 4) {
            Text(text ?? "None yet")
                .foregroundStyle(text == nil ? Color.muted : Color.ink)
            Image(systemName: "chevron.up.chevron.down")
                .iconFont(11, weight: .light)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
        }
    }

    private func seasonText(_ table: StylingTable) -> String? {
        let names = table.seasons.filter { seasons.contains($0.id) }.map(\.name)
        guard let first = names.first else { return nil }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }

    private func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    // MARK: Server

    /// Your version can be saved as soon as Caro has read it, even with pieces still missing:
    /// the look is then in progress.
    private var canSave: Bool {
        guard let inspiration else { return false }
        return inspiration.status == "ready"
    }

    private func load() async {
        do {
            async let one = store.inspiration(inspirationID)
            async let tableAnswer = store.stylingTable()
            let (fresh, freshTable) = try await (one, tableAnswer)
            if table == nil {
                seasons = Set([freshTable.currentSeason?.id].compactMap { $0 })
            }
            inspiration = fresh
            table = freshTable
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    /// Runs one change on the server and shows the inspiration it answers with.
    private func change(_ request: @escaping () async throws -> Inspiration) {
        Task {
            working = true
            defer { working = false }
            do {
                inspiration = try await request()
            } catch {
                actionError = store.message(for: error)
            }
        }
    }

    private func saveDetails(link: String? = nil, note: String? = nil, occasion: Int?? = nil) {
        guard let inspiration else { return }
        let newLink = link.map { $0.trimmingCharacters(in: .whitespaces) }.map { $0.isEmpty ? nil : $0 } ?? inspiration.link
        let newNote = note.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.map { $0.isEmpty ? nil : $0 } ?? inspiration.note
        let newOccasion = occasion ?? inspiration.occasion
        change { try await store.updateInspiration(inspiration, link: newLink, note: newNote, occasion: newOccasion) }
    }

    private func delete() async {
        working = true
        defer { working = false }
        do {
            try await store.deleteInspiration(inspirationID)
            dismiss()
        } catch {
            actionError = store.message(for: error)
        }
    }

    private func save() async {
        guard let inspiration else { return }
        working = true
        defer { working = false }
        do {
            let look = try await store.saveInspirationLook(
                inspiration.id,
                occasions: [inspiration.occasion].compactMap { $0 },
                seasons: (table?.seasons ?? []).map(\.id).filter(seasons.contains)
            )
            store.lookToOpen = look.id
        } catch APIError.sameLook(let message, let lookID, _) {
            sameLook = (message: message, lookID: lookID)
            showingSameLook = true
        } catch {
            actionError = store.message(for: error)
        }
    }
}
