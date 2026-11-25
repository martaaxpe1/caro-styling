import PhotosUI
import SwiftUI

/// Screen 07, the review queue: one piece at a time, with Caro's suggested details to confirm
/// or change. Confirm counts it towards 20; Mark as maybe counts too; Skip leaves it waiting
/// for next time. Added to the design: Pattern in the Colour row, a Formality row, Remove,
/// Retake for a photo where nothing lifted, and turning a photo taken sideways. T13 adds the
/// Doesn't fit yet row, also in Edit. T14 adds the note for a piece that looks like one you already
/// have: Same piece compares the two photos (S12), Different piece is remembered, and Confirm and
/// Mark as maybe ask the same question first.
///
/// The same screen is Edit on the piece page (screen 11, `editing`): change the details and
/// Save, with Brand and Notes added. Mark as maybe and Remove live on the piece page then.
struct ReviewView: View {
    /// A piece opened from the edit. Nil: the review queue.
    var editing: Piece?

    @Environment(WardrobeStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.closeToEdit) private var closeToEdit
    @Environment(\.dismiss) private var dismiss

    /// The pieces to review in this visit, in order. Skipped ones are not asked again until next time.
    @State private var pieces: [Piece] = []
    @State private var index = 0
    @State private var details: PieceDetails?
    @State private var loaded = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var sheet: DetailSheet?
    @State private var confirmingRemove = false
    @State private var showingRetakeLibrary = false
    @State private var showingRetakeCamera = false
    @State private var retakeItem: PhotosPickerItem?
    @State private var retakeCameraOpen = false
    @State private var showingCameraRefused = false
    /// Screen 09, after the confirm that opened Looks and Get the look.
    @State private var opened: WardrobeProgress?
    /// Style your first look (true) or Go to the edit (false), acted on once screen 09 has closed.
    @State private var openLooksAfter = false

    /// Same piece: the piece being compared on S12.
    @State private var comparing: Piece.LooksLike?
    /// S12 ended with a photo kept: the new piece is gone, on to the next.
    @State private var joined = false
    /// Confirm or Mark as maybe, waiting for the answer about the piece it looks like.
    @State private var saveAfterAnswer: Piece.Status?
    @State private var askingSame = false

    @FocusState private var nameFocused: Bool

    private var piece: Piece? { pieces.indices.contains(index) ? pieces[index] : nil }
    private var isEditing: Bool { editing != nil }

    var body: some View {
        Group {
            if let piece, let details = Binding($details) {
                content(piece: piece, details: details)
            } else if loaded {
                emptyQueue
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        // A piece opened from a chapter is pushed: the usual back arrow (and swipe) returns to it.
        .navigationBarBackButtonHidden(!isEditing)
        .toolbar { toolbar }
        .navigationBarTitleDisplayMode(.inline)
        .paperBar()
        .task {
            await store.loadLists()
            if let editing {
                // The queue's answer also carries the member's seasons and occasions, for the chips.
                await store.refreshQueue()
                pieces = [editing]
                loaded = true
                show()
            } else {
                await loadQueue()
            }
        }
        .sheet(item: $sheet) { sheet in
            if let lists = store.lists, details != nil {
                DetailPicker(sheet: sheet, lists: lists, details: Binding($details)!) { warmth in
                    proposeSeasons(for: warmth)
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } }),
            onDismiss: {
                // Once screen 09 has closed: the app learns Looks and Get the look are open,
                // goes back to the edit, and opens Looks if that was the choice.
                let openLooks = openLooksAfter
                let store = store
                let session = session
                let closeToEdit = closeToEdit
                Task {
                    await session.refresh()
                    closeToEdit()
                    store.openLooksNext = openLooks
                }
            }
        ) {
            WardrobeOpenView(pieces: opened?.pieces ?? 20) { openLooks in
                openLooksAfter = openLooks
                opened = nil
            }
        }
        .sheet(item: $comparing, onDismiss: {
            guard joined else { return }
            joined = false
            Task { await goOnAfterJoining() }
        }) { other in
            whichPhoto(other)
        }
        .alert("The same piece?", isPresented: $askingSame, presenting: piece?.looksLike) { other in
            Button("Same piece") { comparing = other }
            Button("Different piece") {
                let status = saveAfterAnswer
                Task { await different(thenSave: status) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { other in
            Text(lookalikeLine(other))
        }
        .alert("Remove this piece?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its photos are deleted too.")
        }
        .photosPicker(isPresented: $showingRetakeLibrary, selection: $retakeItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: retakeItem) { _, item in
            guard let item else { return }
            retakeItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                await retake(with: data)
            }
        }
        .onChange(of: showingRetakeCamera) { _, wanted in
            guard wanted else { return }
            showingRetakeCamera = false
            Task {
                switch await CameraAccess.ask() {
                case .allowed: retakeCameraOpen = true
                case .refused: showingCameraRefused = true
                case .noCamera: errorMessage = "This iPhone has no camera. Choose from library instead."
                }
            }
        }
        .fullScreenCover(isPresented: $retakeCameraOpen) {
            CameraView(single: true) { file in
                Task { await retake(with: file) }
            } done: { _ in
                retakeCameraOpen = false
            }
            .ignoresSafeArea()
        }
        .cameraRefusedAlert(isPresented: $showingCameraRefused)
    }

    // MARK: Layout

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if !isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { closeToEdit() }
                    .font(.caroButton)
            }
        }
        ToolbarItem(placement: .principal) {
            Text(isEditing ? "Edit piece" : pieces.isEmpty ? "Review" : "Review · \(min(index + 1, pieces.count)) of \(pieces.count)")
                .caroLabelStyle()
        }
        ToolbarItem(placement: .topBarTrailing) {
            if piece != nil && !isEditing {
                Button("Skip") { next() }
                    .font(.caroButton)
                    .disabled(saving)
            }
        }
    }

    private func content(piece: Piece, details: Binding<PieceDetails>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                progressLine

                RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                    .fill(Color.tile)
                    .frame(height: 196)
                    .overlay {
                        PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout, shadow: .large)
                            .padding(piece.hasCutout ? 14 : 8)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        // For a photo taken sideways: each tap turns it a quarter turn.
                        Button {
                            Task { await rotate() }
                        } label: {
                            Image(systemName: "rotate.right")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.ink)
                                .frame(width: 36, height: 36)
                                .background(Color.paper, in: Circle())
                                .frame(width: CaroLayout.minTouchTarget, height: CaroLayout.minTouchTarget)
                                .contentShape(Rectangle())
                        }
                        .disabled(saving)
                        .padding(4)
                        .accessibilityLabel("Turn the photo")
                    }
                    .padding(.top, 12)

                notes(piece)

                nameField(details)
                    .padding(.top, 12)

                if !isEditing, let other = piece.looksLike {
                    lookalikeNote(other)
                        .padding(.top, 12)
                }

                VStack(spacing: 0) {
                    row("Category", value: categoryText(details.wrappedValue), sheet: .category)
                    row("Colour", sheet: .colour) { colourValue(details.wrappedValue) }
                    row("Material", value: materialText(details.wrappedValue), sheet: .material)
                    row("Formality", value: details.wrappedValue.formality.map { PieceWords.title($0) }, sheet: .formality)
                    fitRow(details)
                    if isEditing {
                        brandField(details)
                    }
                }
                .padding(.top, 6)

                if let queue = store.queue {
                    chips(
                        "Seasons",
                        note: queue.seasons.isEmpty ? "You have no seasons" : "From its warmth and your year",
                        items: queue.seasons,
                        selected: details.seasons
                    )
                    chips("Occasions", note: "You choose", items: queue.occasions, selected: details.occasions)
                }

                if isEditing {
                    notesField(details)
                }

                if !isEditing {
                    HStack {
                        Button("Mark as maybe") {
                            confirm(as: .maybe)
                        }
                        Spacer()
                        Button("Remove") { confirmingRemove = true }
                    }
                    .font(.caroLink)
                    .foregroundStyle(Color.terracotta)
                    .underline()
                    .frame(minHeight: CaroLayout.minTouchTarget)
                    .padding(.top, 6)
                    .disabled(saving)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(isEditing ? "Save" : "Confirm") {
                // Save keeps a piece opened from the edit as it was: confirmed or maybe.
                confirm(as: isEditing ? piece.status : .confirmed)
            }
            .buttonStyle(.pill)
            .disabled(saving || !canConfirm(details.wrappedValue))
            .bottomButtonBar()
        }
    }

    /// The thin line with "11 of 20" while the wardrobe is still being built.
    @ViewBuilder
    private var progressLine: some View {
        if let progress = store.progress, !progress.unlocked, !isEditing {
            HStack(spacing: 10) {
                ProgressBar(fraction: Double(progress.pieces) / Double(max(progress.needed, 1)), height: 2)
                Text("\(progress.pieces) of \(progress.needed)")
                    .font(.text(11, relativeTo: .caption))
                    .foregroundStyle(Color.muted)
            }
            .padding(.top, 4)
        }
    }

    /// When nothing lifted, or Claude could not read the photo.
    @ViewBuilder
    private func notes(_ piece: Piece) -> some View {
        if !piece.hasCutout {
            HStack(spacing: 6) {
                Text("Nothing lifted from this photo.")
                    .foregroundStyle(Color.muted)
                Menu {
                    Button("Take photo", systemImage: "camera") { showingRetakeCamera = true }
                    Button("Choose from library", systemImage: "photo.on.rectangle") { showingRetakeLibrary = true }
                } label: {
                    Text("Retake")
                        .font(.caroLink)
                        .foregroundStyle(Color.terracotta)
                        .underline()
                }
            }
            .font(.caroNote)
            .padding(.top, 8)
        }
        if piece.detailsStatus == .notRead {
            Text("Caro could not read the details of this photo. Fill them in.")
                .font(.caroNote)
                .foregroundStyle(Color.terracotta)
                .padding(.top, 8)
        }
    }

    private func nameField(_ details: Binding<PieceDetails>) -> some View {
        TextField("Name", text: details.name, prompt: fieldPrompt("Name this piece"))
            .focused($nameFocused)
            .submitLabel(.done)
            .padding(.trailing, 28)
            .underlinedField(font: .display(24, relativeTo: .title2))
            .overlay(alignment: .trailing) {
                Image(systemName: "pencil")
                    .iconFont(16, weight: .light)
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Name")
    }

    /// Already in the edit (T14): the piece it looks like, with its picture, and the two answers.
    private func lookalikeNote(_ other: Piece.LooksLike) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                comparing = other
            } label: {
                PieceImage(path: other.images.thumb, isCutout: other.hasCutout)
                    .padding(6)
                    .frame(width: 64, height: 72)
                    .background(Color.paper, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compare the photos")

            VStack(alignment: .leading, spacing: 0) {
                Text(lookalikeLine(other))
                    .font(.caroBody)
                    .fixedSize(horizontal: false, vertical: true)
                // On one line; under each other when the text is large.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { lookalikeAnswers(other) }
                    VStack(alignment: .leading, spacing: 0) { lookalikeAnswers(other) }
                }
                .font(.caroLink)
                .foregroundStyle(Color.terracottaOnTile)
                .underline()
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        .disabled(saving)
    }

    @ViewBuilder
    private func lookalikeAnswers(_ other: Piece.LooksLike) -> some View {
        Button("Same piece") { comparing = other }
            .frame(minHeight: CaroLayout.minTouchTarget)
        Button("Different piece") {
            Task { await different(thenSave: nil) }
        }
        .frame(minHeight: CaroLayout.minTouchTarget)
    }

    /// S12 for a piece in the review: the one you have, and this new one.
    @ViewBuilder
    private func whichPhoto(_ other: Piece.LooksLike) -> some View {
        if let piece {
            WhichPhotoView(
                name: other.name ?? piece.name ?? "",
                old: ComparePhoto(title: other.waiting ? "Waiting for review" : "In the edit", path: other.images.large, isCutout: other.hasCutout),
                new: ComparePhoto(title: "New", path: piece.images.large, isCutout: piece.hasCutout),
                different: { Task { await different(thenSave: nil) } },
                choose: { choice in
                    do {
                        _ = try await store.same(piece.id, as: other.id, photo: choice)
                        joined = true
                        return nil
                    } catch {
                        return store.message(for: error)
                    }
                }
            )
        }
    }

    /// Edit only: the brand, typed, on a details row.
    private func brandField(_ details: Binding<PieceDetails>) -> some View {
        HStack {
            Text("Brand")
                .font(.caroLabel)
                .textCase(.uppercase)
                .tracking(11 * 0.14)
                .foregroundStyle(Color.muted)
            Spacer()
            TextField("Brand", text: details.brand, prompt: fieldPrompt("Add a brand"))
                .font(.caroBody)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onChange(of: details.wrappedValue.brand) { _, brand in
                    if brand.count > 40 { details.wrappedValue.brand = String(brand.prefix(40)) }
                }
        }
        .padding(.vertical, 6) // Room above and below when the text is large; no change at the normal size.
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    /// Edit only: a short free note, up to 280 letters.
    private func notesField(_ details: Binding<PieceDetails>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caroLabel)
                .textCase(.uppercase)
                .tracking(11 * 0.14)
                .foregroundStyle(Color.muted)
            TextField("Notes", text: details.notes, prompt: fieldPrompt("Where it is from, how it fits"), axis: .vertical)
                .font(.caroBody)
                .lineLimit(2...5)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .onChange(of: details.wrappedValue.notes) { _, notes in
                    if notes.count > 280 { details.wrappedValue.notes = String(notes.prefix(280)) }
                }
        }
        .padding(.top, 18)
    }

    private func row(_ label: String, value: String?, sheet: DetailSheet) -> some View {
        row(label, sheet: sheet) {
            Text(value ?? "Choose")
                .foregroundStyle(value == nil ? Color.terracotta : Color.ink)
        }
    }

    private func row<Value: View>(_ label: String, sheet: DetailSheet, @ViewBuilder value: () -> Value) -> some View {
        Button {
            nameFocused = false
            self.sheet = sheet
        } label: {
            HStack {
                Text(label)
                    .font(.caroLabel)
                    .textCase(.uppercase)
                    .tracking(11 * 0.14)
                    .foregroundStyle(Color.muted)
                Spacer()
                value()
                    .font(.caroBody)
            }
            .padding(.vertical, 6) // Room above and below when the text is large; no change at the normal size.
            .frame(minHeight: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.lists == nil)
    }

    /// Doesn't fit yet, with a round tick: off for a new piece.
    private func fitRow(_ details: Binding<PieceDetails>) -> some View {
        let on = !details.wrappedValue.fits
        return Button {
            nameFocused = false
            details.wrappedValue.fits.toggle()
        } label: {
            HStack {
                Text(FitDot.words)
                    .font(.caroLabel)
                    .textCase(.uppercase)
                    .tracking(11 * 0.14)
                    .foregroundStyle(Color.muted)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .iconFont(20, weight: .light)
                    .foregroundStyle(on ? Color.ink : Color.outline)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func colourValue(_ details: PieceDetails) -> some View {
        HStack(spacing: 6) {
            if details.colours.isEmpty {
                Text("Choose")
                    .foregroundStyle(Color.terracotta)
            } else {
                ForEach(details.colours, id: \.self) { ColourSwatch(colour: $0) }
                Text(colourText(details))
            }
        }
    }

    private func chips(_ label: String, note: String, items: [NamedItem], selected: Binding<[Int]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caroLabel)
                    .textCase(.uppercase)
                    .tracking(11 * 0.14)
                    .foregroundStyle(Color.muted)
                Spacer()
                Text(note)
                    .font(.text(11, relativeTo: .caption))
                    .foregroundStyle(Color.muted)
            }
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    let isOn = selected.wrappedValue.contains(item.id)
                    Chip(title: item.name, isOn: isOn) {
                        if isOn {
                            selected.wrappedValue.removeAll { $0 == item.id }
                        } else {
                            selected.wrappedValue.append(item.id)
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private var emptyQueue: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Nothing to review just now.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
            Button("Back to the edit") { closeToEdit() }
                .buttonStyle(.pillOutlined)
                .padding(.horizontal, CaroLayout.pageMargin)
            Spacer()
        }
    }

    // MARK: Words

    /// "This looks like your green quilted jacket, already in the edit."
    private func lookalikeLine(_ other: Piece.LooksLike) -> String {
        let place = other.waiting ? "also waiting for review" : "already in the edit"
        guard let name = other.name, !name.isEmpty else { return "This looks like another of your pieces, \(place)." }
        return "This looks like your \(name.prefix(1).lowercased() + name.dropFirst()), \(place)."
    }

    private func categoryText(_ details: PieceDetails) -> String? {
        guard let kind = details.kind else { return nil }
        let chapter = store.lists?.chapter(of: kind).map { ChapterWords.title($0.name) }
        return [chapter, PieceWords.title(kind)].compactMap { $0 }.joined(separator: " · ")
    }

    private func colourText(_ details: PieceDetails) -> String {
        let colours = details.colours.map { PieceWords.title($0) }.joined(separator: ", ")
        guard let pattern = details.pattern, pattern != "plain" else { return colours }
        return "\(colours) · \(PieceWords.title(pattern))"
    }

    private func materialText(_ details: PieceDetails) -> String? {
        let parts = [details.material, details.warmth].compactMap { $0 }.map { PieceWords.title($0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func canConfirm(_ details: PieceDetails) -> Bool {
        !details.name.trimmingCharacters(in: .whitespaces).isEmpty && details.kind != nil
    }

    // MARK: Actions

    private func loadQueue() async {
        await store.refreshQueue()
        let seen = Set(pieces.map(\.id))
        let ready = (store.queue?.pieces ?? []).filter { $0.detailsStatus != .reading && !seen.contains($0.id) }
        pieces += ready
        loaded = true
        show()
    }

    /// Fills the screen with the current piece's details.
    private func show() {
        details = piece.map { PieceDetails(from: $0) }
        errorMessage = nil
    }

    private func next() {
        index += 1
        if index < pieces.count {
            show()
        } else {
            // The end of the line: pieces read meanwhile join it; otherwise back to the edit.
            Task {
                await loadQueue()
                if index >= pieces.count {
                    closeToEdit()
                }
            }
        }
    }

    private func proposeSeasons(for warmth: String) {
        details?.seasons = store.queue?.seasonsByWarmth[warmth] ?? []
    }

    /// Confirm, Mark as maybe or Save. A new piece that looks like one you have asks about that first.
    private func confirm(as status: Piece.Status) {
        nameFocused = false
        if !isEditing, piece?.looksLike != nil {
            saveAfterAnswer = status
            askingSame = true
        } else {
            Task { await save(as: status) }
        }
    }

    /// Different piece: remembered on the server, which says what it may look like next, if anything.
    /// From Confirm or Mark as maybe, the piece is saved once there is nothing left to ask.
    private func different(thenSave status: Piece.Status?) async {
        guard let piece, let other = piece.looksLike, !saving else { return }
        saving = true
        errorMessage = nil
        do {
            pieces[index] = try await store.different(piece.id, from: other.id)
            saving = false
            if let status { confirm(as: status) }
        } catch {
            saving = false
            errorMessage = store.message(for: error)
        }
    }

    /// The new piece is gone. Others in line may have been asking about it, or about a photo that
    /// changed: they are shown as the server has them now.
    private func goOnAfterJoining() async {
        saving = true
        pieces.remove(at: index)
        await store.refreshQueue()
        if let queue = store.queue {
            let latest = Dictionary(uniqueKeysWithValues: queue.pieces.map { ($0.id, $0) })
            pieces = pieces.enumerated().compactMap { place, piece in
                place < index ? piece : latest[piece.id]
            }
        }
        index -= 1
        saving = false
        next()
    }

    private func save(as status: Piece.Status) async {
        guard let piece, var details, !saving else { return }
        details.status = status
        nameFocused = false
        saving = true
        defer { saving = false }
        do {
            let saved = try await store.save(piece.id, details: details)
            if saved.justUnlocked {
                opened = saved.progress
            } else if isEditing {
                dismiss()
            } else {
                next()
            }
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func remove() async {
        guard let piece else { return }
        saving = true
        defer { saving = false }
        if let failed = await store.remove(piece) {
            errorMessage = failed
        } else if isEditing {
            dismiss()
        } else {
            pieces.remove(at: index)
            index -= 1
            next()
        }
    }

    /// Turns the piece's pictures a quarter turn clockwise, on the server.
    private func rotate() async {
        guard let piece, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            pieces[index] = try await store.rotate(piece.id)
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func retake(with data: Data) async {
        guard let piece else { return }
        saving = true
        defer { saving = false }
        do {
            let retaken = try await store.retake(piece.id, photoFile: data)
            pieces[index] = retaken
        } catch {
            errorMessage = store.message(for: error)
        }
    }
}

/// Lays out chips in rows, wrapping to the next line when a row is full.
///
/// SwiftUI asks twice: how much room the chips need (sizeThatFits), then to put them there
/// (placeSubviews). Both get the rows from `arrange`, so they always agree and a chip never
/// lands on a row that was not reserved.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // The width on offer (the proposal), not bounds: bounds is only as wide as the chips, and
        // its left edge can be off by a hair, enough to push the last chip to a new row.
        let places = arrange(subviews, width: proposal.width).places
        for (subview, place) in zip(subviews, places) {
            subview.place(
                at: CGPoint(x: bounds.minX + place.minX, y: bounds.minY + place.minY),
                proposal: ProposedViewSize(place.size)
            )
        }
    }

    /// Where each chip goes, counted from the top left corner of the layout, and the size of all of them.
    private func arrange(_ subviews: Subviews, width: CGFloat?) -> (places: [CGRect], size: CGSize) {
        let width = width ?? .infinity
        var places: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            places.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            widest = max(widest, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (places, CGSize(width: min(widest, width), height: y + rowHeight))
    }
}
