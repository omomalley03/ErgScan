import Foundation

// MARK: - Team Info

struct TeamInfo: Identifiable, Hashable {
    let id: String              // CKRecord.recordName
    let name: String
    let createdByID: String     // appleUserID of creator
    let createdAt: Date
    var profilePicData: Data?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TeamInfo, rhs: TeamInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Team Membership Info

struct TeamMembershipInfo: Identifiable, Hashable {
    let id: String              // CKRecord.recordName
    let teamID: String
    let userID: String          // appleUserID
    let username: String
    let displayName: String
    let roles: String           // comma-separated: "rower", "rower,coach", etc.
    let membershipRole: String  // "admin", "member"
    let status: String          // "pending", "approved"
    let joinedAt: Date

    var roleList: [UserRole] { UserRole.fromCSV(roles) }
    func hasRole(_ role: UserRole) -> Bool { roleList.contains(role) }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TeamMembershipInfo, rhs: TeamMembershipInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Team Join Request (for admin approval UI)

struct TeamJoinRequest: Identifiable {
    let id: String              // CKRecord.recordName of the pending TeamMembership
    let teamID: String
    let teamName: String
    let userID: String
    let username: String
    let displayName: String
    let roles: String           // comma-separated requested roles
    let requestedAt: Date

    var roleList: [UserRole] { UserRole.fromCSV(roles) }
    func hasRole(_ role: UserRole) -> Bool { roleList.contains(role) }
}

// MARK: - Team Error

enum TeamError: LocalizedError {
    case notAuthenticated
    case alreadyMember
    case teamNotFound
    case notAdmin
    case noUsername

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in"
        case .alreadyMember: return "Already a member of this team"
        case .teamNotFound: return "Team not found"
        case .notAdmin: return "Only team admins can perform this action"
        case .noUsername: return "Username required to join a team"
        }
    }
}
