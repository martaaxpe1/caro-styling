import Foundation

// Looks, as the server sends them (PRD sections 6 to 8). The member styles every look:
// nothing here, or on the server, proposes one.

/// A slot on the styling table. Each kind of piece fills one; the server says which.
enum Slot: String, CaseIterable, Hashable {
    case outerLayer = "outer layer"
    case top
    case bottom
    case onePiece = "one-piece"
    case shoes
    case bag
    case accessories

    /// The word in the rail of slots: Outer layer, Top, Bottom, Dress, Shoes, Bag, Accessories.
    var title: String {
        switch self {
        case .outerLayer: "Outer layer"
        case .top: "Top"
        case .bottom: "Bottom"
        case .onePiece: "Dress"
        case .shoes: "Shoes"
        case .bag: "Bag"
        case .accessories: "Accessories"
        }
    }

    /// For the tray: "Your shoes for autumn".
    var plural: String {
        switch self {
        case .outerLayer: "outer layers"
        case .top: "tops"
        case .bottom: "bottoms"
        case .onePiece: "dresses"
        case .shoes: "shoes"
        case .bag: "bags"
        case .accessories: "accessories"
        }
    }

    /// Only accessories can hold several pieces.
    var holdsSeveral: Bool { self == .accessories }
}

/// One saved look: its number, where it came from, its occasions, seasons and pieces.
struct Look: Decodable, Identifiable, Hashable {
    enum Source: String, Decodable {
        case built, photo, inspired

        /// As screen 13 writes it, under the look.
        var title: String {
            switch self {
            case .built: "Built"
            case .photo: "From your photo"
            case .inspired: "From an inspiration"
            }
        }
    }

    struct LookPiece: Decodable, Identifiable, Hashable {
        let id: Int
        let slot: String
        let name: String?
        let kind: String?
        let images: Piece.Images

        var hasCutout: Bool { images.cutout != nil }
    }

    /// A photo of the member wearing the look (T9). Addresses on the server, fetched with the
    /// session token like piece pictures.
    struct Photo: Decodable, Identifiable, Hashable {
        let id: Int
        let photo: String
        let thumb: String
    }

    let id: Int
    let number: Int
    let source: Source
    /// Occasion and season ids, in the member's order.
    let occasions: [Int]
    let seasons: [Int]
    /// In slot order: outer layer, top, bottom, dress, shoes, bag, accessories.
    let pieces: [LookPiece]
    /// Oldest first.
    let photos: [Photo]

    /// The same look rule (PRD section 8), as the server checks it: two looks are the same
    /// when their outer layer, top, bottom or dress, and shoes are the same pieces. Bag and
    /// accessories can change. Used on S9 to say so before saving; the server decides.
    static let mainSlots: Set<String> = ["outer layer", "top", "bottom", "one-piece", "shoes"]

    var mainPieces: Set<Int> {
        Set(pieces.filter { Self.mainSlots.contains($0.slot) }.map(\.id))
    }
}

/// GET /me/looks: the looks, newest first, with the member's occasions and seasons by name.
struct LooksPage: Decodable {
    let looks: [Look]
    let occasions: [NamedItem]
    let seasons: [NamedItem]
}

/// GET /me/looks/:id: one look for its page (S8).
struct LookPage: Decodable {
    let look: Look
    let occasions: [NamedItem]
    let seasons: [NamedItem]
}

/// GET /me/looks/table: what the styling table chooses from.
struct StylingTable: Decodable {
    /// Every counted piece in the edit, newest first.
    let pieces: [Piece]
    let occasions: [NamedItem]
    let seasons: [NamedItem]
    let currentSeason: NamedItem?
}

/// What Save look sends: the pieces chosen, and the occasions and seasons ticked.
/// The server works out each piece's slot from its kind.
struct LookDraft: Encodable {
    var pieces: [Int]
    var occasions: [Int]
    var seasons: [Int]
}

/// POST /me/looks/spot: the member's own pieces Claude saw in the photo, best first.
/// A sure piece comes ticked; a less sure one, or a second one for a slot, is asked about.
struct SpottedLook: Decodable {
    struct Spotted: Decodable, Identifiable {
        let piece: Piece
        let certainty: String
        let ticked: Bool

        var id: Int { piece.id }
    }

    /// Something in the photo that is not in the edit, like "Blue straight jeans".
    struct Other: Decodable, Hashable {
        let kind: String?
        let description: String
    }

    let spotted: [Spotted]
    let notInWardrobe: [Other]
    /// clear, partly hidden, too dark or blurry.
    let photoQuality: String?
}

/// What saving a look from a photo answers: the look, and whether the photo went to a look
/// the member already had.
struct PhotoLookSaved: Decodable {
    let look: Look
    let addedTo: Bool
}

/// Words for occasions in a sentence: "A look for the office".
enum OccasionWords {
    /// Caro's four read as part of a sentence; the member's own are written as they are.
    static func phrase(_ name: String) -> String {
        switch name.lowercased() {
        case "office": "the office"
        case "night out": "a night out"
        case "day out": "a day out"
        default: name.prefix(1).lowercased() + name.dropFirst()
        }
    }
}
