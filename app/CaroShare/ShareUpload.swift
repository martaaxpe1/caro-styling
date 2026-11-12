import Foundation

/// Sends what was shared to the Caro server: POST /me/inspirations, with the session token from
/// the shared Keychain. The server saves it and Claude reads it in the background, so this
/// answers in a few seconds. Returns nil when it went well, or the words to show.
enum ShareUpload {
    private struct Body: Encodable {
        let photo: String?
        let link: String?
        let note: String?
    }

    private struct Refusal: Decodable { let error: String }

    static func send(photo: Data?, link: String?, note: String?) async -> String? {
        guard let token = Keychain.readToken() else { return signIn }
        let server = Keychain.readServer() ?? AppConfig.serverURL
        var request = URLRequest(url: server.appending(path: "me/inspirations"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Body(photo: photo?.base64EncodedString(), link: link, note: note))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return "Caro cannot reach the server. Check your connection and try again."
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { return signIn }
        if (200..<300).contains(status) { return nil }
        return (try? JSONDecoder().decode(Refusal.self, from: data))?.error ?? "Something went wrong. Try again."
    }

    static let signIn = "Sign in to Caro first, then share again."
}
