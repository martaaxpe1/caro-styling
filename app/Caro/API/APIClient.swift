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

    // MARK: Sending

    private struct OK: Decodable {}
    private struct ErrorResponse: Decodable { let error: String }
    private struct MemberResponse: Decodable { let member: Member }
    private struct InvitationResponse: Decodable { let invitation: Invitation }
    private struct AdminMemberResponse: Decodable { let member: AdminMember }

    /// The server's dates are text like 2026-11-10T21:30:00Z.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Sends one request and turns the answer into `Response`, or throws an APIError.
    private func send<Response: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 10

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
