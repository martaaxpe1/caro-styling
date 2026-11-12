import Foundation

/// Something went wrong talking to the server. `message` is what the screen shows.
enum APIError: Error {
    /// The server could not be reached: no connection, or the server is not running.
    case notReachable
    /// The session ended: signed out on the server, access removed, or the database was reset.
    case signedOut
    /// The server said no, with its own words, like "That code is not right. 4 tries left."
    case refused(String)

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
        case .refused(let message):
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

    /// GET /me/pieces?chapter=: the counted pieces of one chapter, newest first.
    func pieces(inChapter chapter: String) async throws -> [Piece] {
        let response: PiecesResponse = try await send("GET", "me/pieces", query: [URLQueryItem(name: "chapter", value: chapter)])
        return response.pieces
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

    /// PUT /me/pieces/:id: confirm, or mark as maybe, with the details the member checked.
    func savePiece(_ pieceID: Int, details: PieceDetails) async throws -> SavedPiece {
        try await send("PUT", "me/pieces/\(pieceID)", body: details)
    }

    /// DELETE /me/pieces/:id: removes the piece and its photos.
    func removePiece(_ pieceID: Int) async throws -> WardrobeProgress {
        let response: RemovedResponse = try await send("DELETE", "me/pieces/\(pieceID)")
        return response.progress
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
    private struct ErrorResponse: Decodable { let error: String }
    private struct MemberResponse: Decodable { let member: Member }
    private struct InvitationResponse: Decodable { let invitation: Invitation }
    private struct AdminMemberResponse: Decodable { let member: AdminMember }
    private struct CitiesResponse: Decodable { let cities: [City] }
    private struct FoundStoreResponse: Decodable { let store: FoundStore }
    private struct PiecesResponse: Decodable { let pieces: [Piece] }
    private struct PieceResponse: Decodable { let piece: Piece }
    private struct RemovedResponse: Decodable { let progress: WardrobeProgress }
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
