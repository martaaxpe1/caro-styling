import Foundation

/// Something went wrong talking to the server. `message` is what the screen shows.
enum APIError: Error {
    /// The server could not be reached: no connection, or the server is not running.
    case notReachable
    /// The session ended: signed out on the server, access removed, or the database was reset.
    case signedOut
    /// The server said no, with its own words, like "That code is not right. 4 tries left."
    case refused(String)
    /// The same look rule: "You already have this look: No. 12.", with that look.
    case sameLook(String, lookID: Int, number: Int)

    var message: String {
        switch self {
        case .notReachable:
            #if DEBUG
            "Caro cannot reach the server. Is npm run dev running on your Mac?"
            #else
            "Caro cannot reach the server. Check your connection and try again."
            #endif
        case .signedOut:
            "You are signed out. Sign in again."
        case .refused(let message), .sameLook(let message, _, _):
            message
        }
    }
}

/// Talks to the Caro server. One function per server route.
/// Every request carries the session token from the Keychain, when there is one,
/// so the server knows who is asking.
struct APIClient {
    var baseURL = AppConfig.serverURL

    // MARK: Signing in

    /// POST /auth/code: asks for a 6-digit code by email.
    func requestCode(email: String) async throws {
        let _: OK = try await send("POST", "auth/code", body: ["email": email])
    }

    /// POST /auth/verify: a right code gives back a session token.
    func verifyCode(email: String, code: String) async throws -> SignedIn {
        try await send("POST", "auth/verify", body: ["email": email, "code": code])
    }

    /// GET /me: who the saved token belongs to.
    func me() async throws -> Member {
        let response: MemberResponse = try await send("GET", "me")
        return response.member
    }

    /// POST /auth/sign-out: ends this session on the server.
    func signOut() async throws {
        let _: OK = try await send("POST", "auth/sign-out")
    }

    // MARK: Your data (T8)

    /// GET /me/export: Download everything. The server sends a zip of the member's data and
    /// photos; it is saved in the app's temporary folder, and its address on the iPhone is returned.
    func downloadEverything() async throws -> URL {
        var request = URLRequest(url: baseURL.appending(path: "me/export"))
        request.timeoutInterval = 120
        if let token = Keychain.readToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let file: URL
        let response: URLResponse
        do {
            (file, response) = try await URLSession.shared.download(for: request)
        } catch {
            throw APIError.notReachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw APIError.signedOut
        }
        guard (200..<300).contains(status) else {
            let data = (try? Data(contentsOf: file)) ?? Data()
            let message = (try? Self.decoder.decode(ErrorResponse.self, from: data))?.error
            throw APIError.refused(message ?? "Something went wrong. Try again.")
        }

        // The download lands under a random name; give it the server's name, like caro-2026-11-12.zip.
        let name = response.suggestedFilename ?? "caro.zip"
        let saved = FileManager.default.temporaryDirectory.appending(path: name)
        try? FileManager.default.removeItem(at: saved)
        try FileManager.default.moveItem(at: file, to: saved)
        return saved
    }

    /// DELETE /me: Delete account. Everything goes, photos included, and the session ends.
    func deleteAccount() async throws {
        let _: OK = try await send("DELETE", "me")
    }

    // MARK: Admin

    /// GET /admin: members and pending invitations.
    func adminOverview() async throws -> AdminOverview {
        try await send("GET", "admin")
    }

    /// POST /admin/invitations: add person.
    func invite(name: String, email: String) async throws {
        let _: InvitationResponse = try await send("POST", "admin/invitations", body: ["name": name, "email": email])
    }

    func resendInvitation(id: Int) async throws {
        let _: InvitationResponse = try await send("POST", "admin/invitations/\(id)/resend")
    }

    func cancelInvitation(id: Int) async throws {
        let _: OK = try await send("POST", "admin/invitations/\(id)/cancel")
    }

    func removeAccess(memberID: Int) async throws {
        let _: AdminMemberResponse = try await send("POST", "admin/members/\(memberID)/remove")
    }

    func restoreAccess(memberID: Int) async throws {
        let _: AdminMemberResponse = try await send("POST", "admin/members/\(memberID)/restore")
    }

    // MARK: Set-up (onboarding steps 1 to 5, and Settings)

    /// Calls that ask Claude or a weather service can take a while the first time.
    private static let slowTimeout: TimeInterval = 75
    /// A photo and its cut-out are a few megabytes, which takes a moment on a slow connection.
    private static let uploadTimeout: TimeInterval = 90

    /// GET /me/setup: everything the five steps and Settings show.
    func setup() async throws -> Setup {
        try await send("GET", "me/setup")
    }

    /// PUT /me/name: step 1.
    func saveName(_ name: String) async throws -> Setup {
        try await send("PUT", "me/name", body: ["name": name])
    }

    /// GET /places?q=: city search for step 2.
    func searchCities(_ query: String) async throws -> [City] {
        let response: CitiesResponse = try await send("GET", "places", query: [URLQueryItem(name: "q", value: query)])
        return response.cities
    }

    /// PUT /me/place: step 2. In Settings, a new city goes with its new year.
    func savePlace(_ choice: PlaceChoice, seasons: [Season]? = nil) async throws -> Setup {
        let body = PlaceBody(
            cityId: choice.city.id,
            currency: choice.currency,
            dateOrder: choice.dateOrder,
            sizeSystem: choice.sizeSystem,
            seasons: seasons
        )
        return try await send("PUT", "me/place", body: body)
    }

    /// GET /me/year: the typical weather and the proposed years, for the member's city
    /// or for a city they are moving to.
    func year(cityID: Int? = nil) async throws -> YearProposal {
        let query = cityID.map { [URLQueryItem(name: "cityId", value: String($0))] } ?? []
        return try await send("GET", "me/year", query: query, timeout: Self.slowTimeout)
    }

    /// PUT /me/year: step 3.
    func saveYear(_ seasons: [Season]) async throws -> Setup {
        try await send("PUT", "me/year", body: ["seasons": seasons])
    }

    /// PUT /me/sections: step 4, saved on each tap.
    func saveSections(_ sections: Sections) async throws -> Setup {
        try await send("PUT", "me/sections", body: sections)
    }

    /// POST /me/onboarding/stores-done: Continue on step 4, with at least one section.
    func storesDone() async throws -> Setup {
        try await send("POST", "me/onboarding/stores-done")
    }

    /// POST /me/onboarding/skip-stores: Skip for now.
    func skipStores() async throws -> Setup {
        try await send("POST", "me/onboarding/skip-stores")
    }

    /// PUT /me/occasions: the member's own list, one to eight. In onboarding this is the
    /// last step of set-up.
    func saveOccasions(_ occasions: [Occasion]) async throws -> Setup {
        try await send("PUT", "me/occasions", body: ["occasions": occasions])
    }

    /// POST /me/stores/find: Caro looks the store up for the member's country (an AI action).
    func findStore(name: String) async throws -> FoundStore {
        let response: FoundStoreResponse = try await send("POST", "me/stores/find", body: ["name": name], timeout: Self.slowTimeout)
        return response.store
    }

    /// POST /me/stores: add what was found, after the member confirms it.
    func addStore(_ store: FoundStore) async throws -> Setup {
        try await send("POST", "me/stores", body: store)
    }

    /// PUT /me/stores/:id: the store's site for the member's new country.
    func replaceWebsite(of storeID: Int, with found: FoundStore) async throws -> Setup {
        try await send("PUT", "me/stores/\(storeID)", body: found)
    }

    /// DELETE /me/stores/:id
    func removeStore(id: Int) async throws -> Setup {
        try await send("DELETE", "me/stores/\(id)")
    }

    // MARK: The wardrobe (onboarding step 6 and the edit)

    /// GET /me/wardrobe: progress, pieces waiting, chapters with counts.
    func wardrobe() async throws -> Wardrobe {
        try await send("GET", "me/wardrobe")
    }

    /// GET /me/pieces?status=pending: the review queue, oldest first.
    func reviewQueue() async throws -> ReviewQueue {
        try await send("GET", "me/pieces", query: [URLQueryItem(name: "status", value: "pending")])
    }

    /// GET /me/pieces?chapter=: the counted pieces of one chapter, newest first, with what the
    /// filters need.
    func chapter(_ chapter: String) async throws -> ChapterPage {
        try await send("GET", "me/pieces", query: [URLQueryItem(name: "chapter", value: chapter)])
    }

    /// GET /me/pieces/:id: one piece for its page, with the looks it is in.
    func piecePage(_ pieceID: Int) async throws -> PiecePage {
        try await send("GET", "me/pieces/\(pieceID)")
    }

    /// PUT /me/pieces/:id/status: maybe, or no longer a maybe.
    func setStatus(of pieceID: Int, to status: Piece.Status) async throws -> Piece {
        let response: PieceResponse = try await send("PUT", "me/pieces/\(pieceID)/status", body: ["status": status.rawValue])
        return response.piece
    }

    /// GET /me/wardrobe/overview: the facts of the wardrobe overview.
    func overview() async throws -> Overview {
        try await send("GET", "me/wardrobe/overview")
    }

    /// GET /me/wardrobe/seasons-to-check: the pieces with new seasons, by warmth.
    func seasonsCheck() async throws -> SeasonsCheck {
        try await send("GET", "me/wardrobe/seasons-to-check")
    }

    /// POST /me/wardrobe/seasons-to-check: confirms them, with the seasons for each warmth.
    func confirmSeasons(_ groups: [String: [Int]]) async throws -> Wardrobe {
        let response: ConfirmedSeasonsResponse = try await send("POST", "me/wardrobe/seasons-to-check", body: groups)
        return response.wardrobe
    }

    /// GET /lists: the fixed lists for the details.
    func lists() async throws -> PieceLists {
        try await send("GET", "lists")
    }

    /// POST /me/pieces: a new piece, from the photo (JPEG) and the cut-out (PNG), if anything lifted.
    /// The pictures travel as base64: the bytes of each file written as text, inside the JSON.
    func addPiece(photo: Data, cutout: Data?) async throws -> Piece {
        let body = PhotoBody(photo: photo.base64EncodedString(), cutout: cutout?.base64EncodedString())
        let response: PieceResponse = try await send("POST", "me/pieces", body: body, timeout: Self.uploadTimeout)
        return response.piece
    }

    /// PUT /me/pieces/:id/photo: retake. A new photo, the same details.
    func retakePhoto(of pieceID: Int, photo: Data, cutout: Data?) async throws -> Piece {
        let body = PhotoBody(photo: photo.base64EncodedString(), cutout: cutout?.base64EncodedString())
        let response: PieceResponse = try await send("PUT", "me/pieces/\(pieceID)/photo", body: body, timeout: Self.uploadTimeout)
        return response.piece
    }

    /// POST /me/pieces/:id/rotate: turns the pictures a quarter turn clockwise.
    func rotatePiece(_ pieceID: Int) async throws -> Piece {
        let response: PieceResponse = try await send("POST", "me/pieces/\(pieceID)/rotate", timeout: 30)
        return response.piece
    }

    /// PUT /me/pieces/:id: confirm, or mark as maybe, with the details the member checked.
    func savePiece(_ pieceID: Int, details: PieceDetails) async throws -> SavedPiece {
        try await send("PUT", "me/pieces/\(pieceID)", body: details)
    }

    /// DELETE /me/pieces/:id: removes the piece and its photos.
    func removePiece(_ pieceID: Int) async throws -> WardrobeProgress {
        let response: RemovedResponse = try await send("DELETE", "me/pieces/\(pieceID)")
        return response.progress
    }

    // MARK: Looks (screens 12, 13 and S8)

    /// GET /me/looks: the looks, newest first.
    func looks() async throws -> LooksPage {
        try await send("GET", "me/looks")
    }

    /// GET /me/looks/table: the pieces the styling table chooses from.
    func stylingTable() async throws -> StylingTable {
        try await send("GET", "me/looks/table")
    }

    /// GET /me/looks/:id: one look for its page.
    func lookPage(_ lookID: Int) async throws -> LookPage {
        try await send("GET", "me/looks/\(lookID)")
    }

    /// POST /me/looks, or PUT /me/looks/:id to change one.
    func saveLook(_ draft: LookDraft, lookID: Int?) async throws -> Look {
        let response: LookResponse
        if let lookID {
            response = try await send("PUT", "me/looks/\(lookID)", body: draft)
        } else {
            response = try await send("POST", "me/looks", body: draft)
        }
        return response.look
    }

    /// DELETE /me/looks/:id: the look goes; its pieces stay in the edit.
    func deleteLook(_ lookID: Int) async throws {
        let _: OK = try await send("DELETE", "me/looks/\(lookID)")
    }

    // MARK: Looks from a photo (S9) and a look's photos (S8)

    /// POST /me/looks/spot: which of your pieces Claude sees in the photo. Nothing is stored.
    /// Claude looks at the whole wardrobe, so this can take half a minute or more.
    func spotPieces(photo: Data) async throws -> SpottedLook {
        try await send("POST", "me/looks/spot", body: LookPhotoBody(photo: photo.base64EncodedString()), timeout: 150)
    }

    /// POST /me/looks/photo: saves the look with its photo, or adds the photo to the same look.
    func saveLookFromPhoto(_ draft: LookDraft, photo: Data) async throws -> PhotoLookSaved {
        let body = PhotoLookBody(photo: photo.base64EncodedString(), pieces: draft.pieces, occasions: draft.occasions, seasons: draft.seasons)
        return try await send("POST", "me/looks/photo", body: body, timeout: Self.uploadTimeout)
    }

    /// POST /me/looks/:id/photos: adds a photo of you wearing it.
    func addLookPhoto(_ lookID: Int, photo: Data) async throws -> Look {
        let response: LookResponse = try await send(
            "POST", "me/looks/\(lookID)/photos", body: LookPhotoBody(photo: photo.base64EncodedString()), timeout: Self.uploadTimeout
        )
        return response.look
    }

    /// DELETE /me/looks/:id/photos/:photoID: removes the photo and its files.
    func removeLookPhoto(_ lookID: Int, photoID: Int) async throws -> Look {
        let response: LookResponse = try await send("DELETE", "me/looks/\(lookID)/photos/\(photoID)")
        return response.look
    }

    // MARK: Get the look (screens 14 and 15)

    /// GET /me/inspirations: inspirations, To find, occasions.
    func getTheLook() async throws -> GetTheLookPage {
        try await send("GET", "me/inspirations")
    }

    /// POST /me/inspirations: a new inspiration from a photo (JPEG) or a Pinterest link.
    /// The server answers at once; Claude reads it in the background.
    func addInspiration(photo: Data?, link: String?, note: String?) async throws -> Inspiration {
        let body = NewInspirationBody(photo: photo?.base64EncodedString(), link: link, note: note)
        let response: InspirationResponse = try await send("POST", "me/inspirations", body: body, timeout: Self.uploadTimeout)
        return response.inspiration
    }

    func inspiration(_ id: Int) async throws -> Inspiration {
        let response: InspirationResponse = try await send("GET", "me/inspirations/\(id)")
        return response.inspiration
    }

    /// PUT /me/inspirations/:id: its link, note and occasion.
    func updateInspiration(_ id: Int, link: String?, note: String?, occasion: Int?) async throws -> Inspiration {
        let body = InspirationDetailsBody(link: link, note: note, occasion: occasion)
        let response: InspirationResponse = try await send("PUT", "me/inspirations/\(id)", body: body)
        return response.inspiration
    }

    /// PUT /me/inspirations/:id/pieces/:number: your piece for it (nil: back to Caro's match).
    func fillInspirationPiece(_ id: Int, number: Int, piece: Int?) async throws -> Inspiration {
        let response: InspirationResponse = try await send("PUT", "me/inspirations/\(id)/pieces/\(number)", body: FillBody(piece: piece))
        return response.inspiration
    }

    /// Takes a piece out of your version, or puts it back.
    func removeInspirationPiece(_ id: Int, number: Int, removed: Bool) async throws -> Inspiration {
        let response: InspirationResponse = try await send("PUT", "me/inspirations/\(id)/pieces/\(number)", body: ["removed": removed])
        return response.inspiration
    }

    /// Marks a missing piece as key (it goes on To find), or takes the mark off.
    func markInspirationPiece(_ id: Int, number: Int, key: Bool) async throws -> Inspiration {
        let response: InspirationResponse = try await send("PUT", "me/inspirations/\(id)/pieces/\(number)", body: ["key": key])
        return response.inspiration
    }

    /// POST /me/inspirations/:id/read: Try again, after Caro could not read it.
    func readInspirationAgain(_ id: Int) async throws -> Inspiration {
        let response: InspirationResponse = try await send("POST", "me/inspirations/\(id)/read")
        return response.inspiration
    }

    func deleteInspiration(_ id: Int) async throws {
        let _: OK = try await send("DELETE", "me/inspirations/\(id)")
    }

    /// POST /me/inspirations/:id/look: saves your version as a look, or changes the one saved before.
    func saveInspirationLook(_ id: Int, occasions: [Int], seasons: [Int]) async throws -> Look {
        let response: LookResponse = try await send("POST", "me/inspirations/\(id)/look", body: ["occasions": occasions, "seasons": seasons])
        return response.look
    }

    // MARK: Find it and To find (T11)

    /// GET /me/to-find/:id: the Find it page for one key piece.
    func findIt(_ id: Int) async throws -> FindItPage {
        let response: FindItResponse = try await send("GET", "me/to-find/\(id)")
        return response.toFind
    }

    /// POST /me/to-find/:id/search: Find it, or Search again. Runs in the background.
    func searchAgain(_ id: Int) async throws -> FindItPage {
        let response: FindItResponse = try await send("POST", "me/to-find/\(id)/search")
        return response.toFind
    }

    /// PUT /me/to-find/:id/results/:rid: keep (swipe right) or discard (swipe left); nil undecides.
    func decide(_ id: Int, result: Int, decision: String?) async throws -> FindItPage {
        let response: FindItResponse = try await send("PUT", "me/to-find/\(id)/results/\(result)", body: DecisionBody(decision: decision))
        return response.toFind
    }

    /// POST /me/to-find/:id/bought: the piece goes into the edit with the store's picture, cropped.
    func bought(_ id: Int, result: Int, photo: Data, cutout: Data?) async throws -> Piece {
        let body = BoughtBody(result: result, photo: photo.base64EncodedString(), cutout: cutout?.base64EncodedString())
        let response: PieceResponse = try await send("POST", "me/to-find/\(id)/bought", body: body, timeout: Self.uploadTimeout)
        return response.piece
    }

    /// PUT /me/to-find/:id: no longer looking for it.
    func dropToFind(_ id: Int) async throws {
        let _: OK = try await send("PUT", "me/to-find/\(id)", body: ["status": "dropped"])
    }

    /// PUT /admin/allowance: the monthly AI allowance, the same for every member.
    func setAllowance(_ allowance: Int) async throws -> AIUsage {
        let response: AIResponse = try await send("PUT", "admin/allowance", body: ["allowance": allowance])
        return response.ai
    }

    /// A piece's picture, from an address the server gave, like /me/pieces/12/thumb?v=ab12.
    /// A plain request with the session token: the photos are private.
    func imageRequest(for path: String) -> URLRequest? {
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let token = Keychain.readToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Sending

    private struct OK: Decodable {}
    private struct FindItResponse: Decodable { let toFind: FindItPage }
    private struct AIResponse: Decodable { let ai: AIUsage }
    private struct BoughtBody: Encodable {
        let result: Int
        let photo: String
        let cutout: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(result, forKey: .result)
            try container.encode(photo, forKey: .photo)
            try container.encode(cutout, forKey: .cutout)
        }

        private enum CodingKeys: String, CodingKey { case result, photo, cutout }
    }
    private struct DecisionBody: Encodable {
        let decision: String?

        // nil is sent as null: not decided.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(decision, forKey: .decision)
        }

        private enum CodingKeys: String, CodingKey { case decision }
    }
    private struct ErrorResponse: Decodable { let error: String }
    private struct MemberResponse: Decodable { let member: Member }
    private struct InvitationResponse: Decodable { let invitation: Invitation }
    private struct AdminMemberResponse: Decodable { let member: AdminMember }
    private struct CitiesResponse: Decodable { let cities: [City] }
    private struct FoundStoreResponse: Decodable { let store: FoundStore }
    private struct ConfirmedSeasonsResponse: Decodable { let wardrobe: Wardrobe }
    private struct PieceResponse: Decodable { let piece: Piece }
    private struct LookResponse: Decodable { let look: Look }
    private struct RemovedResponse: Decodable { let progress: WardrobeProgress }
    private struct LookPhotoBody: Encodable { let photo: String }
    private struct InspirationResponse: Decodable { let inspiration: Inspiration }
    private struct NewInspirationBody: Encodable {
        let photo: String?
        let link: String?
        let note: String?
    }
    /// The three are always sent; nil is sent as null, which clears it.
    private struct InspirationDetailsBody: Encodable {
        let link: String?
        let note: String?
        let occasion: Int?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(link, forKey: .link)
            try container.encode(note, forKey: .note)
            try container.encode(occasion, forKey: .occasion)
        }

        private enum CodingKeys: String, CodingKey { case link, note, occasion }
    }
    /// piece nil is sent as null: back to Caro's match.
    private struct FillBody: Encodable {
        let piece: Int?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(piece, forKey: .piece)
        }

        private enum CodingKeys: String, CodingKey { case piece }
    }
    private struct PhotoLookBody: Encodable {
        let photo: String
        let pieces: [Int]
        let occasions: [Int]
        let seasons: [Int]
    }
    private struct SameLookResponse: Decodable {
        struct Match: Decodable { let id: Int; let number: Int }
        let error: String
        let look: Match
    }

    private struct PhotoBody: Encodable {
        let photo: String
        let cutout: String?

        // A missing cut-out is sent as null: nothing lifted.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(photo, forKey: .photo)
            try container.encode(cutout, forKey: .cutout)
        }

        private enum CodingKeys: String, CodingKey { case photo, cutout }
    }

    private struct PlaceBody: Encodable {
        let cityId: Int
        let currency: String
        let dateOrder: DateOrder
        let sizeSystem: SizeSystem
        /// Left out when empty, so the server keeps the year as it is.
        let seasons: [Season]?
    }

    /// The server's dates are text like 2026-11-10T21:30:00Z.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Sends one request and turns the answer into `Response`, or throws an APIError.
    /// `body` is any data that can be written as JSON; `query` goes after the ? in the address.
    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: (any Encodable)? = nil,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = 10
    ) async throws -> Response {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if let token = Keychain.readToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.notReachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw APIError.signedOut
        }
        if status == 409, let same = try? Self.decoder.decode(SameLookResponse.self, from: data) {
            throw APIError.sameLook(same.error, lookID: same.look.id, number: same.look.number)
        }
        guard (200..<300).contains(status) else {
            let message = (try? Self.decoder.decode(ErrorResponse.self, from: data))?.error
            throw APIError.refused(message ?? "Something went wrong. Try again.")
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.refused("Caro could not read the server's answer.")
        }
    }
}
