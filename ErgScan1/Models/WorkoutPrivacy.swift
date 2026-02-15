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

    /// Parses team IDs from a privacy string
    /// - Parameter privacyString: The privacy value from CloudKit
    /// - Returns: Array of team IDs, or empty if not team-specific
    static func parseTeamIDs(from privacyString: String) -> [String] {
        guard privacyString.hasPrefix("team:") else { return [] }
        let idsString = String(privacyString.dropFirst(5)) // Remove "team:" prefix
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
        } else if privacyString == "friends" {
            return friendIDs.contains(ownerID)
        } else if privacyString == "team" {
            // Generic team — access if user shares any team with owner
            return !userTeamIDs.isEmpty
        } else if privacyString.hasPrefix("team:") {
            // Specific teams
            let allowedTeamIDs = parseTeamIDs(from: privacyString)
            return !Set(allowedTeamIDs).intersection(userTeamIDs).isEmpty
        }

        // Default deny
        return false
    }
}
