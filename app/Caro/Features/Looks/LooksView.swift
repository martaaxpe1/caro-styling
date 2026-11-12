import SwiftUI

/// Screen 13, Looks: the masthead with the dateline "Looks · 34 looks", the member's occasions
/// as a row of words (All first), Style a look, and the saved looks as flat lays, each with its
/// number, occasion and source.
///
/// Added to the design: "Your looks will show here." before the first look, and "No looks for
/// the office yet." for an occasion with none.
struct LooksView: View {
    let member: Member

    @Environment(WardrobeStore.self) private var store
    @State private var page: LooksPage?
    @State private var errorMessage: String?
    /// The occasion chosen in the row of words; nil is All.
    @State private var occasion: Int?
    @State private var styling: StyleStart?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Masthead(
                initial: member.initial,
                dateline: "Looks",
                datelineRight: page.map { countText($0.looks.count, "look", "looks") } ?? "",
                add: { styling = .empty },
                addLabel: "Style a look"
            ) {
                showingSettings = true
            }
            .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let page {
                        occasionsRow(page)
                            .padding(.top, 18)
                    }

                    styleALook
                        .padding(.top, 18)

                    if let page {
                        looks(page)
                            .padding(.top, 18)
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
        .fullScreenCover(item: $styling) { start in
            StyleLookView(start: start) { _ in
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(member: member)
        }
    }

    // MARK: Parts

    /// All, Office, Working from home, ...: Bodoni words, the chosen one in italics, underlined.
    private func occasionsRow(_ page: LooksPage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                occasionWord("All", isOn: occasion == nil) { occasion = nil }
                ForEach(page.occasions) { item in
                    occasionWord(item.name, isOn: occasion == item.id) { occasion = item.id }
                }
            }
            .padding(.trailing, CaroLayout.pageMargin)
        }
        .padding(.trailing, -CaroLayout.pageMargin)
    }

    private func occasionWord(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.display(18, relativeTo: .title3))
                .italic(isOn)
                // Room for the italic's last letter, which leans past the word's box.
                .padding(.trailing, 3)
                .foregroundStyle(isOn ? Color.ink : Color.muted)
                .overlay(alignment: .bottom) {
                    if isOn {
                        Rectangle().fill(Color.ink).frame(height: 1).offset(y: 6)
                    }
                }
                .frame(minHeight: CaroLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The outlined card: "Style a look", "From scratch, or start from a piece".
    private var styleALook: some View {
        Button {
            styling = .empty
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Style a look")
                        .font(.caroChapterName)
                    Text("From scratch, or start from a piece")
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .light))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .overlay(RoundedRectangle(cornerRadius: CaroLayout.tileRadius).strokeBorder(Color.ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func looks(_ page: LooksPage) -> some View {
        let shown = page.looks.filter { occasion == nil || $0.occasions.contains(occasion!) }
        if page.looks.isEmpty {
            Text("Your looks will show here.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
        } else if shown.isEmpty, let name = page.occasions.first(where: { $0.id == occasion })?.name {
            Text("No looks for \(OccasionWords.phrase(name)) yet.")
                .font(.caroBody)
                .foregroundStyle(Color.muted)
        } else {
            LooksGrid(looks: shown, occasions: page.occasions, preferredOccasion: occasion)
        }
    }

    private func load() async {
        do {
            page = try await store.looks()
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }
}

/// Looks in two columns, each a flat lay with "No. 34", its occasion and its source.
/// Used on Looks and on "See all" from a piece.
struct LooksGrid: View {
    let looks: [Look]
    let occasions: [NamedItem]
    /// The occasion named under each look: the one chosen above, or the look's first.
    var preferredOccasion: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(looks) { look in
                NavigationLink(value: WardrobeRoute.look(id: look.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        FlatLay(items: look.pieces.map { FlatLayItem($0) })
                            .frame(height: 170)
                            .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                            .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))

                        HStack(alignment: .firstTextBaseline) {
                            Text("No. \(look.number)")
                                .font(.display(16, relativeTo: .headline))
                            Spacer(minLength: 4)
                            Text(occasionName(look))
                                .font(.text(11, relativeTo: .caption))
                                .foregroundStyle(Color.muted)
                                .lineLimit(1)
                        }
                        Text(look.source.title)
                            .font(.text(11, relativeTo: .caption))
                            .textCase(.uppercase)
                            .tracking(11 * 0.12)
                            .foregroundStyle(Color.muted)
                    }
                    .foregroundStyle(Color.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(["Look \(look.number)", occasionName(look), look.source.title].filter { !$0.isEmpty }.joined(separator: ", "))
            }
        }
    }

    private func occasionName(_ look: Look) -> String {
        let id = preferredOccasion.flatMap { look.occasions.contains($0) ? $0 : nil } ?? look.occasions.first
        return occasions.first { $0.id == id }?.name ?? ""
    }
}

/// "See all" from a piece: every look it is in.
struct PieceLooksView: View {
    let pieceID: Int
    let name: String

    @Environment(WardrobeStore.self) private var store
    @State private var page: LooksPage?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Looks with your \(name.prefix(1).lowercased() + name.dropFirst())")
                    .font(.caroScreenTitle)
                    .caroTitleTracking()
                if let page {
                    LooksGrid(looks: page.looks.filter { $0.pieces.contains { $0.id == pieceID } }, occasions: page.occasions)
                } else if let errorMessage {
                    Text(errorMessage).font(.caroNote).foregroundStyle(Color.terracotta)
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
        .onAppear {
            Task {
                do {
                    page = try await store.looks()
                } catch {
                    errorMessage = store.message(for: error)
                }
            }
        }
    }
}
