import SwiftUI

/// The edit (screen 08 while the wardrobe is being built; T6 makes it screen 10).
/// The masthead with the add button, the progress box while Looks and Get the look are locked,
/// the pieces still waiting, and one numbered row per chapter with its count and cut-outs.
struct EditView: View {
    let member: Member
    let addPieces: () -> Void
    let review: () -> Void
    let openChapter: (ChapterSummary) -> Void

    @Environment(WardrobeStore.self) private var store
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Masthead(
                    initial: member.initial,
                    dateline: "The edit",
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
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.load() }
        .task { await store.load() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(member: member)
        }
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

            if wardrobe.chapters.isEmpty {
                Text("Your pieces show here once you confirm them, chapter by chapter.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(wardrobe.chapters) { chapter in
                        Button {
                            openChapter(chapter)
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 14)
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

    var body: some View {
        HStack(spacing: 0) {
            Text(ChapterWords.number(chapter.number))
                .font(.caroChapterNumber)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(ChapterWords.title(chapter.name))
                    .font(.caroChapterName)
                Text(chapter.count == 1 ? "1 piece" : "\(chapter.count) pieces")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: -12) {
                ForEach(chapter.thumbs, id: \.self) { thumb in
                    PieceImage(path: thumb)
                        .frame(width: 48, height: 48)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .frame(minHeight: 76)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the chapter")
    }
}
