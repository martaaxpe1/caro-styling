import SwiftUI

/// The screens of adding pieces, pushed onto a navigation stack: from onboarding step 6 or
/// from the edit.
enum WardrobeRoute: Hashable {
    /// Screen 05 from the edit's add button: the tips, Take photos, Choose from library.
    case addPieces
    /// Screen 06: the photos being cut out and read.
    case adding
    /// Screen 07: the review queue.
    case review
    /// The simple list of one chapter's pieces, until T6 builds the chapter page (S6).
    case chapter(name: String, number: Int)
}

extension EnvironmentValues {
    /// "Close and keep your progress" on screens 06 and 07: back to the edit. The edit pops to
    /// its first screen; onboarding asks the server again, which then opens the app on the edit.
    @Entry var closeToEdit: () -> Void = {}
}
