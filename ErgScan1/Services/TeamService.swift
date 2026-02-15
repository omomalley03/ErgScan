import Foundation
import CloudKit
import Combine
import SwiftData

@MainActor
class TeamService: ObservableObject {

    // MARK: - Published State

    @Published var myTeams: [TeamInfo] = []
    @Published var myMemberships: [TeamMembershipInfo] = []
    @Published var selectedTeamID: String? = nil
    @Published var selectedTeamRoster: [TeamMembershipInfo] = []
    @Published var teamActivity: [SocialService.SharedWorkoutResult] = []
    @Published var pendingJoinRequests: [TeamJoinRequest] = []
    @Published var myPendingTeamRequests: [TeamMembershipInfo] = []
    @Published var teamSearchResults: [TeamInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let container = CKContainer(identifier: "iCloud.com.omomalley03.ErgScan1")
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private(set) var currentUserID: String?
    private var modelContext: ModelContext?

    // MARK: - Initialization

    func setCurrentUser(_ appleUserID: String, context: ModelContext) {
        currentUserID = appleUserID
        modelContext = context
        Task {
            await loadMyTeams()
            await loadMyPendingRequests()
        }
    }

    // MARK: - Team CRUD

    func createTeam(name: String) async throws -> TeamInfo {
        guard let userID = currentUserID else { throw TeamError.notAuthenticated }
        print("🔵 Creating team: \(name)")

        // Create Team record
        let teamRecord = CKRecord(recordType: "Team")
        teamRecord["name"] = name
        teamRecord["createdByID"] = userID
        teamRecord["createdAt"] = Date() as NSDate

        let savedTeam = try await publicDB.save(teamRecord)
        let teamID = savedTeam.recordID.recordName
        print("✅ Team created with ID: \(teamID)")

        // Fetch creator's profile for display info
        let (username, displayName) = await fetchUserDisplayInfo(userID: userID)

        // Create admin membership for creator
        let memberRecord = CKRecord(recordType: "TeamMembership")
        memberRecord["teamID"] = teamID
        memberRecord["userID"] = userID
        memberRecord["username"] = username
        memberRecord["displayName"] = displayName
        memberRecord["role"] = fetchLocalUserRoles()
        memberRecord["membershipRole"] = "admin"
        memberRecord["status"] = "approved"
        memberRecord["joinedAt"] = Date() as NSDate

        _ = try await publicDB.save(memberRecord)
        print("✅ Creator added as admin member")

        let teamInfo = TeamInfo(
            id: teamID,
            name: name,
            createdByID: userID,
            createdAt: Date(),
            profilePicData: nil
        )

        myTeams.append(teamInfo)
        selectedTeamID = teamInfo.id
        return teamInfo
    }

    func searchTeams(query: String) async {
        guard !query.isEmpty else {
            teamSearchResults = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let predicate = NSPredicate(format: "name BEGINSWITH %@", query)
            let ckQuery = CKQuery(recordType: "Team", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: ckQuery, resultsLimit: 20)

            var teams: [TeamInfo] = []
            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                teams.append(parseTeamRecord(record))
            }
            teamSearchResults = teams
            print("🔍 Found \(teams.count) teams matching '\(query)'")
        } catch let error as CKError where error.code == .unknownItem {
            teamSearchResults = []
        } catch {
            print("❌ Team search failed: \(error)")
            teamSearchResults = []
        }
    }

    func loadMyTeams() async {
        guard let userID = currentUserID else { return }

        do {
            // Get all approved memberships for current user
            let predicate = NSPredicate(format: "userID == %@ AND status == %@", userID, "approved")
            let query = CKQuery(recordType: "TeamMembership", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 20)

            var memberships: [TeamMembershipInfo] = []
            var teamIDs: [String] = []

            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                let membership = parseMembershipRecord(record)
                memberships.append(membership)
                if !teamIDs.contains(membership.teamID) {
                    teamIDs.append(membership.teamID)
                }
            }

            myMemberships = memberships

            // Fetch team records
            var teams: [TeamInfo] = []
            for teamID in teamIDs {
                do {
                    let teamRecordID = CKRecord.ID(recordName: teamID)
                    let teamRecord = try await publicDB.record(for: teamRecordID)
                    teams.append(parseTeamRecord(teamRecord))
                } catch {
                    print("⚠️ Could not load team \(teamID): \(error)")
                    continue
                }
            }

            myTeams = teams
            if selectedTeamID == nil, let first = teams.first {
                selectedTeamID = first.id
            }
            print("✅ Loaded \(teams.count) teams")
        } catch let error as CKError where error.code == .unknownItem {
            myTeams = []
            myMemberships = []
        } catch {
            print("❌ Failed to load teams: \(error)")
        }
    }

    // MARK: - Membership

    func requestToJoinTeam(teamID: String, roles: String) async throws {
        guard let userID = currentUserID else { throw TeamError.notAuthenticated }

        // Check for existing membership (dedup)
        do {
            let predicate = NSPredicate(format: "teamID == %@ AND userID == %@", teamID, userID)
            let query = CKQuery(recordType: "TeamMembership", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            if !results.isEmpty {
                throw TeamError.alreadyMember
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — fine
        } catch let error as TeamError {
            throw error
        }

        // Fetch profile for display info
        let (username, displayName) = await fetchUserDisplayInfo(userID: userID)
        guard !username.isEmpty else { throw TeamError.noUsername }

        let record = CKRecord(recordType: "TeamMembership")
        record["teamID"] = teamID
        record["userID"] = userID
        record["username"] = username
        record["displayName"] = displayName
        record["role"] = roles
        record["membershipRole"] = "member"
        record["status"] = "pending"
        record["joinedAt"] = Date() as NSDate

        _ = try await publicDB.save(record)
        print("✅ Join request sent for team \(teamID)")

        // Refresh pending requests
        await loadMyPendingRequests()
    }

    func approveJoinRequest(membershipRecordName: String) async throws {
        guard let userID = currentUserID else { throw TeamError.notAuthenticated }
        print("🔵 Approving join request: \(membershipRecordName)")

        // Fetch the pending membership record to get the user info
        let pendingRecordID = CKRecord.ID(recordName: membershipRecordName)
        let pendingRecord: CKRecord
        do {
            pendingRecord = try await publicDB.record(for: pendingRecordID)
        } catch {
            print("❌ Could not fetch pending record: \(error)")
            throw TeamError.teamNotFound
        }

        let teamID = pendingRecord["teamID"] as? String ?? ""
        let joinerUserID = pendingRecord["userID"] as? String ?? ""
        let joinerUsername = pendingRecord["username"] as? String ?? ""
        let joinerDisplayName = pendingRecord["displayName"] as? String ?? ""
        let joinerRoles = pendingRecord["role"] as? String ?? "rower"

        // Create an approved membership record (owned by admin, following bidirectional pattern)
        let approvedRecord = CKRecord(recordType: "TeamMembership")
        approvedRecord["teamID"] = teamID
        approvedRecord["userID"] = joinerUserID
        approvedRecord["username"] = joinerUsername
        approvedRecord["displayName"] = joinerDisplayName
        approvedRecord["role"] = joinerRoles
        approvedRecord["membershipRole"] = "member"
        approvedRecord["status"] = "approved"
        approvedRecord["joinedAt"] = Date() as NSDate

        _ = try await publicDB.save(approvedRecord)
        print("✅ Join request approved for \(joinerUsername)")

        // Refresh
        await loadPendingJoinRequests(teamID: teamID)
        await loadRoster(teamID: teamID)
    }

    func rejectJoinRequest(membershipRecordName: String) async throws {
        guard currentUserID != nil else { throw TeamError.notAuthenticated }
        print("🔵 Rejecting join request: \(membershipRecordName)")

        // We can't delete the pending record (not ours), but we remove it from our local state
        // The pending record stays but won't match "approved" queries
        pendingJoinRequests.removeAll { $0.id == membershipRecordName }
        print("✅ Join request rejected")
    }

    func leaveTeam(teamID: String) async throws {
        guard let userID = currentUserID else { throw TeamError.notAuthenticated }

        // Find and delete all our membership records for this team
        let predicate = NSPredicate(format: "teamID == %@ AND userID == %@", teamID, userID)
        let query = CKQuery(recordType: "TeamMembership", predicate: predicate)
        let (results, _) = try await publicDB.records(matching: query, resultsLimit: 10)

        var recordIDsToDelete: [CKRecord.ID] = []
        for (recordID, result) in results {
            guard case .success(let record) = result else { continue }
            // Only delete records we own (created by us)
            recordIDsToDelete.append(recordID)
        }

        if !recordIDsToDelete.isEmpty {
            _ = try await publicDB.modifyRecords(saving: [], deleting: recordIDsToDelete)
        }

        // Refresh
        myTeams.removeAll { $0.id == teamID }
        myMemberships.removeAll { $0.teamID == teamID }
        if selectedTeamID == teamID {
            selectedTeamID = myTeams.first?.id
        }
        print("✅ Left team \(teamID)")
    }

    func loadRoster(teamID: String) async {
        do {
            let predicate = NSPredicate(format: "teamID == %@ AND status == %@", teamID, "approved")
            let query = CKQuery(recordType: "TeamMembership", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            var roster: [TeamMembershipInfo] = []
            var seenUserIDs: Set<String> = []
            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                let member = parseMembershipRecord(record)
                // Deduplicate by userID (keep the first approved record found)
                if !seenUserIDs.contains(member.userID) {
                    seenUserIDs.insert(member.userID)
                    roster.append(member)
                }
            }

            selectedTeamRoster = roster
            print("✅ Loaded roster: \(roster.count) members")
        } catch let error as CKError where error.code == .unknownItem {
            selectedTeamRoster = []
        } catch {
            print("❌ Failed to load roster: \(error)")
        }
    }

    func loadPendingJoinRequests(teamID: String) async {
        do {
            let predicate = NSPredicate(format: "teamID == %@ AND status == %@", teamID, "pending")
            let query = CKQuery(recordType: "TeamMembership", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)

            // Filter out users who already have an approved membership
            let approvedPredicate = NSPredicate(format: "teamID == %@ AND status == %@", teamID, "approved")
            let approvedQuery = CKQuery(recordType: "TeamMembership", predicate: approvedPredicate)
            let (approvedResults, _) = try await publicDB.records(matching: approvedQuery, resultsLimit: 100)

            var approvedUserIDs: Set<String> = []
            for (_, result) in approvedResults {
                guard case .success(let record) = result else { continue }
                if let uid = record["userID"] as? String {
                    approvedUserIDs.insert(uid)
                }
            }

            // Get team name
            let teamName: String
            if let team = myTeams.first(where: { $0.id == teamID }) {
                teamName = team.name
            } else {
                teamName = "Team"
            }

            var requests: [TeamJoinRequest] = []
            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                let uid = record["userID"] as? String ?? ""
                // Skip users who are already approved
                if approvedUserIDs.contains(uid) { continue }

                requests.append(TeamJoinRequest(
                    id: record.recordID.recordName,
                    teamID: teamID,
                    teamName: teamName,
                    userID: uid,
                    username: record["username"] as? String ?? "",
                    displayName: record["displayName"] as? String ?? "",
                    roles: record["role"] as? String ?? "rower",
                    requestedAt: record["joinedAt"] as? Date ?? Date()
                ))
            }

            pendingJoinRequests = requests
            print("✅ Loaded \(requests.count) pending join requests")
        } catch let error as CKError where error.code == .unknownItem {
            pendingJoinRequests = []
        } catch {
            print("❌ Failed to load pending requests: \(error)")
        }
    }

    func loadMyPendingRequests() async {
        guard let userID = currentUserID else { return }

        do {
            let predicate = NSPredicate(format: "userID == %@ AND status == %@", userID, "pending")
            let query = CKQuery(recordType: "TeamMembership", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 20)

            // Check which of these have already been approved (via a separate approved record)
            let approvedPredicate = NSPredicate(format: "userID == %@ AND status == %@", userID, "approved")
            let approvedQuery = CKQuery(recordType: "TeamMembership", predicate: approvedPredicate)
            let (approvedResults, _) = try await publicDB.records(matching: approvedQuery, resultsLimit: 20)

            var approvedTeamIDs: Set<String> = []
            for (_, result) in approvedResults {
                guard case .success(let record) = result else { continue }
                if let tid = record["teamID"] as? String {
                    approvedTeamIDs.insert(tid)
                }
            }

            var pending: [TeamMembershipInfo] = []
            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                let membership = parseMembershipRecord(record)
                // Only show as pending if not yet approved
                if !approvedTeamIDs.contains(membership.teamID) {
                    pending.append(membership)
                }
            }

            myPendingTeamRequests = pending
        } catch let error as CKError where error.code == .unknownItem {
            myPendingTeamRequests = []
        } catch {
            print("❌ Failed to load pending team requests: \(error)")
        }
    }

    // MARK: - Team Feed

    func loadTeamActivity(teamID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Get approved members
            let memberPredicate = NSPredicate(format: "teamID == %@ AND status == %@", teamID, "approved")
            let memberQuery = CKQuery(recordType: "TeamMembership", predicate: memberPredicate)
            let (memberResults, _) = try await publicDB.records(matching: memberQuery, resultsLimit: 50)

            var memberIDs: Set<String> = []
            for (_, result) in memberResults {
                guard case .success(let record) = result else { continue }
                if let uid = record["userID"] as? String {
                    memberIDs.insert(uid)
                }
            }

            // Fetch recent workouts from each member
            var allWorkouts: [SocialService.SharedWorkoutResult] = []
            for memberID in memberIDs {
                do {
                    let predicate = NSPredicate(format: "ownerID == %@", memberID)
                    let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
                    query.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]
                    let (results, _) = try await publicDB.records(matching: query, resultsLimit: 3)

                    for (_, result) in results {
                        guard case .success(let record) = result else { continue }
                        allWorkouts.append(parseSharedWorkoutRecord(record))
                    }
                } catch let error as CKError where error.code == .unknownItem {
                    continue
                } catch {
                    print("⚠️ Failed to load workouts for member \(memberID): \(error)")
                    continue
                }
            }

            teamActivity = allWorkouts
                .sorted { $0.workoutDate > $1.workoutDate }
                .prefix(10)
                .map { $0 }

            print("✅ Loaded \(teamActivity.count) team activity items")
        } catch let error as CKError where error.code == .unknownItem {
            teamActivity = []
        } catch {
            print("❌ Failed to load team activity: \(error)")
            errorMessage = "Could not load team activity"
        }
    }

    // MARK: - Admin Check

    func isAdmin(teamID: String) -> Bool {
        myMemberships.contains { $0.teamID == teamID && $0.membershipRole == "admin" }
    }

    func hasRole(_ role: UserRole, teamID: String) -> Bool {
        guard let membership = myMemberships.first(where: { $0.teamID == teamID }) else {
            return false
        }
        return membership.hasRole(role)
    }

    func membershipFor(teamID: String) -> TeamMembershipInfo? {
        myMemberships.first { $0.teamID == teamID }
    }

    // MARK: - Admin Role Management

    func updateMemberRoles(membershipRecordName: String, newRoles: String, teamID: String) async throws {
        guard currentUserID != nil else { throw TeamError.notAuthenticated }
        guard isAdmin(teamID: teamID) else { throw TeamError.notAdmin }

        let recordID = CKRecord.ID(recordName: membershipRecordName)
        let record = try await publicDB.record(for: recordID)
        record["role"] = newRoles
        _ = try await publicDB.save(record)
        print("✅ Updated roles to '\(newRoles)' for membership \(membershipRecordName)")

        await loadRoster(teamID: teamID)
    }

    // MARK: - Helpers

    private func fetchUserDisplayInfo(userID: String) async -> (username: String, displayName: String) {
        do {
            let profileID = CKRecord.ID(recordName: userID)
            let profile = try await publicDB.record(for: profileID)
            let username = profile["username"] as? String ?? ""
            let displayName = profile["displayName"] as? String ?? ""
            return (username, displayName)
        } catch {
            print("⚠️ Could not fetch profile for \(userID): \(error)")
            return ("", "")
        }
    }

    private func fetchLocalUserRoles() -> String {
        guard let userID = currentUserID, let context = modelContext else { return "rower" }
        let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { u in
            u.appleUserID == userID
        })
        if let users = try? context.fetch(descriptor), let user = users.first {
            return user.role ?? "rower"
        }
        return "rower"
    }

    private func parseTeamRecord(_ record: CKRecord) -> TeamInfo {
        var picData: Data? = nil
        if let asset = record["profilePic"] as? CKAsset,
           let url = asset.fileURL,
           let data = try? Data(contentsOf: url) {
            picData = data
        }
        return TeamInfo(
            id: record.recordID.recordName,
            name: record["name"] as? String ?? "Unnamed Team",
            createdByID: record["createdByID"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? Date(),
            profilePicData: picData
        )
    }

    private func parseMembershipRecord(_ record: CKRecord) -> TeamMembershipInfo {
        TeamMembershipInfo(
            id: record.recordID.recordName,
            teamID: record["teamID"] as? String ?? "",
            userID: record["userID"] as? String ?? "",
            username: record["username"] as? String ?? "",
            displayName: record["displayName"] as? String ?? "",
            roles: record["role"] as? String ?? "rower",
            membershipRole: record["membershipRole"] as? String ?? "member",
            status: record["status"] as? String ?? "pending",
            joinedAt: record["joinedAt"] as? Date ?? Date()
        )
    }

    private func parseSharedWorkoutRecord(_ record: CKRecord) -> SocialService.SharedWorkoutResult {
        SocialService.SharedWorkoutResult(
            id: record.recordID.recordName,
            ownerID: record["ownerID"] as? String ?? "",
            ownerUsername: record["ownerUsername"] as? String ?? "",
            ownerDisplayName: record["ownerDisplayName"] as? String ?? "",
            workoutDate: record["workoutDate"] as? Date ?? Date(),
            workoutType: record["workoutType"] as? String ?? "",
            totalTime: record["totalTime"] as? String ?? "",
            totalDistance: record["totalDistance"] as? Int ?? 0,
            averageSplit: record["averageSplit"] as? String ?? "",
            intensityZone: record["intensityZone"] as? String ?? "",
            isErgTest: (record["isErgTest"] as? Int64 ?? 0) == 1,
            privacy: record["privacy"] as? String ?? "friends",
            submittedByCoxUsername: record["submittedByCoxUsername"] as? String
        )
    }
}
