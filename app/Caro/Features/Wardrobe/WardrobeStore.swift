import Foundation
import Observation
import PhotosUI
import SwiftUI

/// The member's wardrobe, shared by the edit, step 6, adding pieces and the review.
/// One WardrobeStore lives in the environment, like SetupStore. The server holds the truth:
/// after every change the store asks it again, so the screens show what the server holds.
@Observable
final class WardrobeStore {
    /// What the edit shows: progress, pieces waiting, chapters.
    private(set) var wardrobe: Wardrobe?
    /// Why the wardrobe could not be loaded, shown with Try again.
    private(set) var loadError: String?

    let session: Session
    let api = APIClient()
    private var memberID: Int?

    init(session: Session) {
        self.session = session
    }

    var progress: WardrobeProgress? { wardrobe?.progress }

    /// Loads the wardrobe from the server. Forgets another member's wardrobe first.
    func load() async {
        forgetOtherMember()
        do {
            wardrobe = try await api.wardrobe()
            loadError = nil
        } catch {
            loadError = session.message(for: error)
        }
    }

    /// One chapter's pieces, with the member's seasons and occasions for the filters (S6).
    func chapter(_ name: String) async throws -> ChapterPage {
        try await api.chapter(name)
    }

    /// One piece for its page (screen 11).
    func piecePage(_ pieceID: Int) async throws -> PiecePage {
        try await api.piecePage(pieceID)
    }

    /// Maybe, or no longer a maybe. The edit is updated in the background.
    func setStatus(of pieceID: Int, to status: Piece.Status) async throws -> Piece {
        let piece = try await api.setStatus(of: pieceID, to: status)
        Task { await load() }
        return piece
    }

    /// The facts of the wardrobe overview (S7).
    func overview() async throws -> Overview {
        try await api.overview()
    }

    /// The pieces whose new seasons are still to check, grouped by warmth.
    func seasonsCheck() async throws -> SeasonsCheck {
        try await api.seasonsCheck()
    }

    /// Confirms the new seasons in one batch: the seasons for each warmth.
    func confirmSeasons(_ groups: [String: [Int]]) async throws {
        wardrobe = try await api.confirmSeasons(groups)
    }

    /// Removes a piece. Returns the message to show if it failed. If Looks and Get the look
    /// are open, they stay open: the server never closes them again.
    func remove(_ piece: Piece) async -> String? {
        do {
            _ = try await api.removePiece(piece.id)
            await load()
            return nil
        } catch {
            return session.message(for: error)
        }
    }

    func message(for error: Error) -> String {
        session.message(for: error)
    }

    /// Set by "Style your first look" on screen 09: the app opens on Looks.
    var openLooksNext = false

    /// A look to show next, on Looks: the one just saved from a photo, or the one a new look
    /// turned out to be the same as. MainView opens it and sets this back to nil.
    var lookToOpen: Int?
    /// An inspiration to show in Get the look (T10), from a look's page or the overview.
    var inspirationToOpen: Int?

    // MARK: The review (screen 07)

    /// The fixed lists for the detail pickers. Loaded once.
    private(set) var lists: PieceLists?

    func loadLists() async {
        guard lists == nil else { return }
        lists = try? await api.lists()
    }

    /// Confirms a piece (or marks it maybe). The answer says whether this opened Looks and
    /// Get the look; the edit is updated in the background.
    func save(_ pieceID: Int, details: PieceDetails) async throws -> SavedPiece {
        let saved = try await api.savePiece(pieceID, details: details)
        Task { await load() }
        return saved
    }

    /// Turns a piece's pictures a quarter turn clockwise. The edit is updated in the background.
    func rotate(_ pieceID: Int) async throws -> Piece {
        let piece = try await api.rotatePiece(pieceID)
        Task { await load() }
        return piece
    }

    /// Retake: a new photo for a piece, cut out again on the iPhone. The details stay.
    func retake(_ pieceID: Int, photoFile: Data) async throws -> Piece {
        guard let prepared = await PhotoPrep.prepare(data: photoFile) else {
            throw APIError.refused("Caro could not read this photo. Try another one.")
        }
        let piece = try await api.retakePhoto(of: pieceID, photo: prepared.photo, cutout: prepared.cutout)
        ImageCache.shared.keep(prepared.preview, for: piece.images.thumb)
        return piece
    }

    /// A different member signed in on this iPhone: start from nothing.
    func forgetOtherMember() {
        guard memberID != session.member?.id else { return }
        memberID = session.member?.id
        wardrobe = nil
        loadError = nil
        tiles = []
        queue = nil
    }

    // MARK: Adding pieces (screen 06)
    //
    // Each photo becomes a tile. One at a time, the store prepares it (upright, resized), cuts
    // it out on the iPhone and sends it to the server, which saves the piece at once and has
    // Claude read its details in the background. While any piece is being read, the store asks
    // the server every 2 seconds which are ready (polling). The member can keep adding photos
    // the whole time: new tiles join the end of the line.

    /// One photo on the adding screen.
    struct Tile: Identifiable {
        enum State: Equatable {
            /// In line, not started.
            case waiting
            /// Being cut out and sent.
            case cuttingOut
            /// On the server, Claude is reading its details.
            case reading
            /// Ready for review.
            case ready
            /// Could not be sent: tap to try again.
            case notSent
            /// The picture could not be read at all.
            case unreadable
        }

        let id = UUID()
        /// Where the photo comes from, until it is prepared.
        var source: Source?
        /// Kept until the server has it, so "Not sent" can be tried again.
        var prepared: PhotoPrep.Prepared?
        var preview: UIImage?
        var hasCutout = false
        var pieceID: Int?
        var state = State.waiting
    }

    enum Source {
        /// A photo chosen in the photo library.
        case library(PhotosPickerItem)
        /// A photo taken with the camera, as a file.
        case file(Data)
    }

    /// The photos of this round of adding, in order.
    private(set) var tiles: [Tile] = []
    /// The review queue as the server last sent it.
    private(set) var queue: ReviewQueue?
    private var working = false
    private var polling = false

    /// Pieces whose details are back, ready to review (from this round or before).
    var readyToReview: Int {
        queue?.pieces.filter { $0.detailsStatus != .reading }.count ?? 0
    }

    func count(_ state: Tile.State) -> Int {
        tiles.filter { $0.state == state }.count
    }

    /// Adds photos from the library.
    func add(_ items: [PhotosPickerItem]) {
        startNewRoundIfDone()
        tiles += items.map { Tile(source: .library($0)) }
        startWorking()
    }

    /// Adds a photo from the camera.
    func add(photoFile: Data) {
        startNewRoundIfDone()
        tiles.append(Tile(source: .file(photoFile)))
        startWorking()
    }

    /// "Not sent": try again.
    func retry(_ tileID: UUID) {
        guard let tile = tiles.first(where: { $0.id == tileID }), tile.state == .notSent else { return }
        update(tileID) { $0.state = .waiting }
        startWorking()
    }

    /// A new round of adding starts on a clean screen, once the last round is all done.
    private func startNewRoundIfDone() {
        let busy = tiles.contains { [.waiting, .cuttingOut, .reading, .notSent].contains($0.state) }
        if !busy {
            tiles = []
        }
    }

    private func update(_ id: UUID, _ change: (inout Tile) -> Void) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        change(&tiles[index])
    }

    private func startWorking() {
        guard !working else { return }
        working = true
        Task {
            await work()
            working = false
        }
    }

    /// Takes the tiles in line one by one: prepare, cut out, send.
    private func work() async {
        while let tile = tiles.first(where: { $0.state == .waiting }) {
            let id = tile.id
            update(id) { $0.state = .cuttingOut }

            if tile.prepared == nil {
                guard let prepared = await prepare(tile.source) else {
                    update(id) { $0.state = .unreadable; $0.source = nil }
                    continue
                }
                update(id) {
                    $0.prepared = prepared
                    $0.preview = prepared.preview
                    $0.hasCutout = prepared.cutout != nil
                    // The original is no longer needed: free its memory.
                    $0.source = nil
                }
            }
            await send(id)
        }
    }

    private func prepare(_ source: Source?) async -> PhotoPrep.Prepared? {
        switch source {
        case .library(let item):
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            return await PhotoPrep.prepare(data: data)
        case .file(let data):
            return await PhotoPrep.prepare(data: data)
        case nil:
            return nil
        }
    }

    private func send(_ id: UUID) async {
        guard let prepared = tiles.first(where: { $0.id == id })?.prepared else { return }
        do {
            let piece = try await api.addPiece(photo: prepared.photo, cutout: prepared.cutout)
            // The iPhone already has the picture: no need to download it again.
            ImageCache.shared.keep(prepared.preview, for: piece.images.thumb)
            update(id) {
                $0.pieceID = piece.id
                $0.state = .reading
                $0.prepared = nil
            }
            startPolling()
        } catch {
            if case APIError.signedOut = error {
                _ = session.message(for: error)
                return
            }
            update(id) { $0.state = .notSent }
        }
    }

    /// While any piece is being read, asks the server every 2 seconds which are ready.
    private func startPolling() {
        guard !polling else { return }
        polling = true
        Task {
            while tiles.contains(where: { $0.state == .reading }) {
                await refreshQueue()
                if tiles.contains(where: { $0.state == .reading }) {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            polling = false
            await load()
        }
    }

    /// Asks the server for the review queue, and marks the tiles whose details are back.
    func refreshQueue() async {
        do {
            let latest = try await api.reviewQueue()
            queue = latest
            let pieces = Dictionary(uniqueKeysWithValues: latest.pieces.map { ($0.id, $0) })
            for tile in tiles where tile.state == .reading {
                guard let pieceID = tile.pieceID else { continue }
                // Gone from the queue (confirmed or removed meanwhile) also means done.
                if pieces[pieceID]?.detailsStatus != .reading {
                    update(tile.id) { $0.state = .ready }
                }
            }
        } catch {
            // Offline for a moment: try again on the next round.
        }
    }
}
