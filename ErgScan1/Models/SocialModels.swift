import Foundation

// MARK: - Chup (Like) Info

enum ChupType {
    case none
    case regular
    case big
}

struct ChupInfo {
    var totalCount: Int
    var regularCount: Int
    var bigChupCount: Int
    var currentUserChupType: ChupType
}

struct ChupUser: Identifiable {
    let id: String  // userID
    let username: String
    let displayName: String?
    let isBigChup: Bool
    let timestamp: Date
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
