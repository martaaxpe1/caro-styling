import SwiftUI

/// S7, the wardrobe overview (designed here, in the style of screens 10 and 11): what you have,
/// as facts. Counts by chapter, main colour, season and occasion. Once there is a first look,
/// the pieces in no look yet and the occasions with fewer than three looks. Never advice.
struct OverviewView: View {
    @Environment(WardrobeStore.self) private var store
    @State private var overview: Overview?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(overview.map { "The edit · \(countText($0.pieces, "piece", "pieces"))" } ?? "The edit")
                    .caroLabelStyle()

                Text("The \(Text("overview").italic())")
                    .font(.caroPieceTitle)
                    .caroTitleTracking()
                    .padding(.top, 6)

                if let overview {
                    facts(overview)
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
            .padding(.bottom, 32)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .refreshable { await load() }
        .onAppear { Task { await load() } }
    }

    @ViewBuilder
    private func facts(_ overview: Overview) -> some View {
        section("By chapter") {
            ForEach(overview.chapters) { chapter in
                CountRow(count: chapter.count) {
                    HStack(spacing: 10) {
                        Text(ChapterWords.number(chapter.number))
                            .font(.display(17, relativeTo: .headline))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 26, alignment: .leading)
                        Text(ChapterWords.title(chapter.name))
                    }
                }
            }
        }

        if !overview.colours.isEmpty {
            section("By colour", note: "Main colour") {
                ForEach(overview.colours) { colour in
                    CountRow(count: colour.count) {
                        HStack(spacing: 10) {
                            ColourSwatch(colour: colour.name)
                            Text(PieceWords.title(colour.name))
                        }
                    }
                }
            }
        }

        if !overview.seasons.isEmpty {
            section("By season") {
                ForEach(overview.seasons) { season in
                    CountRow(count: season.count) { Text(season.name) }
                }
                if overview.noSeason > 0 {
                    CountRow(count: overview.noSeason, muted: true) { Text("No season") }
                }
            }
        }

        section("By occasion") {
            ForEach(overview.occasions) { occasion in
                CountRow(count: occasion.count) { Text(occasion.name) }
            }
            if overview.noOccasion > 0 {
                CountRow(count: overview.noOccasion, muted: true) { Text("No occasion yet") }
            }
        }

        if let notInALook = overview.notInALook {
            section("Not in a look yet") {
                CountRow(count: notInALook.count) { Text(notInALook.count == 1 ? "Piece" : "Pieces") }
                if !notInALook.pieces.isEmpty {
                    HStack(spacing: -10) {
                        ForEach(notInALook.pieces) { piece in
                            PieceImage(path: piece.thumb, isCutout: piece.hasCutout)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityHidden(true)
                }
            }
            if let few = overview.occasionsFewLooks, !few.isEmpty {
                section("Occasions with fewer than three looks") {
                    ForEach(few) { occasion in
                        CountRow(text: countText(occasion.looks, "look", "looks")) { Text(occasion.name) }
                    }
                }
            }
        } else {
            section("Looks") {
                Text("The looks facts start with your first look: pieces in no look yet, and occasions with fewer than three looks.")
                    .font(.caroNote)
                    .foregroundStyle(Color.muted)
                    .padding(.vertical, 10)
            }
        }
    }

    private func section<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caroSectionTitle)
                Spacer()
                if let note {
                    Text(note)
                        .font(.text(11, relativeTo: .caption))
                        .foregroundStyle(Color.muted)
                }
            }
            .padding(.bottom, 6)
            content()
        }
        .padding(.top, 26)
    }

    private func load() async {
        do {
            overview = try await store.overview()
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }
}

/// A fact: what on the left, how many on the right, a hairline under it.
struct CountRow<Label: View>: View {
    var text: String
    var muted = false
    @ViewBuilder let label: () -> Label

    init(count: Int, muted: Bool = false, @ViewBuilder label: @escaping () -> Label) {
        self.text = "\(count)"
        self.muted = muted
        self.label = label
    }

    init(text: String, @ViewBuilder label: @escaping () -> Label) {
        self.text = text
        self.label = label
    }

    var body: some View {
        HStack {
            label()
                .foregroundStyle(muted ? Color.muted : Color.ink)
            Spacer()
            Text(text)
                .monospacedDigit()
                .foregroundStyle(muted ? Color.muted : Color.ink)
        }
        .font(.caroBody)
        .padding(.vertical, 6) // Room above and below when the text is large; no change at the normal size.
        .frame(minHeight: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
