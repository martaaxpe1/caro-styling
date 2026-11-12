import SwiftUI

/// S8, a look (to design, in the style of the piece page): "No. 12" with its source, the flat lay
/// large, its occasions and seasons, and its pieces as numbered credits that open each piece.
/// Edit opens the styling table with the look on it; Delete is a small link at the bottom and
/// asks first. Photos of you wearing it come with T9 (looks from a photo).
struct LookView: View {
    let lookID: Int

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page: LookPage?
    @State private var errorMessage: String?
    @State private var editing: StyleStart?
    @State private var confirmingDelete = false
    @State private var working = false

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
        .toolbarBackground(Color.paper, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let look = page?.look {
                    Button("Edit") { editing = .look(look) }
                        .font(.caroButton)
                        .disabled(working)
                }
            }
        }
        .onAppear { Task { await load() } }
        .fullScreenCover(item: $editing) { start in
            StyleLookView(start: start) { _ in
                Task { await load() }
            }
        }
        .alert("Delete look No. \(page?.look.number ?? 0)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its pieces stay in your edit.")
        }
    }

    private func content(_ page: LookPage) -> some View {
        let look = page.look
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(look.source.title)
                    .caroLabelStyle()

                Text("No. \(look.number)")
                    .font(.caroPieceTitle)
                    .caroTitleTracking()
                    .padding(.top, 4)

                FlatLay(items: look.pieces.map { FlatLayItem($0, large: true) }, shadow: .large)
                    .aspectRatio(FlatLay.table.width / FlatLay.table.height, contentMode: .fit)
                    .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                    .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                    .padding(.top, 14)
                    .accessibilityElement()
                    .accessibilityLabel("Look \(look.number): " + look.pieces.compactMap(\.name).joined(separator: ", "))

                VStack(spacing: 0) {
                    DetailRow(label: "Occasions", value: names(look.occasions, in: page.occasions))
                    if !page.seasons.isEmpty {
                        DetailRow(label: "Seasons", value: names(look.seasons, in: page.seasons))
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .padding(.top, 16)

                Text("The pieces")
                    .font(.caroSectionTitle)
                    .padding(.top, 22)

                VStack(spacing: 0) {
                    ForEach(Array(look.pieces.enumerated()), id: \.element.id) { index, piece in
                        credit(index + 1, piece)
                    }
                }
                .padding(.top, 8)

                Button("Delete look") { confirmingDelete = true }
                    .font(.caroLink)
                    .foregroundStyle(Color.terracotta)
                    .underline()
                    .frame(minHeight: CaroLayout.minTouchTarget)
                    .padding(.top, 20)
                    .disabled(working)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caroNote)
                        .foregroundStyle(Color.terracotta)
                }
            }
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    /// A numbered credit: "01", the piece on the tile colour, its name and slot. Opens the piece.
    private func credit(_ number: Int, _ piece: Look.LookPiece) -> some View {
        NavigationLink(value: WardrobeRoute.piece(id: piece.id)) {
            HStack(spacing: 14) {
                Text(ChapterWords.number(number))
                    .font(.display(18, relativeTo: .title3))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 28, alignment: .leading)
                PieceImage(path: piece.images.thumb, isCutout: piece.hasCutout)
                    .padding(4)
                    .frame(width: 52, height: 52)
                    .background(Color.tile, in: RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.name ?? "Piece")
                        .font(.caroRowTitle)
                    Text((Slot(rawValue: piece.slot) ?? .accessories).title)
                        .font(.caroMeta)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .iconFont(13, weight: .light)
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.ink)
            .padding(.vertical, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Office, day out": the names in the member's order, as one sentence.
    private func names(_ ids: [Int], in items: [NamedItem]) -> String? {
        let words = items.filter { ids.contains($0.id) }.map(\.name)
        guard let first = words.first else { return nil }
        return ([first] + words.dropFirst().map { $0.prefix(1).lowercased() + $0.dropFirst() }).joined(separator: ", ")
    }

    private func load() async {
        do {
            page = try await store.lookPage(lookID)
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func delete() async {
        working = true
        defer { working = false }
        do {
            try await store.deleteLook(lookID)
            dismiss()
        } catch {
            errorMessage = store.message(for: error)
        }
    }
}
