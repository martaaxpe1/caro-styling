import Foundation

// The wardrobe, as the server sends it (PRD sections 5, 6 and 8).

/// One piece of clothing, shoes, a bag or an accessory.
struct Piece: Decodable, Identifiable, Equatable, Hashable {
    enum Status: String, Codable {
        /// Waiting in the review queue.
        case pending, confirmed, maybe
    }

    /// How far Claude got with its suggested details.
    enum DetailsStatus: String, Decodable {
        case reading
        case suggested
        case notRead = "not read"
    }

    /// Addresses on the server, like /me/pieces/12/thumb?v=ab12. Fetched with the session token.
    struct Images: Decodable, Equatable, Hashable {
        let photo: String
        /// Empty when nothing lifted from the photo: the photo is shown on the tile colour.
        let cutout: String?
        let thumb: String

        /// The best picture to show large: the cut-out, or the photo.
        var large: String { cutout ?? photo }
    }

    let id: Int
    let status: Status
    let detailsStatus: DetailsStatus
    let name: String?
    let kind: String?
    let chapter: String?
    let slot: String?
    let colours: [String]
    let pattern: String?
    let material: String?
    let warmth: String?
    let formality: String?
    /// Season ids, in the order of the member's year.
    let seasons: [Int]
    /// Occasion ids, in the member's order.
    let occasions: [Int]
    let images: Images

    var hasCutout: Bool { images.cutout != nil }
}

/// Progress towards opening Looks and Get the look, worked out on the server.
struct WardrobeProgress: Decodable, Equatable {
    /// Confirmed and maybe pieces. Pieces waiting for review do not count.
    let pieces: Int
    let needed: Int
    let top: Bool
    let bottomOrOnePiece: Bool
    let shoes: Bool
    let unlocked: Bool

    var toGo: Int { max(needed - pieces, 0) }
}

/// GET /me/wardrobe: what the edit shows.
struct Wardrobe: Decodable, Equatable {
    struct Waiting: Decodable, Equatable {
        /// Claude is still reading their details.
        let reading: Int
        /// Ready for the member to confirm.
        let toReview: Int
    }

    let progress: WardrobeProgress
    let waiting: Waiting
    let chapters: [ChapterSummary]
}

/// One chapter of the edit with its count and its newest cut-outs.
struct ChapterSummary: Decodable, Identifiable, Equatable {
    let name: String
    let number: Int
    let count: Int
    let thumbs: [String]

    var id: String { name }
}

/// GET /me/pieces?status=pending: the review queue.
struct ReviewQueue: Decodable {
    let pieces: [Piece]
    /// The seasons proposed for each warmth: "light": [season ids], ...
    let seasonsByWarmth: [String: [Int]]
    /// The member's seasons and occasions, to show as chips.
    let seasons: [NamedItem]
    let occasions: [NamedItem]
}

/// A season or an occasion of the member's own: its id and name.
struct NamedItem: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
}

/// GET /lists: the fixed lists the details come from.
struct PieceLists: Decodable {
    struct Chapter: Decodable, Identifiable {
        let name: String
        let number: Int
        let kinds: [Kind]
        var id: String { name }
    }

    struct Kind: Decodable, Identifiable, Hashable {
        let name: String
        let slot: String
        var id: String { name }
    }

    let chapters: [Chapter]
    let colours: [String]
    let patterns: [String]
    let materials: [String]
    let warmth: [String]
    let formality: [String]

    func chapter(of kind: String?) -> Chapter? {
        chapters.first { chapter in chapter.kinds.contains { $0.name == kind } }
    }
}

/// What the member saves in the review: PUT /me/pieces/:id.
struct PieceDetails: Encodable, Equatable {
    var name: String
    var kind: String?
    var colours: [String]
    var pattern: String?
    var material: String?
    var warmth: String?
    var formality: String?
    var seasons: [Int]
    var occasions: [Int]
    var status: Piece.Status

    init(from piece: Piece) {
        name = piece.name ?? ""
        kind = piece.kind
        colours = piece.colours
        pattern = piece.pattern
        material = piece.material
        warmth = piece.warmth
        formality = piece.formality
        seasons = piece.seasons
        occasions = piece.occasions
        status = .confirmed
    }

    // Empty values are sent as null, so the server knows they were left empty on purpose.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(colours, forKey: .colours)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(material, forKey: .material)
        try container.encode(warmth, forKey: .warmth)
        try container.encode(formality, forKey: .formality)
        try container.encode(seasons, forKey: .seasons)
        try container.encode(occasions, forKey: .occasions)
        try container.encode(status, forKey: .status)
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, colours, pattern, material, warmth, formality, seasons, occasions, status
    }
}

/// PUT /me/pieces/:id answers with the piece, the progress, and whether this confirm just
/// opened Looks and Get the look.
struct SavedPiece: Decodable {
    let piece: Piece
    let progress: WardrobeProgress
    let justUnlocked: Bool
}

/// Words for chapters: "dresses and skirts" shows as "Dresses and skirts", number 1 as "01".
enum ChapterWords {
    static func title(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    static func number(_ number: Int) -> String {
        String(format: "%02d", number)
    }
}
