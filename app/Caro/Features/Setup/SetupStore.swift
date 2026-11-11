import Foundation
import Observation

/// The member's set-up (onboarding steps 1 to 5), shared by onboarding and Settings.
/// One SetupStore lives in the environment, like Session. Screens read `setup` and save
/// through it; every save answers with the whole set-up from the server, which replaces
/// what is here, so the screens always show what the server holds.
@Observable
final class SetupStore {
    private(set) var setup: Setup?
    /// Why the set-up could not be loaded, shown with Try again.
    private(set) var loadError: String?

    private let session: Session
    let api = APIClient()

    init(session: Session) {
        self.session = session
    }

    /// Loads the set-up from the server. Forgets another member's set-up first.
    func load() async {
        if setup?.member.id != session.member?.id {
            setup = nil
        }
        loadError = nil
        do {
            apply(try await api.setup())
        } catch {
            loadError = session.message(for: error)
        }
    }

    /// Takes the server's answer to a save, and tells the session about the member in it
    /// (a new name, or set-up done, which shows the app instead of onboarding).
    func apply(_ new: Setup) {
        setup = new
        session.update(new.member)
    }

    /// Runs one save. Returns the message to show if it failed, or nil when it worked.
    func save(_ action: (APIClient) async throws -> Setup) async -> String? {
        do {
            apply(try await action(api))
            return nil
        } catch {
            return session.message(for: error)
        }
    }

    /// The message for a failed request that is not a save, like a search.
    func message(for error: Error) -> String {
        session.message(for: error)
    }
}
