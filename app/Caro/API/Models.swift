import Foundation

// What the server sends back, as Swift types. Decodable turns the JSON into these.

/// The signed-in member, from GET /me and POST /auth/verify.
struct Member: Decodable, Equatable {
    enum Role: String, Decodable {
        case member, admin
    }

    enum Status: String, Decodable {
        case onboarding, active, removed
    }

    let id: Int
    let name: String
    let email: String
    let role: Role
    let status: Status
    let onboardingStep: Int
    let country: String?
    /// Looks and Get the look are open: 20 pieces reached once (PRD section 5). Stays true.
    let unlocked: Bool
    /// The member has added pieces, so the app opens on the edit instead of step 6.
    let wardrobeStarted: Bool

    var isAdmin: Bool { role == .admin }

    /// Onboarding until set-up is done and the first pieces are added.
    var showsOnboarding: Bool {
        status == .onboarding || (!wardrobeStarted && !unlocked)
    }

    /// For the profile button in the masthead: "M".
    var initial: String { String(name.prefix(1)).uppercased() }

    /// For previews in Xcode.
    static let preview = Member(id: 1, name: "Marta", email: "marta@example.com", role: .admin, status: .active, onboardingStep: 6, country: "NL", unlocked: false, wardrobeStarted: true)
}

/// POST /auth/verify: the session token, given once, and who it belongs to.
struct SignedIn: Decodable {
    let token: String
    let member: Member
}

/// GET /admin: everything the admin screen shows.
struct AdminOverview: Decodable {
    let members: [AdminMember]
    let invitations: [Invitation]
}

/// One row in the admin's member list. People and totals only, never photos.
struct AdminMember: Decodable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let role: Member.Role
    let status: Member.Status
    let city: String?
    let country: String?
    let joinedAt: Date
    let lastActiveAt: Date?
    let aiActionsThisMonth: Int
    let removedAt: Date?
    let deletedOn: Date?

    var isAdmin: Bool { role == .admin }
    var isRemoved: Bool { status == .removed }
}

/// A pending invitation.
struct Invitation: Decodable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let sentAt: Date
    let expiresAt: Date
}
