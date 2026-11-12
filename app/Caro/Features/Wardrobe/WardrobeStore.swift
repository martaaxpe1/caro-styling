import Foundation
import Observation

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

    /// The counted pieces of one chapter.
    func pieces(inChapter chapter: String) async throws -> [Piece] {
        try await api.pieces(inChapter: chapter)
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

    /// A different member signed in on this iPhone: start from nothing.
    func forgetOtherMember() {
        guard memberID != session.member?.id else { return }
        memberID = session.member?.id
        wardrobe = nil
        loadError = nil
    }
}
