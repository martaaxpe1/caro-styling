import SwiftUI

/// A simple list of one chapter's pieces (added in T5). It stands in for the chapter page (S6),
/// which T6 builds with filters, so a piece can already be removed: touch and hold, Remove.
struct ChapterPiecesView: View {
    let name: String
    let number: Int

    @Environment(WardrobeStore.self) private var store
    @State private var pieces: [Piece]?
    @State private var errorMessage: String?
    @State private var removing: Piece?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(ChapterWords.title(name))
                    .font(.caroScreenTitle)
                    .caroTitleTracking()

                Text("Tap a piece to change its details. Touch and hold to remove it.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 8)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                        .padding(.top, 12)
                }

                if let pieces {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(pieces) { piece in
                            NavigationLink(value: WardrobeRoute.piece(piece)) {
                                PieceTile(piece: piece)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove piece", systemImage: "trash", role: .destructive) {
                                    removing = piece
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .background(Color.paper)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Chapter \(ChapterWords.number(number))")
                    .caroLabelStyle()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        // Again each time it shows, so a piece changed or turned shows as it is now.
        .onAppear { Task { await load() } }
        .alert(
            "Remove this piece?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { piece in
            Button("Remove", role: .destructive) {
                Task { await remove(piece) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { piece in
            Text("\(piece.name ?? "This piece") and its photos are deleted.")
        }
    }

    private func load() async {
        do {
            pieces = try await store.pieces(inChapter: name)
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func remove(_ piece: Piece) async {
        if let failed = await store.remove(piece) {
            errorMessage = failed
        } else {
            pieces?.removeAll { $0.id == piece.id }
        }
    }
}

/// A piece on the tile colour, with its name under it.
struct PieceTile: View {
    let piece: Piece

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                .fill(Color.tile)
                .frame(height: 120)
                .overlay {
                    PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
                        .padding(piece.hasCutout ? 12 : 6)
                }
            Text(piece.name ?? "")
                .font(.caroMeta)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
