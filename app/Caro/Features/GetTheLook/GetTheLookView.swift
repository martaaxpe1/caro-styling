import PhotosUI
import SwiftUI

/// Screen 14, Get the look: the masthead with the dateline "Get the look · 6 inspirations", the
/// dashed Add an inspiration card (or share an image from Pinterest into Caro), your
/// inspirations with how much of each you own ("4 of 5 yours"), and the To find list.
///
/// Add an inspiration and the plus are a native menu: Choose from library, or Paste a Pinterest
/// link (Caro takes the pin's image). An image needs no link.
///
/// Added to the design: an inspiration Caro is still reading says "Reading"; one it could not
/// read says so. All inspirations show in the grid, so there is no See all yet. Find it on a
/// To find piece comes with T11; until then the row says "Not searched yet".
struct GetTheLookView: View {
    let member: Member
    /// Opens an inspiration's page.
    let open: (Int) -> Void

    @Environment(WardrobeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: GetTheLookPage?
    @State private var errorMessage: String?
    @State private var showingSettings = false
    @State private var showingLibrary = false
    @State private var item: PhotosPickerItem?
    @State private var adding = false
    @State private var addError: String?
    @State private var askingForLink = false
    @State private var linkDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            Masthead(
                initial: member.initial,
                dateline: "Get the look",
                datelineRight: page.map { countText($0.inspirations.count, "inspiration", "inspirations") } ?? "",
                add: { showingLibrary = true },
                addLabel: "Add an inspiration",
                addChoices: [
                    (title: "Choose from library", systemImage: "photo.on.rectangle", action: { chooseFromLibrary() }),
                    (title: "Paste a Pinterest link", systemImage: "link", action: { pasteLink() }),
                ]
            ) {
                showingSettings = true
            }
            .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    addCard
                        .padding(.top, 18)
                    if let addError {
                        Text(addError)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                    }

                    if let page {
                        inspirations(page)
                            .padding(.top, 22)
                        toFind(page)
                            .padding(.top, 26)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.caroNote)
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, CaroLayout.pageMargin)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Task { await load() } }
        .refreshable { await load() }
        // Back from the share sheet: an inspiration shared from Pinterest is here now.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        // While Caro reads an inspiration, ask again every few seconds.
        .task(id: isReading) {
            while isReading, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await load()
            }
        }
        .photosPicker(isPresented: $showingLibrary, selection: $item, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            item = nil
            Task { await add(picked) }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(member: member)
        }
        .alert("Pinterest link", isPresented: $askingForLink) {
            TextField("https://pin.it/...", text: $linkDraft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") { Task { await add(link: linkDraft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the link of a pin. Caro takes its image.")
        }
    }

    private func chooseFromLibrary() {
        addError = nil
        showingLibrary = true
    }

    private func pasteLink() {
        addError = nil
        linkDraft = ""
        askingForLink = true
    }

    private var isReading: Bool {
        page?.inspirations.contains { $0.status == "reading" } ?? false
    }

    // MARK: Parts

    /// "Add an inspiration", "Or share an image from Instagram or Pinterest", in a dashed card.
    /// A native menu: Choose from library, Paste a Pinterest link.
    private var addCard: some View {
        Menu {
            Button("Choose from library", systemImage: "photo.on.rectangle") { chooseFromLibrary() }
            Button("Paste a Pinterest link", systemImage: "link") { pasteLink() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(adding ? "Adding your inspiration" : "Add an inspiration")
                        .font(.display(21, relativeTo: .title2))
                    Text("Or share an image from Instagram or Pinterest")
                        .font(.text(12, relativeTo: .footnote))
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 8)
                if adding { ProgressView() }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                    .strokeBorder(Color.emptySlot, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(adding)
        .accessibilityHint("Choose an image from your library, or paste a Pinterest link")
    }

    @ViewBuilder
    private func inspirations(_ page: GetTheLookPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspirations")
                .font(.display(19, relativeTo: .title3).italic())
            if page.inspirations.isEmpty {
                Text("The looks you add will show here, with how much of each you own.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 14) {
                    ForEach(page.inspirations) { inspiration in
                        Button {
                            open(inspiration.id)
                        } label: {
                            tile(inspiration, occasions: page.occasions)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tile(_ inspiration: InspirationSummary, occasions: [NamedItem]) -> some View {
        let occasion = occasions.first { $0.id == inspiration.occasion }?.name
        return VStack(alignment: .leading, spacing: 4) {
            LookPhotoImage(path: inspiration.thumb)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(ownedText(inspiration))
                .font(.text(13, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(inspiration.status == "not read" ? Color.terracotta : Color.ink)
                .lineLimit(2)
            if let occasion {
                Text(occasion)
                    .font(.text(11, relativeTo: .caption))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(["Inspiration", ownedText(inspiration), occasion].compactMap { $0 }.joined(separator: ", "))
    }

    private func ownedText(_ inspiration: InspirationSummary) -> String {
        switch inspiration.status {
        case "reading": return "Reading"
        case "not read": return "Not read yet"
        default:
            if inspiration.total == 0 { return "No pieces found" }
            if inspiration.owned == inspiration.total { return "All yours" }
            return "\(inspiration.owned) of \(inspiration.total) yours"
        }
    }

    @ViewBuilder
    private func toFind(_ page: GetTheLookPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("To find")
                    .font(.display(19, relativeTo: .title3).italic())
                Spacer()
                if !page.toFind.isEmpty {
                    Text(countText(page.toFind.count, "piece", "pieces"))
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
            }
            if page.toFind.isEmpty {
                Text("Mark a missing piece as key and it shows here.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(page.toFind) { item in
                        Button {
                            open(item.inspiration)
                        } label: {
                            toFindRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The piece's name and state, with a dashed spot where the product will show (T11).
    private func toFindRow(_ item: ToFindItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                .strokeBorder(Color.terracotta, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .font(.text(14, weight: .medium, relativeTo: .body))
                Text(statusText(item))
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .iconFont(14, weight: .light)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "In 3 inspirations · not searched yet"
    private func statusText(_ item: ToFindItem) -> String {
        ToFindWords.status(searchedAt: item.searchedAt, bought: item.status == "bought", inspirations: item.inspirations)
    }

    // MARK: Server

    private func load() async {
        do {
            page = try await store.getTheLook()
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    /// Sends a Pinterest link: the server takes the pin's image. Then opens its page.
    private func add(link: String) async {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        adding = true
        defer { adding = false }
        do {
            let inspiration = try await store.addInspiration(link: link)
            await load()
            open(inspiration.id)
        } catch {
            addError = store.message(for: error)
        }
    }

    /// Sends the chosen image, then opens its page, where Caro reads it.
    private func add(_ picked: PhotosPickerItem) async {
        adding = true
        defer { adding = false }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let photo = await LookPhotoSource.photoFile(from: data)
        else {
            addError = "Caro could not read this image. Try another one."
            return
        }
        do {
            let inspiration = try await store.addInspiration(photo: photo)
            await load()
            // Pushed once the photo picker has finished closing.
            try? await Task.sleep(for: .milliseconds(400))
            open(inspiration.id)
        } catch {
            addError = store.message(for: error)
        }
    }
}
