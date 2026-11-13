import Foundation

// Get the look, as the server sends it (PRD sections 6 to 8, screens 14 and 15).
// Claude describes each piece of an inspiration and finds the member's closest piece of the
// same kind. The member makes their version: nothing here proposes a look.

/// GET /me/inspirations: the home of Get the look.
struct GetTheLookPage: Decodable {
    let inspirations: [InspirationSummary]
    let toFind: [ToFindItem]
    let occasions: [NamedItem]
}

/// One inspiration in the home grid.
struct InspirationSummary: Decodable, Identifiable, Hashable {
    let id: Int
    /// reading, ready, or not read
    let status: String
    let thumb: String
    let occasion: Int?
    /// "4 of 5 yours": pieces Claude marked yours and pieces you filled. Close does not count.
    let owned: Int
    let total: Int
}

/// A missing piece marked as key: on the To find list.
struct ToFindItem: Decodable, Identifiable, Hashable {
    let id: Int
    let inspiration: Int
    let number: Int
    let description: String
    let kind: String?
    /// considering (bought and dropped pieces leave the list)
    let status: String
    let searchedAt: String?
    /// In how many of your inspirations a piece like it is missing; nil when only this one.
    let inspirations: Int?
    /// The store search (T11): nil (not searched yet), searching, done, failed.
    let searchStatus: String?
    let searchMessage: String?
    /// Products found, and kept by the member.
    let found: Int
    let kept: Int
    /// A kept product's picture, or the first one found.
    let image: String?

    var words: String {
        ToFindWords.status(searchStatus: searchStatus, found: found, kept: kept, inspirations: inspirations)
    }
    /// Not searched yet, or the search did not work: Find it shows on the row.
    var canFindIt: Bool { searchStatus == nil || searchStatus == "failed" }
}

/// A key piece's search, on Your version (T11).
struct KeySearch: Decodable, Hashable {
    let id: Int
    let searchStatus: String?
    let searchMessage: String?
    let found: Int
    let kept: Int
    let image: String?

    var words: String { ToFindWords.status(searchStatus: searchStatus, found: found, kept: kept) }
}

/// One inspiration and your version of it (screen 15).
struct Inspiration: Decodable, Identifiable {
    struct LookRef: Decodable, Hashable {
        let id: Int
        let number: Int?
    }

    let id: Int
    let status: String
    let photo: String
    let thumb: String
    let link: String?
    /// "Pinterest", "Instagram" or the site's name, from the link.
    let source: String?
    let note: String?
    let occasion: Int?
    /// The look saved from it, if any.
    let look: LookRef?
    let owned: Int
    let total: Int
    let pieces: [InspirationPiece]

    var isReading: Bool { status == "reading" }
    var notRead: Bool { status == "not read" }
}

/// One piece Claude saw in the inspiration, and yours for it.
struct InspirationPiece: Decodable, Identifiable, Hashable {
    struct Pin: Decodable, Hashable {
        /// The piece's centre, in percent of the photo's width and height.
        let x: Double
        let y: Double
    }

    /// The pin number on the photo.
    let number: Int
    /// Like "Grey oversized blazer".
    let description: String
    let kind: String?
    let colour: String?
    let shape: String?
    let pin: Pin?
    /// yours, close, missing, or filled (you chose one of your own pieces for it).
    let match: String
    /// Your piece standing in for it. None for a missing piece.
    let piece: Piece?
    /// For a missing piece: your nearest piece of that kind, if you have one.
    let nearest: Piece?
    /// For a missing piece: in how many of your inspirations a piece like it is missing.
    let inspirations: Int?
    let key: Bool
    let removed: Bool
    /// A key piece's To find row and its search (T11).
    let toFind: KeySearch?

    var id: Int { number }
    var isMissing: Bool { match == "missing" }
}
