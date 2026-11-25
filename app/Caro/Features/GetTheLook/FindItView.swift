import SwiftUI

/// S11, Find it (T11, to design): what Caro found in your stores for one key piece.
///
/// The piece's name and its inspiration, then up to five products: the store's picture on the
/// tile colour, the name, the store and the price in your currency. Tap a product to open its
/// page in Safari inside the app. Keep or discard it with the heart and the cross next to it,
/// or swipe right or left (as in Mail); the same choices are in a touch-and-hold menu.
/// While Caro searches, each store shows how it is doing, and products appear as stores answer.
/// "Searched for" shows the words used, with Change; when nothing is found, they open to edit. Kept products come first, with Bought, which adds
/// the piece to your edit with the store's picture, cropped. "Nothing found" is a valid answer.
/// Stores Caro could not search are listed. Search again is a small outlined pill.
///
/// Caro searches only on your tap, for this one piece, in your stores. It never recommends.
struct FindItView: View {
    let toFindID: Int

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page: FindItPage?
    @State private var errorMessage: String?
    @State private var working = false
    @State private var webPage: WebPage?
    @State private var buying: StoreResult?
    @State private var confirmingDrop = false
    @State private var editingWords = false
    @State private var wordsDraft = ""
    @FocusState private var wordsFocused: Bool

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
        .paperBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let page, !page.isBought {
                    Menu {
                        Button("No longer looking", systemImage: "xmark.circle", role: .destructive) { confirmingDrop = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .iconFont(16)
                            .frame(minWidth: CaroLayout.minTouchTarget, minHeight: CaroLayout.minTouchTarget)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .onAppear { Task { await load() } }
        .refreshable { await load() }
        // While Caro searches, ask again every few seconds.
        .task(id: page?.isSearching) {
            while page?.isSearching == true, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await load()
            }
        }
        .sheet(item: $webPage) { page in
            SafariView(url: page.url)
                .ignoresSafeArea()
        }
        .sheet(item: $buying) { result in
            if let image = result.image {
                CropView(imagePath: image, productName: result.name) { picture in
                    await bought(result, picture: picture)
                }
            }
        }
        .alert("No longer looking for it?", isPresented: $confirmingDrop) {
            Button("Take off To find", role: .destructive) { Task { await drop() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stays missing in your version, and you can mark it as key again.")
        }
    }

    // MARK: Page

    private func content(_ page: FindItPage) -> some View {
        List {
            header(page)
                .plainRow(separator: false)

            if page.isBought {
                boughtNote(page)
                    .plainRow(separator: false)
            }

            if let progress = page.progress {
                progressBlock(progress)
                    .padding(.top, 14)
                    .plainRow(separator: false)
            }

            if !page.isBought {
                wordsBlock(page)
                    .padding(.top, 14)
                    .plainRow(separator: false)
            }

            if !page.results.isEmpty {
                if !page.isBought {
                    Text("Tap a product to see it in the store. Keep it or discard it with the buttons, or swipe right or left.")
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                        .plainRow(separator: false)
                }
                ForEach(page.results) { result in
                    productRow(result, page: page)
                        .plainRow(separator: true)
                }
            }

            if !page.notSearched.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(page.notSearched, id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.caroMeta)
                .foregroundStyle(Color.muted)
                .padding(.top, 16)
                .plainRow(separator: false)
            }

            if !page.isBought && !showsWordsField(page) {
                searchButton(page)
                    .padding(.top, 18)
                    .plainRow(separator: false)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caroNote)
                    .foregroundStyle(Color.terracotta)
                    .padding(.top, 8)
                    .plainRow(separator: false)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    /// FIND IT, the piece's name, its inspiration, and how the search is doing.
    private func header(_ page: FindItPage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Find it")
                    .caroLabelStyle()
                Text(page.description)
                    .font(.display(28, relativeTo: .title))
                    .fixedSize(horizontal: false, vertical: true)
                statusLine(page)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            // A button, not a link: a link inside a list gets a chevron.
            Button {
                store.inspirationToOpen = page.inspiration.id
            } label: {
                LookPhotoImage(path: page.inspiration.thumb)
                    .frame(width: 60, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open its inspiration")
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func statusLine(_ page: FindItPage) -> some View {
        switch page.searchStatus {
        case "searching":
            Text("Searching \(page.stores.count == 1 ? "your store" : "your \(page.stores.count) stores"), each on its own. This takes up to a minute.")
                .font(.caroNote)
                .foregroundStyle(Color.muted)
        case "failed":
            Text(page.searchMessage ?? "Caro could not search your stores just now. Try again.")
                .font(.caroNote)
                .foregroundStyle(Color.terracotta)
        case "done":
            Text(foundLine(page))
                .font(.caroNote)
                .foregroundStyle(Color.muted)
        default:
            Text("Not searched yet.")
                .font(.caroNote)
                .foregroundStyle(Color.muted)
        }
    }

    /// When the search ran: "Searched your 7 stores on 12 Nov." With products, a reminder that
    /// the store's price and stock can have changed since.
    private func foundLine(_ page: FindItPage) -> String {
        let stores = page.stores.count == 1 ? "your store" : "your \(page.stores.count) stores"
        var line = "Searched \(stores)"
        if let date = page.searchedAt {
            line += " on " + date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_\(page.country ?? "US")")))
        }
        line += "."
        if !page.results.isEmpty { line += " Prices and stock may have changed since." }
        return line
    }

    /// Each store while Caro searches: a spinner, then how many it found, or that it did not answer.
    private func progressBlock(_ progress: [StoreProgress]) -> some View {
        VStack(spacing: 0) {
            ForEach(progress, id: \.store) { item in
                HStack(spacing: 10) {
                    Group {
                        switch item.status {
                        case "searching": ProgressView().controlSize(.small)
                        case "failed": Image(systemName: "xmark").foregroundStyle(Color.terracotta)
                        default: Image(systemName: "checkmark").foregroundStyle(Color.ink)
                        }
                    }
                    .iconFont(12, weight: .medium)
                    .frame(width: 18)
                    Text(item.store)
                        .font(.caroBody)
                    Spacer()
                    Text(progressWords(item))
                        .font(.caroMeta)
                        .foregroundStyle(item.status == "failed" ? Color.terracotta : Color.muted)
                }
                .frame(minHeight: 32)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.default, value: progress)
    }

    private func progressWords(_ item: StoreProgress) -> String {
        switch item.status {
        case "searching": return "Searching"
        case "failed": return "Did not answer"
        default: return item.found == 0 ? "Nothing found" : "\(item.found) found"
        }
    }

    /// The words to change are open when you asked, or when the search found nothing.
    private func showsWordsField(_ page: FindItPage) -> Bool {
        !page.isSearching && (editingWords || (page.searchStatus == "done" && page.results.isEmpty))
    }

    /// "Searched for: black crossbody bag, small, slim strap" with Change. Opened, a field with
    /// the words and Search with these words; after nothing found, a line on what to try.
    @ViewBuilder
    private func wordsBlock(_ page: FindItPage) -> some View {
        if showsWordsField(page) {
            VStack(alignment: .leading, spacing: 10) {
                if page.searchStatus == "done" && page.results.isEmpty {
                    Text("Nothing found in your stores.")
                        .font(.caroRowTitle)
                    Text("Try other words: a simpler name, the material, or the word a store would use, like shoulder bag.")
                        .font(.caroNote)
                        .foregroundStyle(Color.muted)
                }
                Text("Search for")
                    .caroLabelStyle()
                    .padding(.top, 4)
                TextField("Like black leather crossbody bag", text: $wordsDraft, axis: .vertical)
                    .font(.caroBody)
                    .lineLimit(1...3)
                    .focused($wordsFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search(words: wordsDraft) } }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.ink).frame(height: 1) }
                HStack(spacing: 16) {
                    Button {
                        Task { await search(words: wordsDraft) }
                    } label: {
                        Text("Search with these words")
                            .font(.text(13, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.terracotta)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 34)
                            .overlay(Capsule().strokeBorder(Color.terracotta, lineWidth: 1))
                            .frame(minHeight: CaroLayout.minTouchTarget)
                    }
                    .buttonStyle(.borderless)
                    .disabled(working || wordsDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if editingWords {
                        Button("Cancel") {
                            editingWords = false
                            wordsFocused = false
                        }
                        .font(.caroLink)
                        .foregroundStyle(Color.muted)
                        .buttonStyle(.borderless)
                    }
                    if page.ownWords {
                        Button("Caro's words") {
                            Task { await search(words: "") }
                        }
                        .font(.caroLink)
                        .foregroundStyle(Color.terracotta)
                        .underline()
                        .buttonStyle(.borderless)
                        .accessibilityHint("Searches again with Caro's description of the piece")
                    }
                }
            }
            .onAppear { if wordsDraft.isEmpty { wordsDraft = page.searchWords } }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                (Text("Searched for ").foregroundStyle(Color.muted) + Text(page.searchWords))
                    .font(.caroNote)
                Spacer(minLength: 4)
                if !page.isSearching {
                    Button("Change") {
                        wordsDraft = page.searchWords
                        editingWords = true
                        wordsFocused = true
                    }
                    .font(.caroLink)
                    .foregroundStyle(Color.terracotta)
                    .underline()
                    .buttonStyle(.borderless)
                    .accessibilityHint("Change the words Caro searches with")
                }
            }
        }
    }

    private func productRow(_ result: StoreResult, page: FindItPage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .center, spacing: 8) {
            Button {
                open(result)
            } label: {
                HStack(spacing: 12) {
                    productImage(result)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(.text(14, weight: .medium, relativeTo: .body))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        Text([result.store, PriceText.text(cents: result.priceCents, currency: result.currency, country: page.country)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caroMeta)
                            .foregroundStyle(Color.muted)
                        if result.isKept {
                            keptLabel
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens it in the store")

            if !page.isBought {
                decisionButtons(result)
            }
        }
        // Kept: Bought, under the name, to add it to your edit.
        if result.isKept && !page.isBought && result.image != nil {
            boughtButton(result)
                .padding(.leading, 76)
        }
        }
        .padding(.vertical, 10)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !page.isBought {
                Button(result.isKept ? "Not kept" : "Keep") {
                    Task { await decide(result, result.isKept ? nil : "kept") }
                }
                .tint(Color.ink)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !page.isBought {
                Button("Discard", role: .destructive) {
                    Task { await decide(result, "discarded") }
                }
                .tint(Color.terracotta)
            }
        }
        .contextMenu {
            Button("Open in the store", systemImage: "safari") { open(result) }
            if !page.isBought {
                Button(result.isKept ? "Not kept" : "Keep", systemImage: result.isKept ? "heart.slash" : "heart") {
                    Task { await decide(result, result.isKept ? nil : "kept") }
                }
                Button("Discard", systemImage: "xmark", role: .destructive) {
                    Task { await decide(result, "discarded") }
                }
            }
        }
    }

    /// Keep (a heart, filled once kept) and discard (a cross), as round outlined buttons.
    private func decisionButtons(_ result: StoreResult) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await decide(result, result.isKept ? nil : "kept") }
            } label: {
                Image(systemName: result.isKept ? "heart.fill" : "heart")
                    .iconFont(15)
                    .foregroundStyle(result.isKept ? Color.onInk : Color.ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(result.isKept ? Color.ink : Color.clear))
                    .overlay(Circle().strokeBorder(Color.ink, lineWidth: 1))
                    .frame(minWidth: CaroLayout.minTouchTarget, minHeight: CaroLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(result.isKept ? "Kept. Tap to undo" : "Keep")
            Button {
                Task { await decide(result, "discarded") }
            } label: {
                Image(systemName: "xmark")
                    .iconFont(14)
                    .foregroundStyle(Color.terracotta)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(Color.terracotta, lineWidth: 1))
                    .frame(minWidth: CaroLayout.minTouchTarget, minHeight: CaroLayout.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Discard")
        }
        .disabled(working)
    }

    private func boughtButton(_ result: StoreResult) -> some View {
                Button("Bought") { buying = result }
                    .font(.text(13, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.terracotta)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .overlay(Capsule().strokeBorder(Color.terracotta, lineWidth: 1))
                    .frame(minHeight: CaroLayout.minTouchTarget)
                    .buttonStyle(.borderless)
                    .disabled(working)
                    .accessibilityHint("Adds it to your edit with the store's picture")
    }

    private func productImage(_ result: StoreResult) -> some View {
        ZStack {
            Color.tile
            if let image = result.image {
                LookPhotoImage(path: image, fill: false)
                    .padding(4)
            }
        }
        .frame(width: 64, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
        .accessibilityHidden(true)
    }

    /// A dot and KEPT, in label style, like YOURS on Your version.
    private var keptLabel: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.ink).frame(width: 7, height: 7)
            Text("Kept")
                .font(.text(11, relativeTo: .caption))
                .textCase(.uppercase)
                .tracking(11 * 0.12)
                .foregroundStyle(Color.muted)
        }
        .padding(.top, 2)
    }

    private func boughtNote(_ page: FindItPage) -> some View {
        HStack(spacing: 12) {
            if let piece = page.piece {
                PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
                    .padding(4)
                    .frame(width: 56, height: 56)
                    .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
            }
            Text("Bought, and in your edit. When it arrives, retake its photo on its page.")
                .font(.caroNote)
                .foregroundStyle(Color.muted)
        }
        .padding(.top, 14)
    }

    private func searchButton(_ page: FindItPage) -> some View {
        Button {
            Task { await search() }
        } label: {
            Text(page.searchStatus == nil ? "Find it" : "Search again")
                .font(.text(13, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.terracotta)
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
                .overlay(Capsule().strokeBorder(Color.terracotta, lineWidth: 1))
                .frame(minHeight: CaroLayout.minTouchTarget)
        }
        .buttonStyle(.plain)
        .disabled(working || page.isSearching)
        .opacity(page.isSearching ? 0.5 : 1)
        .accessibilityHint("Searches your stores for this piece. One AI action.")
    }

    // MARK: Server

    private func open(_ result: StoreResult) {
        guard let url = URL(string: result.url), url.scheme == "https" else { return }
        webPage = WebPage(url: url)
    }

    private func load() async {
        do {
            page = try await store.findIt(toFindID)
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    /// Search again; with words, those words (empty: back to Caro's description).
    private func search(words: String? = nil) async {
        working = true
        defer { working = false }
        do {
            page = try await store.searchAgain(toFindID, words: words)
            editingWords = false
            wordsFocused = false
            wordsDraft = ""
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func decide(_ result: StoreResult, _ decision: String?) async {
        do {
            let changed = try await store.decide(toFindID, result: result.id, decision: decision)
            withAnimation(.snappy) { page = changed }
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    /// Returns the message to show in the crop sheet, or nil when the piece is in the edit.
    private func bought(_ result: StoreResult, picture: UIImage) async -> String? {
        do {
            _ = try await store.bought(toFindID, result: result.id, picture: picture)
            await load()
            return nil
        } catch {
            return store.message(for: error)
        }
    }

    private func drop() async {
        do {
            try await store.dropToFind(toFindID)
            dismiss()
        } catch {
            errorMessage = store.message(for: error)
        }
    }
}

private extension View {
    /// A list row on paper with the page margins and, if wanted, a hairline under it.
    func plainRow(separator: Bool) -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: CaroLayout.pageMargin, bottom: 0, trailing: CaroLayout.pageMargin))
            .listRowBackground(Color.paper)
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(Color.hairline)
    }
}
