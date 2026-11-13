import UIKit

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

// MARK: Find it and To find (T11)

extension WardrobeStore {
    func findIt(_ id: Int) async throws -> FindItPage {
        try await api.findIt(id)
    }

    /// Find it, or Search again, with your own words if given: one AI action, in the background.
    func searchAgain(_ id: Int, words: String? = nil) async throws -> FindItPage {
        try await api.searchAgain(id, words: words)
    }

    /// Keep (swipe right) or discard (swipe left) a product; nil undecides.
    func decide(_ id: Int, result: Int, decision: String?) async throws -> FindItPage {
        try await api.decide(id, result: result, decision: decision)
    }

    /// Bought: the cropped store picture is cut out on the iPhone and the piece goes into the
    /// edit, confirmed. The edit is updated in the background.
    func bought(_ id: Int, result: Int, picture: UIImage) async throws -> Piece {
        guard let prepared = await PhotoPrep.prepare(picture) else {
            throw APIError.refused("Caro could not read this picture. Try again.")
        }
        let piece = try await api.bought(id, result: result, photo: prepared.photo, cutout: prepared.cutout)
        ImageCache.shared.keep(prepared.preview, for: piece.images.thumb)
        Task { await load() }
        return piece
    }

    /// No longer looking for it: it leaves To find.
    func dropToFind(_ id: Int) async throws {
        try await api.dropToFind(id)
    }
}

/// The screens pushed on top of Get the look.
enum GetTheLookRoute: Hashable {
    /// One inspiration and your version of it (screen 15).
    case inspiration(id: Int)
    /// Find it: the products found for one key piece (S11, T11).
    case findIt(id: Int)
}
