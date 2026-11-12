import SwiftUI

/// S8, a look (to design, in the style of the piece page): "No. 12" with its source, the flat lay
/// large, its occasions and seasons, and its pieces as numbered credits that open each piece.
/// Edit opens the styling table with the look on it; Delete is a small link at the bottom and
/// asks first.
///
/// T9: "Your photos", the photos of you wearing it, in a row under the flat lay. Tap one to see
/// it large, with Remove photo (asks first). Add a photo takes or chooses one; no AI.
struct LookView: View {
    let lookID: Int

    @Environment(WardrobeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page: LookPage?
    @State private var errorMessage: String?
    @State private var editing: StyleStart?
    @State private var confirmingDelete = false
    @State private var working = false
    @State private var askingForPhoto = false
    @State private var shownPhoto: Look.Photo?

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
        .lookPhotoSource(isAsking: $askingForPhoto, title: "A photo of you wearing it") { data in
            Task { await addPhoto(data) }
        }
        .fullScreenCover(item: $shownPhoto) { photo in
            LookPhotoViewer(photo: photo, number: page?.look.number ?? 0) {
                Task { await removePhoto(photo) }
            }
        }
        .alert("Delete look No. \(page?.look.number ?? 0)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(page?.look.photos.isEmpty == false ? "Its pieces stay in your edit. Your photos of it are deleted." : "Its pieces stay in your edit.")
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

                photos(look)
                    .padding(.top, 18)

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

    /// "Your photos": the photos of you wearing it, then a dashed spot to add one.
    private func photos(_ look: Look) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your photos")
                .font(.caroSectionTitle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(look.photos) { photo in
                        Button {
                            shownPhoto = photo
                        } label: {
                            LookPhotoImage(path: photo.thumb)
                                .frame(width: 96, height: 128)
                                .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your photo wearing look \(look.number)")
                    }
                    Button {
                        askingForPhoto = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .iconFont(18, weight: .light)
                                .accessibilityHidden(true)
                            Text("Add a photo")
                                .font(.caroMeta)
                        }
                        .foregroundStyle(Color.ink)
                        .frame(width: 96, height: 128)
                        .overlay(
                            RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
                                .strokeBorder(Color.emptySlot, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                }
            }
            if working {
                Text("Adding your photo")
                    .font(.caroMeta)
                    .foregroundStyle(Color.muted)
            }
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

    private func addPhoto(_ data: Data) async {
        working = true
        defer { working = false }
        do {
            let look = try await store.addLookPhoto(lookID, photo: data)
            if let page { self.page = LookPage(look: look, occasions: page.occasions, seasons: page.seasons) }
            errorMessage = nil
        } catch {
            errorMessage = store.message(for: error)
        }
    }

    private func removePhoto(_ photo: Look.Photo) async {
        do {
            let look = try await store.removeLookPhoto(lookID, photoID: photo.id)
            if let page { self.page = LookPage(look: look, occasions: page.occasions, seasons: page.seasons) }
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

/// A photo of you wearing a look, filling its frame. Loaded with the session token.
struct LookPhotoImage: View {
    let path: String
    var fill = true

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // The placeholder colour while it loads, in a thumbnail; nothing behind a large photo.
            if fill { Color.photo }
            if let image {
                if fill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
        }
        .task(id: path) {
            image = await ImageCache.shared.image(for: path)
        }
        .accessibilityHidden(true)
    }
}

/// One photo large, on ink, with Done and Remove photo (asks first).
private struct LookPhotoViewer: View {
    let photo: Look.Photo
    let number: Int
    let remove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }
                    .font(.text(15, weight: .medium, relativeTo: .body))
                    .frame(minHeight: CaroLayout.minTouchTarget)
                Spacer()
                // The label style, in paper on ink.
                Text("No. \(number)")
                    .font(.caroLabel)
                    .textCase(.uppercase)
                    .tracking(11 * 0.16)
                    .foregroundStyle(Color.onInk)
                Spacer()
                Button("Remove photo") { confirmingRemove = true }
                    .font(.caroLink)
                    .frame(minHeight: CaroLayout.minTouchTarget)
            }
            .foregroundStyle(Color.onInk)
            .padding(.horizontal, CaroLayout.pageMargin)

            LookPhotoImage(path: photo.photo, fill: false)
                .background(Color.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel("Your photo wearing look \(number)")
        }
        .background(Color.ink.ignoresSafeArea())
        // Light status bar text on ink.
        .preferredColorScheme(.dark)
        .alert("Remove this photo?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                remove()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The look stays.")
        }
    }
}
