import Foundation

enum WorkoutPrivacy: String, CaseIterable, Identifiable, Codable {
    case privateOnly = "private"
    case friends = "friends"
    case team = "team"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .privateOnly: return "Private"
        case .friends: return "Friends"
        case .team: return "Team"
        }
    }

    var icon: String {
        switch self {
        case .privateOnly: return "lock.fill"
        case .friends: return "person.2.fill"
        case .team: return "person.3.fill"
        }
    }

    var description: String {
        switch self {
        case .privateOnly: return "Only you can see this workout"
        case .friends: return "Visible to your friends"
        case .team: return "Visible to your team members"
        }
    }

    // MARK: - Team-specific privacy helpers

    /// Creates a privacy string for specific team(s)
    /// - Parameter teamIDs: Array of team IDs to share with
    /// - Returns: Comma-separated string like "team:teamID1,teamID2"
    static func teamPrivacy(teamIDs: [String]) -> String {
        guard !teamIDs.isEmpty else { return WorkoutPrivacy.team.rawValue }
        return "team:" + teamIDs.joined(separator: ",")
    }

    /// Creates a privacy string for sharing with both friends and team(s)
    /// - Parameter teamIDs: Array of team IDs to share with
    /// - Returns: "friends+team" or "friends+team:teamID1,teamID2"
    static func friendsAndTeamPrivacy(teamIDs: [String]) -> String {
        guard !teamIDs.isEmpty else { return "friends+team" }
        return "friends+team:" + teamIDs.joined(separator: ",")
    }

    /// True if privacy includes the friends audience.
    static func includesFriends(_ privacyString: String) -> Bool {
        let normalized = privacyString.lowercased()
        return normalized == WorkoutPrivacy.friends.rawValue || normalized.hasPrefix("friends+team")
    }

    /// True if privacy includes the team audience.
    static func includesTeam(_ privacyString: String) -> Bool {
        let normalized = privacyString.lowercased()
        return normalized == WorkoutPrivacy.team.rawValue
            || normalized.hasPrefix("team:")
            || normalized.hasPrefix("friends+team")
    }

    /// True if privacy targets a specific team (or generic team visibility).
    static func includesTeam(_ privacyString: String, teamID: String) -> Bool {
        let normalized = privacyString.lowercased()
        if normalized == WorkoutPrivacy.team.rawValue || normalized == "friends+team" {
            return true
        }
        let teamIDs = parseTeamIDs(from: privacyString)
        if teamIDs.isEmpty {
            return includesTeam(privacyString)
        }
        return teamIDs.contains(teamID)
    }

    /// Parses team IDs from a privacy string
    /// - Parameter privacyString: The privacy value from CloudKit
    /// - Returns: Array of team IDs, or empty if not team-specific
    static func parseTeamIDs(from privacyString: String) -> [String] {
        let lowercased = privacyString.lowercased()
        let idsString: String
        if lowercased.hasPrefix("team:") {
            idsString = String(privacyString.dropFirst(5)) // Remove "team:" prefix
        } else if lowercased.hasPrefix("friends+team:") {
            idsString = String(privacyString.dropFirst(13)) // Remove "friends+team:" prefix
        } else {
            return []
        }
        return idsString.split(separator: ",").map { String($0) }
    }

    /// Checks if a privacy string grants access to a specific user
    /// - Parameters:
    ///   - privacyString: The privacy value from CloudKit
    ///   - userID: The user to check access for
    ///   - friendIDs: Set of friend IDs
    ///   - teamIDs: Set of team IDs the user belongs to
    /// - Returns: True if the user can see the workout
    static func canAccess(
        privacyString: String,
        userID: String,
        ownerID: String,
        friendIDs: Set<String>,
        userTeamIDs: Set<String>
    ) -> Bool {
        // Owner always has access
        if userID == ownerID { return true }

        // Parse privacy
        if privacyString == "private" {
            return false
        }

        let friendAllowed = includesFriends(privacyString) && friendIDs.contains(ownerID)

        var teamAllowed = false
        if includesTeam(privacyString) {
            let allowedTeamIDs = parseTeamIDs(from: privacyString)
            if allowedTeamIDs.isEmpty {
                // Generic team visibility
                teamAllowed = !userTeamIDs.isEmpty
            } else {
                teamAllowed = !Set(allowedTeamIDs).intersection(userTeamIDs).isEmpty
            }
        }

        return friendAllowed || teamAllowed
    }
}
