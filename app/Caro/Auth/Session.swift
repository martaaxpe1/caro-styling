import Foundation
import Observation

/// Who is signed in. One Session is shared by every screen (through the SwiftUI environment),
/// and the screens redraw themselves when it changes. @Observable is what makes that happen.
@Observable
final class Session {
    enum State: Equatable {
        /// Reading the Keychain and asking the server.
        case starting
        /// A token is saved, but the server could not be reached to check it.
        case notReachable
        case signedOut
        case signedIn(Member)
    }

    private(set) var state = State.starting
    private let api = APIClient()

    var member: Member? {
        if case .signedIn(let member) = state { member } else { nil }
    }

    /// When the app opens: is a token saved, and does the server still know it?
    func start() async {
        guard Keychain.readToken() != nil else {
            state = .signedOut
            return
        }

        state = .starting
        do {
            state = .signedIn(try await api.me())
        } catch APIError.signedOut {
            // The server no longer knows this token, for example after npm run reset-dev.
            endSession()
        } catch {
            state = .notReachable
        }
    }

    /// When the app comes back to the front: picks up changes, like access removed.
    func refresh() async {
        guard case .signedIn = state else { return }
        do {
            state = .signedIn(try await api.me())
        } catch APIError.signedOut {
            endSession()
        } catch {
            // Offline for a moment: stay as we are.
        }
    }

    /// After a save that changed the member, like a new name or set-up done.
    func update(_ member: Member) {
        guard case .signedIn = state else { return }
        state = .signedIn(member)
    }

    /// After a right code: the token goes into the Keychain, so it is remembered.
    func signedIn(token: String, member: Member) {
        Keychain.saveToken(token)
        state = .signedIn(member)
    }

    func signOut() async {
        // Ends the session on the server too. Signed out on the iPhone even if that fails.
        try? await api.signOut()
        endSession()
    }

    /// For a screen whose request failed: the message to show. If the session has ended,
    /// it also goes back to sign in.
    func message(for error: Error) -> String {
        if case APIError.signedOut = error {
            endSession()
        }
        return (error as? APIError)?.message ?? "Something went wrong. Try again."
    }

    private func endSession() {
        Keychain.deleteToken()
        // The next person on this iPhone never sees this member's photos.
        ImageCache.shared.removeAll()
        state = .signedOut
    }
}
