import SwiftUI

/// The screens pushed onto a navigation stack: adding pieces (from onboarding step 6 or from
/// the edit), the edit's chapters, pieces, overview and season check, and looks (on both the
/// edit's stack and the Looks tab's).
enum WardrobeRoute: Hashable {
    /// Screen 05 from the edit's add button: the tips, Take photos, Choose from library.
    case addPieces
    /// Screen 06: the photos being cut out and read.
    case adding
    /// Screen 07: the review queue.
    case review
    /// One chapter's pieces, with filters (S6).
    case chapter(name: String, number: Int)
    /// One piece's page (screen 11).
    case piece(id: Int)
    /// Edit on the piece page: the review form, with Save, Brand and Notes.
    case editPiece(Piece)
    /// The wardrobe overview (S7).
    case overview
    /// The new seasons to check in one batch, after the year changed.
    case seasonsCheck
    /// One look's page (S8).
    case look(id: Int)
    /// "See all" from a piece: every look it is in.
    case looksWith(pieceID: Int, name: String)
    /// An inspiration and your version of it (screen 15), from a look or the overview (T10).
    case inspiration(id: Int)
}

extension EnvironmentValues {
    /// "Close and keep your progress" on screens 06 and 07: back to the edit. The edit pops to
    /// its first screen; onboarding asks the server again, which then opens the app on the edit.
    @Entry var closeToEdit: () -> Void = {}
}
