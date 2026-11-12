import SwiftUI

/// The screens pushed onto a navigation stack: adding pieces (from onboarding step 6 or from
/// the edit), and the edit's chapters, pieces, overview and season check.
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
}

extension EnvironmentValues {
    /// "Close and keep your progress" on screens 06 and 07: back to the edit. The edit pops to
    /// its first screen; onboarding asks the server again, which then opens the app on the edit.
    @Entry var closeToEdit: () -> Void = {}
}
