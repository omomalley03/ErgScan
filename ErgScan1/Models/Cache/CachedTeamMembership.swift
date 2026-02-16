import Foundation
import SwiftData

@Model
final class CachedTeamMembership {
    @Attribute(.unique) var membershipID: String
    var teamID: String
    var userID: String
    var username: String
    var displayName: String
    var roles: String
    var membershipRole: String
    var status: String
    var joinedAt: Date
    var cachedAt: Date

    init(from membership: TeamMembershipInfo) {
        self.membershipID = membership.id
        self.teamID = membership.teamID
        self.userID = membership.userID
        self.username = membership.username
        self.displayName = membership.displayName
        self.roles = membership.roles
        self.membershipRole = membership.membershipRole
        self.status = membership.status
        self.joinedAt = membership.joinedAt
        self.cachedAt = Date()
    }

    func toTeamMembershipInfo() -> TeamMembershipInfo {
        TeamMembershipInfo(
            id: membershipID,
            teamID: teamID,
            userID: userID,
            username: username,
            displayName: displayName,
            roles: roles,
            membershipRole: membershipRole,
            status: status,
            joinedAt: joinedAt
        )
    }
}
