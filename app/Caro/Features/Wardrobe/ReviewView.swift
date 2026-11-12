import PhotosUI
import SwiftUI

/// Screen 07, the review queue: one piece at a time, with Caro's suggested details to confirm
/// or change. Confirm counts it towards 20; Mark as maybe counts too; Skip leaves it waiting
/// for next time. Added to the design: Pattern in the Colour row, a Formality row, Remove, and
/// Retake for a photo where nothing lifted.
struct ReviewView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.closeToEdit) private var closeToEdit

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
    /// Screen 09, after the confirm that opened Looks and Get the look.
    @State private var opened: WardrobeProgress?
    /// Style your first look (true) or Go to the edit (false), acted on once screen 09 has closed.
    @State private var openLooksAfter = false

    @FocusState private var nameFocused: Bool

    private var piece: Piece? { pieces.indices.contains(index) ? pieces[index] : nil }

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
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .task {
            await store.loadLists()
            await loadQueue()
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
            if wanted && !UIImagePickerController.isSourceTypeAvailable(.camera) {
                showingRetakeCamera = false
                errorMessage = "This iPhone has no camera. Choose from library instead."
            }
        }
    }

    // MARK: Layout

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close") { closeToEdit() }
                .font(.caroButton)
        }
        ToolbarItem(placement: .principal) {
            Text(pieces.isEmpty ? "Review" : "Review · \(min(index + 1, pieces.count)) of \(pieces.count)")
                .caroLabelStyle()
        }
        ToolbarItem(placement: .topBarTrailing) {
            if piece != nil {
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
                    .padding(.top, 12)

                notes(piece)

                nameField(details)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    row("Category", value: categoryText(details.wrappedValue), sheet: .category)
                    row("Colour", sheet: .colour) { colourValue(details.wrappedValue) }
                    row("Material", value: materialText(details.wrappedValue), sheet: .material)
                    row("Formality", value: details.wrappedValue.formality.map { PieceWords.title($0) }, sheet: .formality)
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

                HStack {
                    Button("Mark as maybe") {
                        Task { await save(as: .maybe) }
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
            Button("Confirm") {
                Task { await save(as: .confirmed) }
            }
            .buttonStyle(.pill)
            .disabled(saving || !canConfirm(details.wrappedValue))
            .bottomButtonBar()
        }
    }

    /// The thin line with "11 of 20" while the wardrobe is still being built.
    @ViewBuilder
    private var progressLine: some View {
        if let progress = store.progress, !progress.unlocked {
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
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Name")
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
            .frame(minHeight: 38)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.lists == nil)
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
        } else {
            pieces.remove(at: index)
            index -= 1
            next()
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
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
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
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
