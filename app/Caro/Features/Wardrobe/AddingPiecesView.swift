import SwiftUI

/// Screen 06, Adding pieces: every photo of this round as a tile, while it is cut out, sent and
/// read. "7 ready · 3 cutting out · 2 waiting". Add more photos, or review the ready ones.
/// The cross closes it and keeps everything: the pieces carry on in the background.
struct AddingPiecesView: View {
    @Environment(WardrobeStore.self) private var store
    @Environment(\.closeToEdit) private var closeToEdit
    @State private var showingLibrary = false
    @State private var showingCamera = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let count = store.tiles.count
                Text("\(count) \(Text(count == 1 ? "photo" : "photos").italic())")
                    .font(.display(30, relativeTo: .largeTitle))
                    .caroTitleTracking()

                Text("Cutting them out and reading the details. You can keep adding while you wait.")
                    .font(.caroBody)
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(store.tiles) { tile in
                        AddingTileView(tile: tile)
                            .onTapGesture {
                                if tile.state == .notSent {
                                    store.retry(tile.id)
                                }
                            }
                    }
                }
                .padding(.top, 18)

                summary
                    .padding(.top, 12)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CaroLayout.pageMargin)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .background(Color.paper)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Menu {
                    Button("Take photos", systemImage: "camera") { showingCamera = true }
                    Button("Choose from library", systemImage: "photo.on.rectangle") { showingLibrary = true }
                } label: {
                    // Drawn like the outlined pill: a menu cannot take a button style.
                    Text("Add more photos")
                        .font(.caroButton)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: CaroLayout.buttonHeight)
                        .overlay { Capsule().strokeBorder(Color.ink, lineWidth: 1) }
                        .contentShape(Capsule())
                }

                let ready = store.readyToReview
                NavigationLink(value: WardrobeRoute.review) {
                    Text(ready == 1 ? "Review 1 piece" : "Review \(ready) pieces")
                }
                .buttonStyle(.pill)
                .disabled(ready == 0)
            }
            .bottomButtonBar()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    closeToEdit()
                } label: {
                    Image(systemName: "xmark")
                        .iconFont(16, weight: .light)
                }
                .accessibilityLabel("Close and keep your progress")
            }
            ToolbarItem(placement: .principal) {
                Text("Adding pieces")
                    .caroLabelStyle()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .paperBar()
        .addPhotosSources(library: $showingLibrary, camera: $showingCamera) {}
        .task { await store.refreshQueue() }
    }

    /// "7 ready · 3 cutting out · 2 waiting", with "not sent" when any could not be sent.
    private var summary: some View {
        let ready = store.count(.ready)
        let busy = store.count(.cuttingOut) + store.count(.reading)
        let waiting = store.count(.waiting)
        let notSent = store.count(.notSent)
        let unreadable = store.count(.unreadable)

        var rest: [String] = []
        if busy > 0 { rest.append("\(busy) cutting out") }
        if waiting > 0 { rest.append("\(waiting) waiting") }
        if notSent > 0 { rest.append("\(notSent) not sent, tap to try again") }
        if unreadable > 0 { rest.append("\(unreadable) could not be read") }

        return (Text("\(ready) ready").fontWeight(.semibold).foregroundStyle(Color.ink)
            + Text(rest.isEmpty ? "" : " · " + rest.joined(separator: " · ")))
            .font(.caroNote)
            .foregroundStyle(Color.muted)
    }
}

/// One photo on screen 06: on the tile colour with a check once ready; darker with "Cutting out"
/// while it is cut out, sent and read; faded with "Waiting" while in line.
private struct AddingTileView: View {
    let tile: WardrobeStore.Tile

    var body: some View {
        RoundedRectangle(cornerRadius: CaroLayout.tileRadius)
            .fill(background)
            .frame(height: 110)
            .overlay {
                if let preview = tile.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .padding(tile.hasCutout ? 12 : 6)
                        .opacity(tile.state == .waiting ? 0.55 : 1)
                        .shadow(color: shadowColor, radius: 2, x: 0, y: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if tile.state == .ready {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.onInk)
                        .frame(width: 20, height: 20)
                        .background(Color.ink, in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if let label {
                    Text(label)
                        .font(.text(11, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(tile.state == .notSent || tile.state == .unreadable ? Color.terracotta : Color.ink)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(Color.paper, in: RoundedRectangle(cornerRadius: 3))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CaroLayout.tileRadius))
            .accessibilityElement()
            .accessibilityLabel(label ?? "Ready")
    }

    private var background: Color {
        switch tile.state {
        case .ready: .tile
        case .cuttingOut, .reading: .addingWorking
        default: .addingWaiting
        }
    }

    private var shadowColor: Color {
        tile.state == .ready && tile.hasCutout ? Color.shadowBrown.opacity(0.2) : .clear
    }

    private var label: String? {
        switch tile.state {
        case .ready: nil
        case .cuttingOut, .reading: "Cutting out"
        case .waiting: "Waiting"
        case .notSent: "Not sent"
        case .unreadable: "Could not read"
        }
    }
}
