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

extension ChupInfo {
    mutating func applyCurrentUserTransition(to newType: ChupType) {
        switch currentUserChupType {
        case .regular:
            regularCount = max(0, regularCount - 1)
        case .big:
            bigChupCount = max(0, bigChupCount - 1)
        case .none:
            break
        }

        switch newType {
        case .regular:
            regularCount += 1
        case .big:
            bigChupCount += 1
        case .none:
            break
        }

        currentUserChupType = newType
        totalCount = regularCount + bigChupCount
    }
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
