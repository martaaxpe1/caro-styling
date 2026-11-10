import Foundation

/// Talks to the Caro server. One function per server route.
struct APIClient {
    var baseURL = AppConfig.serverURL

    /// What the server's /health route answers: {"ok": true}
    private struct HealthResponse: Decodable {
        let ok: Bool
    }

    /// Asks the server if it is there. True when it answers, false when it cannot be reached.
    func checkHealth() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return try JSONDecoder().decode(HealthResponse.self, from: data).ok
        } catch {
            return false
        }
    }
}
