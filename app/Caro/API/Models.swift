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

    var isAdmin: Bool { role == .admin }

    /// For the profile button in the masthead: "M".
    var initial: String { String(name.prefix(1)).uppercased() }
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
