import Foundation

// Find it and To find, as the server sends them (PRD sections 7 and 8, screen S11, T11).
// Caro searches the member's stores for one key piece, only on their tap. Claude only looks
// up what the stores list; it never recommends.

/// GET /me/to-find/:id: the Find it page for one key piece.
struct FindItPage: Decodable, Identifiable {
    struct InspirationRef: Decodable, Hashable {
        let id: Int
        let thumb: String
    }

    let id: Int
    /// considering, bought, or dropped
    let status: String
    let inspiration: InspirationRef
    let number: Int
    /// Like "Black leather shoulder bag".
    let description: String
    let kind: String?
    /// nil (not searched yet), searching, done, failed
    let searchStatus: String?
    /// Why the last search did not work, in words to show.
    let searchMessage: String?
    let searchedAt: Date?
    /// The words searched with: Caro's description of the piece, or the member's own.
    let searchWords: String
    let ownWords: Bool
    /// While searching: each store and how it is doing. Nil otherwise.
    let progress: [StoreProgress]?
    /// Up to three per store, the kept ones first. Discarded ones are not sent.
    let results: [StoreResult]
    /// The member's country, for prices in their own format.
    let country: String?
    /// The stores searched.
    let stores: [String]
    /// "Arket has no online shop in the Netherlands, so it was not searched."
    let notSearched: [String]
    /// The piece added to the edit when bought.
    let piece: Piece?

    var isSearching: Bool { searchStatus == "searching" }
    var isBought: Bool { status == "bought" }
}

/// One store while Find it searches it.
struct StoreProgress: Decodable, Hashable {
    let store: String
    /// searching, done, or failed
    let status: String
    let found: Int
}

/// One product a store lists for the piece.
struct StoreResult: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    /// The store's name, like COS.
    let store: String
    let priceCents: Int?
    let currency: String?
    /// The product page in the store, opened in Safari inside the app.
    let url: String
    /// The picture through the server, like /me/to-find/3/results/12/image.
    let image: String?
    let foundAt: Date
    /// kept, discarded, or nil (not decided yet)
    let decision: String?

    var isKept: Bool { decision == "kept" }
}

/// Prices in the member's own format: "€ 89,00" in the Netherlands, "$89.00" in the US.
enum PriceText {
    static func text(cents: Int?, currency: String?, country: String?) -> String? {
        guard let cents, let currency else { return nil }
        let locale = Locale(identifier: "en_\(country ?? "US")")
        return (Decimal(cents) / 100).formatted(.currency(code: currency).locale(locale))
    }
}

/// How a piece on To find is doing, in words: "In 3 inspirations · 5 found".
enum ToFindWords {
    /// - searchStatus: nil, searching, done or failed
    /// - found, kept: products found, and kept by the member
    static func status(searchStatus: String?, found: Int = 0, kept: Int = 0, inspirations: Int? = nil) -> String {
        let state: String
        switch searchStatus {
        case "searching": state = "searching your stores"
        case "failed": state = "not searched"
        case "done":
            if kept > 0 {
                state = "\(kept) kept"
            } else {
                state = found == 0 ? "nothing found" : "\(found) found"
            }
        default: state = "not searched yet"
        }
        if let count = inspirations {
            return "In \(count) inspirations · \(state)"
        }
        return state.prefix(1).uppercased() + state.dropFirst()
    }
}
