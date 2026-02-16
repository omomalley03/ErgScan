import Foundation
import SwiftData
import CloudKit
import Combine

@MainActor
class SocialCacheService: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()

    private var modelContext: ModelContext?
    private var currentUserID: String?

    // MARK: - Configuration

    func configure(context: ModelContext, userID: String) {
        self.modelContext = context
        self.currentUserID = userID
    }

    // MARK: - Staleness Thresholds

    static let feedStaleness: TimeInterval = 5 * 60       // 5 minutes
    static let friendsStaleness: TimeInterval = 15 * 60    // 15 minutes
    static let chupStaleness: TimeInterval = 2 * 60        // 2 minutes

    // MARK: - Cache Read Operations

    func getCachedFriendActivity() -> [SocialService.SharedWorkoutResult] {
        guard let context = modelContext else { return [] }
        let source = "friend"
        let descriptor = FetchDescriptor<CachedSharedWorkout>(
            predicate: #Predicate { $0.source == source },
            sortBy: [SortDescriptor(\.workoutDate, order: .reverse)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.map { $0.toSharedWorkoutResult() }
    }

    func getCachedFriends() -> [SocialService.UserProfileResult] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<CachedFriend>(
            sortBy: [SortDescriptor(\.username)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.map { $0.toUserProfileResult() }
    }

    func getCachedTeamActivity(teamID: String) -> [SocialService.SharedWorkoutResult] {
        guard let context = modelContext else { return [] }
        let source = "team:\(teamID)"
        let descriptor = FetchDescriptor<CachedSharedWorkout>(
            predicate: #Predicate { $0.source == source },
            sortBy: [SortDescriptor(\.workoutDate, order: .reverse)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.map { $0.toSharedWorkoutResult() }
    }

    func getCachedTeams() -> [TeamInfo] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<CachedTeam>(
            sortBy: [SortDescriptor(\.name)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.map { $0.toTeamInfo() }
    }

    func getCachedTeamMemberships(teamID: String) -> [TeamMembershipInfo] {
        guard let context = modelContext else { return [] }
        let approved = "approved"
        let descriptor = FetchDescriptor<CachedTeamMembership>(
            predicate: #Predicate { $0.teamID == teamID && $0.status == approved },
            sortBy: [SortDescriptor(\.username)]
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.map { $0.toTeamMembershipInfo() }
    }

    // MARK: - Cache Write Operations (with Zombie Pruning)

    func saveFriendActivity(_ workouts: [SocialService.SharedWorkoutResult], prune: Bool = true) {
        guard let context = modelContext else { return }

        if prune {
            // Prune zombie records: delete cached entries NOT in the new result set
            let returnedIDs = Set(workouts.map { $0.id })
            let source = "friend"
            let descriptor = FetchDescriptor<CachedSharedWorkout>(
                predicate: #Predicate { $0.source == source }
            )
            if let existing = try? context.fetch(descriptor) {
                for cached in existing {
                    if !returnedIDs.contains(cached.recordID) {
                        context.delete(cached)
                    }
                }
            }
        }

        // Upsert: update existing or insert new
        for workout in workouts {
            let recordID = workout.id
            let source = "friend"
            let descriptor = FetchDescriptor<CachedSharedWorkout>(
                predicate: #Predicate { $0.recordID == recordID && $0.source == source }
            )
            if let existing = try? context.fetch(descriptor).first {
                // Update existing cached record
                existing.ownerUsername = workout.ownerUsername
                existing.ownerDisplayName = workout.ownerDisplayName
                existing.workoutDate = workout.workoutDate
                existing.workoutType = workout.workoutType
                existing.totalTime = workout.totalTime
                existing.totalDistance = workout.totalDistance
                existing.averageSplit = workout.averageSplit
                existing.intensityZone = workout.intensityZone
                existing.isErgTest = workout.isErgTest
                existing.privacy = workout.privacy
                existing.submittedByCoxUsername = workout.submittedByCoxUsername
                existing.cachedAt = Date()
            } else {
                context.insert(CachedSharedWorkout(from: workout, source: "friend"))
            }
        }

        try? context.save()
    }

    func saveFriends(_ friends: [SocialService.UserProfileResult]) {
        guard let context = modelContext else { return }

        // Prune: remove friends no longer in the list
        let returnedIDs = Set(friends.map { $0.id })
        let descriptor = FetchDescriptor<CachedFriend>()
        if let existing = try? context.fetch(descriptor) {
            for cached in existing {
                if !returnedIDs.contains(cached.userID) {
                    context.delete(cached)
                }
            }
        }

        // Upsert
        for friend in friends {
            let userID = friend.id
            let upsertDescriptor = FetchDescriptor<CachedFriend>(
                predicate: #Predicate { $0.userID == userID }
            )
            if let existing = try? context.fetch(upsertDescriptor).first {
                existing.username = friend.username
                existing.displayName = friend.displayName
                existing.cachedAt = Date()
            } else {
                context.insert(CachedFriend(from: friend))
            }
        }

        try? context.save()
    }

    func saveTeamActivity(teamID: String, workouts: [SocialService.SharedWorkoutResult], prune: Bool = true) {
        guard let context = modelContext else { return }
        let source = "team:\(teamID)"

        if prune {
            let returnedIDs = Set(workouts.map { $0.id })
            let descriptor = FetchDescriptor<CachedSharedWorkout>(
                predicate: #Predicate { $0.source == source }
            )
            if let existing = try? context.fetch(descriptor) {
                for cached in existing {
                    if !returnedIDs.contains(cached.recordID) {
                        context.delete(cached)
                    }
                }
            }
        }

        for workout in workouts {
            let recordID = workout.id
            let descriptor = FetchDescriptor<CachedSharedWorkout>(
                predicate: #Predicate { $0.recordID == recordID && $0.source == source }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.ownerUsername = workout.ownerUsername
                existing.ownerDisplayName = workout.ownerDisplayName
                existing.workoutDate = workout.workoutDate
                existing.workoutType = workout.workoutType
                existing.totalTime = workout.totalTime
                existing.totalDistance = workout.totalDistance
                existing.averageSplit = workout.averageSplit
                existing.intensityZone = workout.intensityZone
                existing.isErgTest = workout.isErgTest
                existing.privacy = workout.privacy
                existing.submittedByCoxUsername = workout.submittedByCoxUsername
                existing.cachedAt = Date()
            } else {
                context.insert(CachedSharedWorkout(from: workout, source: source))
            }
        }

        try? context.save()
    }

    func saveTeams(_ teams: [TeamInfo]) {
        guard let context = modelContext else { return }

        let returnedIDs = Set(teams.map { $0.id })
        let descriptor = FetchDescriptor<CachedTeam>()
        if let existing = try? context.fetch(descriptor) {
            for cached in existing {
                if !returnedIDs.contains(cached.teamID) {
                    context.delete(cached)
                }
            }
        }

        for team in teams {
            let teamID = team.id
            let upsertDescriptor = FetchDescriptor<CachedTeam>(
                predicate: #Predicate { $0.teamID == teamID }
            )
            if let existing = try? context.fetch(upsertDescriptor).first {
                existing.name = team.name
                existing.cachedAt = Date()
                // Save profile pic to file system if present
                if let picData = team.profilePicData {
                    let filename = "team_\(teamID).jpg"
                    SocialCacheService.saveImageToCache(data: picData, filename: filename)
                    existing.profilePicFilename = filename
                }
            } else {
                let cached = CachedTeam(from: team)
                if let picData = team.profilePicData {
                    let filename = "team_\(teamID).jpg"
                    SocialCacheService.saveImageToCache(data: picData, filename: filename)
                    cached.profilePicFilename = filename
                }
                context.insert(cached)
            }
        }

        try? context.save()
    }

    func saveTeamMemberships(teamID: String, memberships: [TeamMembershipInfo]) {
        guard let context = modelContext else { return }

        let returnedIDs = Set(memberships.map { $0.id })
        let descriptor = FetchDescriptor<CachedTeamMembership>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? context.fetch(descriptor) {
            for cached in existing {
                if !returnedIDs.contains(cached.membershipID) {
                    context.delete(cached)
                }
            }
        }

        for membership in memberships {
            let membershipID = membership.id
            let upsertDescriptor = FetchDescriptor<CachedTeamMembership>(
                predicate: #Predicate { $0.membershipID == membershipID }
            )
            if let existing = try? context.fetch(upsertDescriptor).first {
                existing.username = membership.username
                existing.displayName = membership.displayName
                existing.roles = membership.roles
                existing.membershipRole = membership.membershipRole
                existing.status = membership.status
                existing.cachedAt = Date()
            } else {
                context.insert(CachedTeamMembership(from: membership))
            }
        }

        try? context.save()
    }

    func getCachedMyMemberships() -> [TeamMembershipInfo] {
        guard let context = modelContext, let userID = currentUserID else { return [] }
        let descriptor = FetchDescriptor<CachedTeamMembership>(
            predicate: #Predicate { $0.userID == userID && $0.status == "approved" }
        )
        let cached = (try? context.fetch(descriptor)) ?? []
        return cached.map { $0.toTeamMembershipInfo() }
    }

    func saveMyMemberships(_ memberships: [TeamMembershipInfo]) {
        guard let context = modelContext, let userID = currentUserID else { return }

        // Prune: remove cached memberships for this user that are no longer in the list
        let returnedIDs = Set(memberships.map { $0.id })
        let descriptor = FetchDescriptor<CachedTeamMembership>(
            predicate: #Predicate { $0.userID == userID }
        )
        if let existing = try? context.fetch(descriptor) {
            for cached in existing {
                if !returnedIDs.contains(cached.membershipID) {
                    context.delete(cached)
                }
            }
        }

        // Upsert
        for membership in memberships {
            let membershipID = membership.id
            let upsertDescriptor = FetchDescriptor<CachedTeamMembership>(
                predicate: #Predicate { $0.membershipID == membershipID }
            )
            if let existing = try? context.fetch(upsertDescriptor).first {
                existing.username = membership.username
                existing.displayName = membership.displayName
                existing.roles = membership.roles
                existing.membershipRole = membership.membershipRole
                existing.status = membership.status
                existing.cachedAt = Date()
            } else {
                context.insert(CachedTeamMembership(from: membership))
            }
        }

        try? context.save()
    }

    // MARK: - Staleness Checks

    func isCacheStale(category: String, threshold: TimeInterval) -> Bool {
        guard let context = modelContext else { return true }
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.category == category }
        )
        guard let meta = try? context.fetch(descriptor).first else { return true }
        return Date().timeIntervalSince(meta.lastSyncedAt) > threshold
    }

    func getLastSyncDate(category: String) -> Date? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.category == category }
        )
        return (try? context.fetch(descriptor).first)?.lastSyncedAt
    }

    func updateSyncTimestamp(category: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.category == category }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.lastSyncedAt = Date()
        } else {
            context.insert(SyncMetadata(category: category, lastSyncedAt: Date()))
        }
        try? context.save()
    }

    // MARK: - Cache Cleanup

    func clearAllCache() {
        guard let context = modelContext else { return }
        try? context.delete(model: CachedFriend.self)
        try? context.delete(model: CachedSharedWorkout.self)
        try? context.delete(model: CachedTeam.self)
        try? context.delete(model: CachedTeamMembership.self)
        try? context.delete(model: SyncMetadata.self)
        try? context.save()
    }

    // MARK: - Image File Helpers

    nonisolated private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    nonisolated static func saveImageToCache(data: Data, filename: String) {
        let url = cacheDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
    }

    nonisolated static func loadImageFromCache(filename: String?) -> Data? {
        guard let filename = filename else { return nil }
        let url = cacheDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }
}
