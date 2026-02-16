import Foundation
import SwiftData
import CloudKit

@Model
final class CachedFriend {
    @Attribute(.unique) var userID: String
    var username: String
    var displayName: String
    var cachedAt: Date

    init(userID: String, username: String, displayName: String) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.cachedAt = Date()
    }

    init(from result: SocialService.UserProfileResult) {
        self.userID = result.id
        self.username = result.username
        self.displayName = result.displayName
        self.cachedAt = Date()
    }

    func toUserProfileResult() -> SocialService.UserProfileResult {
        SocialService.UserProfileResult(
            id: userID,
            username: username,
            displayName: displayName,
            recordID: CKRecord.ID(recordName: userID)
        )
    }
}
