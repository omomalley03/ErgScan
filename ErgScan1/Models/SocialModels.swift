import Foundation

// MARK: - Chup (Like) Info

struct ChupInfo {
    var count: Int
    var currentUserChupped: Bool
}

// MARK: - Comment Info

struct CommentInfo: Identifiable {
    let id: String
    let userID: String
    let username: String
    let text: String
    let timestamp: Date
    var heartCount: Int
    var currentUserHearted: Bool
}

// MARK: - Friend Profile

struct FriendProfile: Identifiable {
    let id: String // userID
    let username: String
    let displayName: String
}

// MARK: - Profile Relationship

enum ProfileRelationship {
    case friends
    case notFriends
    case requestSentByMe
    case requestSentToMe
}
