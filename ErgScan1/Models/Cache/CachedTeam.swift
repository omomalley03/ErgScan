import Foundation
import SwiftData

@Model
final class CachedTeam {
    @Attribute(.unique) var teamID: String
    var name: String
    var createdByID: String
    var createdAt: Date
    var profilePicFilename: String?  // Stored in .cachesDirectory, NOT as Data blob
    var cachedAt: Date

    init(from team: TeamInfo) {
        self.teamID = team.id
        self.name = team.name
        self.createdByID = team.createdByID
        self.createdAt = team.createdAt
        self.cachedAt = Date()
    }

    func toTeamInfo() -> TeamInfo {
        TeamInfo(
            id: teamID,
            name: name,
            createdByID: createdByID,
            createdAt: createdAt,
            profilePicData: SocialCacheService.loadImageFromCache(filename: profilePicFilename)
        )
    }
}
