import SwiftUI

/// The edit (screen 08 while the wardrobe is being built, screen 10 after).
/// The masthead with the add button and "The autumn edit", the progress box while Looks and
/// Get the look are locked, the pieces still waiting, new seasons to check, the contents (one
/// numbered row per chapter with its counts and cut-outs) and a last row for the overview.
struct EditView: View {
    let member: Member
    let addPieces: () -> Void
    let review: () -> Void
    let openChapter: (ChapterSummary) -> Void
    /// The overview and the season check.
    let open: (WardrobeRoute) -> Void

    @Environment(WardrobeStore.self) private var store
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Masthead(
                    initial: member.initial,
                    dateline: editLine,
                    datelineRight: piecesLine,
                    add: addPieces
                ) {
                    showingSettings = true
                }
                .padding(.top, 6)

                content
                    .padding(.horizontal, CaroLayout.pageMargin)
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        // The pages scroll under a strip of paper behind the clock, not under the clock itself.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.paper.frame(height: 0)
                .background(Color.paper.ignoresSafeArea(edges: .top))
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.load() }
        .task { await store.load() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(member: member)
        }
    }

    /// "The autumn edit": the season holding today's month. "The edit" with no seasons.
    private var editLine: String {
        guard let season = store.wardrobe?.currentSeason?.name, !season.isEmpty else { return "The edit" }
        return "The \(season.prefix(1).lowercased() + season.dropFirst()) edit"
    }

    private var piecesLine: String {
        guard let pieces = store.progress?.pieces else { return "" }
        return pieces == 1 ? "1 piece" : "\(pieces) pieces"
    }

    @ViewBuilder
    private var content: some View {
        if let wardrobe = store.wardrobe {
            if !wardrobe.progress.unlocked {
                ProgressBox(progress: wardrobe.progress, addPieces: addPieces)
                    .padding(.top, 18)
            }

            waitingLine(wardrobe.waiting)
            seasonsLine(wardrobe.seasonsToCheck)

            if wardrobe.chapters.isEmpty {
                Text("Your pieces show here once you confirm them, chapter by chapter.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 24)
            } else {
                Text("Contents")
                    .font(.display(17, relativeTo: .headline).italic())
                    .foregroundStyle(Color.muted)
                    .padding(.top, 22)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(wardrobe.chapters) { chapter in
                        Button {
                            openChapter(chapter)
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        open(.overview)
                    } label: {
                        OverviewRow()
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let message = store.loadError {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.caroBody)
                    .foregroundStyle(Color.terracotta)
                Button("Try again") {
                    Task { await store.load() }
                }
                .font(.caroLink)
                .foregroundStyle(Color.terracotta)
                .underline()
            }
            .padding(.top, 24)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    /// Added to screen 08: pieces Claude is still reading, and pieces waiting for review.
    @ViewBuilder
    private func waitingLine(_ waiting: Wardrobe.Waiting) -> some View {
        if waiting.toReview > 0 || waiting.reading > 0 {
            HStack(spacing: 12) {
                Text(waitingText(waiting))
                    .font(.caroNote)
                Spacer(minLength: 0)
                if waiting.toReview > 0 {
                    Button("Review", action: review)
                        .font(.caroLink)
                        .foregroundStyle(Color.terracotta)
                        .underline()
                        .frame(minHeight: CaroLayout.minTouchTarget)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
        }
    }

    /// After the number of seasons changed: the new seasons to check in one batch.
    @ViewBuilder
    private func seasonsLine(_ count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 12) {
                Text("New seasons for \(countText(count, "piece", "pieces"))")
                    .font(.caroNote)
                Spacer(minLength: 0)
                Button("Check") { open(.seasonsCheck) }
                    .font(.caroLink)
                    .foregroundStyle(Color.terracotta)
                    .underline()
                    .frame(minHeight: CaroLayout.minTouchTarget)
            }
            .padding(.top, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
        }
    }

    private func waitingText(_ waiting: Wardrobe.Waiting) -> String {
        var parts: [String] = []
        if waiting.toReview > 0 {
            parts.append(waiting.toReview == 1 ? "1 piece to review" : "\(waiting.toReview) pieces to review")
        }
        if waiting.reading > 0 {
            parts.append("\(waiting.reading) being read")
        }
        return parts.joined(separator: " · ")
    }
}

/// One chapter on the edit: its number, its name, its count, and its newest cut-outs.
struct ChapterRow: View {
    let chapter: ChapterSummary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 0) {
            // The number never splits over two lines: its column widens when the text is larger.
            Text(ChapterWords.number(chapter.number))
                .font(.caroChapterNumber)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 50, alignment: .leading)
                .padding(.trailing, typeSize.isAccessibilitySize ? 10 : 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(ChapterWords.title(chapter.name))
                    .font(.caroChapterName)
                Text(meta)
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
                // At the largest text sizes the cut-outs move under the words, so a chapter's
                // name keeps the whole width and never breaks inside a word.
                if typeSize.isAccessibilitySize {
                    thumbs.padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)

            if !typeSize.isAccessibilitySize {
                thumbs.frame(width: 112, alignment: .trailing)
            }
        }
        .frame(minHeight: 80)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the chapter")
    }

    /// The chapter's newest cut-outs, overlapping a little.
    private var thumbs: some View {
        HStack(spacing: -12) {
            ForEach(chapter.thumbs, id: \.self) { thumb in
                PieceImage(path: thumb)
                    .frame(width: 48, height: 48)
            }
        }
    }

    /// "11 pieces · 2 not styled yet". The second part waits for a first look.
    private var meta: String {
        let pieces = countText(chapter.count, "piece", "pieces")
        guard let notStyled = chapter.notStyled, notStyled > 0 else { return pieces }
        return "\(pieces) · \(notStyled) not styled yet"
    }
}

/// The last row of the contents: the wardrobe overview (S7).
struct OverviewRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 50, height: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("The overview")
                    .font(.caroChapterName)
                    .italic()
                Text("By chapter, colour, season and occasion")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .iconFont(14, weight: .light)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 80)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the overview")
    }
}
