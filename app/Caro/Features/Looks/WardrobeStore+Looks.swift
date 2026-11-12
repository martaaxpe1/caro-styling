import Foundation

/// Looks, in the same store as the wardrobe: a look is made of the wardrobe's pieces, and
/// saving one changes the edit ("not styled yet") and the piece pages ("In 1 look").
/// The screens ask the server again each time they show, so they always show what it holds.
extension WardrobeStore {
    func looks() async throws -> LooksPage {
        try await api.looks()
    }

    func stylingTable() async throws -> StylingTable {
        try await api.stylingTable()
    }

    func lookPage(_ lookID: Int) async throws -> LookPage {
        try await api.lookPage(lookID)
    }

    /// Saves a new look (lookID nil) or changes one. The edit is updated in the background.
    func saveLook(_ draft: LookDraft, lookID: Int?) async throws -> Look {
        let look = try await api.saveLook(draft, lookID: lookID)
        Task { await load() }
        return look
    }

    func deleteLook(_ lookID: Int) async throws {
        try await api.deleteLook(lookID)
        Task { await load() }
    }
}
