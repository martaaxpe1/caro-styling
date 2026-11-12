import Foundation

/// Get the look, in the same store as the wardrobe and looks: your version is made of the
/// wardrobe's pieces, and saving it makes a look.
extension WardrobeStore {
    func getTheLook() async throws -> GetTheLookPage {
        try await api.getTheLook()
    }

    func inspiration(_ id: Int) async throws -> Inspiration {
        try await api.inspiration(id)
    }

    /// A new inspiration from a photo in your library. Claude reads it in the background.
    func addInspiration(photo: Data) async throws -> Inspiration {
        try await api.addInspiration(photo: photo, link: nil, note: nil)
    }

    /// A new inspiration from a Pinterest link: the server takes the pin's image.
    func addInspiration(link: String) async throws -> Inspiration {
        try await api.addInspiration(photo: nil, link: link, note: nil)
    }

    func updateInspiration(_ inspiration: Inspiration, link: String?, note: String?, occasion: Int?) async throws -> Inspiration {
        try await api.updateInspiration(inspiration.id, link: link, note: note, occasion: occasion)
    }

    func fillInspirationPiece(_ id: Int, number: Int, piece: Int?) async throws -> Inspiration {
        try await api.fillInspirationPiece(id, number: number, piece: piece)
    }

    func removeInspirationPiece(_ id: Int, number: Int, removed: Bool) async throws -> Inspiration {
        try await api.removeInspirationPiece(id, number: number, removed: removed)
    }

    func markInspirationPiece(_ id: Int, number: Int, key: Bool) async throws -> Inspiration {
        try await api.markInspirationPiece(id, number: number, key: key)
    }

    func readInspirationAgain(_ id: Int) async throws -> Inspiration {
        try await api.readInspirationAgain(id)
    }

    func deleteInspiration(_ id: Int) async throws {
        try await api.deleteInspiration(id)
    }

    /// Saves your version as a look. The edit is updated in the background ("not styled yet").
    func saveInspirationLook(_ id: Int, occasions: [Int], seasons: [Int]) async throws -> Look {
        let look = try await api.saveInspirationLook(id, occasions: occasions, seasons: seasons)
        Task { await load() }
        return look
    }
}

/// The screens pushed on top of Get the look.
enum GetTheLookRoute: Hashable {
    /// One inspiration and your version of it (screen 15).
    case inspiration(id: Int)
}
