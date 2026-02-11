import Foundation
import CloudKit
import Combine
import SwiftData

@MainActor
class SocialService: ObservableObject {

    // MARK: - Published State

    @Published var myProfile: CKRecord?
    @Published var usernameStatus: UsernameStatus = .unchecked
    @Published var searchResults: [UserProfileResult] = []
    @Published var pendingRequests: [FriendRequestResult] = []
    @Published var friends: [UserProfileResult] = []
    @Published var friendActivity: [SharedWorkoutResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Types

    enum UsernameStatus: Equatable {
        case unchecked, checking, available, taken, invalid
    }

    struct UserProfileResult: Identifiable {
        let id: String           // appleUserID
        let username: String
        let displayName: String
        let recordID: CKRecord.ID
    }

    struct FriendRequestResult: Identifiable {
        let id: String           // CKRecord.recordName
        let senderID: String
        let senderUsername: String
        let senderDisplayName: String
        let status: String
        let createdAt: Date
        let record: CKRecord
    }

    struct SharedWorkoutResult: Identifiable {
        let id: String
        let ownerUsername: String
        let ownerDisplayName: String
        let workoutDate: Date
        let workoutType: String
        let totalTime: String
        let totalDistance: Int
        let averageSplit: String
        let intensityZone: String
        let isErgTest: Bool
    }

    // Track which users we've already sent requests to (for UI state)
    @Published var sentRequestIDs: Set<String> = []

    // MARK: - Private

    private let container = CKContainer(identifier: "iCloud.com.omomalley03.ErgScan1")
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private(set) var currentUserID: String?
    private var modelContext: ModelContext?

    // MARK: - Profile Management

    func setCurrentUser(_ appleUserID: String, context: ModelContext) {
        currentUserID = appleUserID
        modelContext = context
        Task {
            await checkCloudKitStatus()
            await loadMyProfile()
        }
    }

    private func checkCloudKitStatus() async {
        print("🔵 === CLOUDKIT STATUS CHECK ===")
        do {
            let status = try await container.accountStatus()
            print("   Account status: \(status.rawValue)")
            switch status {
            case .available:
                print("   ✅ CloudKit account available")
                await testCloudKitAccess()
            case .noAccount:
                print("   ❌ No iCloud account signed in")
                errorMessage = "Please sign into iCloud in Settings"
            case .restricted:
                print("   ❌ CloudKit restricted")
                errorMessage = "CloudKit is restricted on this device"
            case .couldNotDetermine:
                print("   ❌ Could not determine CloudKit status")
                errorMessage = "Could not check CloudKit status"
            case .temporarilyUnavailable:
                print("   ⚠️ CloudKit temporarily unavailable")
                errorMessage = "CloudKit temporarily unavailable"
            @unknown default:
                print("   ⚠️ Unknown CloudKit status")
            }
        } catch {
            print("   ❌ Failed to check CloudKit status: \(error)")
        }
    }

    private func testCloudKitAccess() async {
        print("🧪 Testing CloudKit public database access...")
        do {
            // Try a simple query to test access (use a real predicate — CloudKit rejects NSFalsePredicate)
            let predicate = NSPredicate(format: "appleUserID == %@", "___cloudkit_test___")
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            let _ = try await publicDB.records(matching: query, resultsLimit: 1)
            print("   ✅ Public database access successful")
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — that's OK, it auto-creates on first write
            print("   ✅ Public database reachable (UserProfile type will be created on first save)")
        } catch let error as CKError {
            print("   ❌ Public database error: \(error.localizedDescription)")
            print("   Error code: \(error.code.rawValue)")
            print("   Full error: \(error)")
        } catch {
            print("   ❌ Unexpected error: \(error)")
        }
    }

    func loadMyProfile() async {
        guard let userID = currentUserID else { return }
        do {
            let recordID = CKRecord.ID(recordName: userID)
            let record = try await publicDB.record(for: recordID)
            myProfile = record

            // Sync username from CloudKit to local SwiftData User model
            if let cloudUsername = record["username"] as? String,
               let context = modelContext {
                let descriptor = FetchDescriptor<User>(predicate: #Predicate<User> { u in
                    u.appleUserID == userID
                })
                if let users = try? context.fetch(descriptor),
                   let localUser = users.first,
                   localUser.username != cloudUsername {
                    localUser.username = cloudUsername
                    try? context.save()
                    print("✅ Synced username '\(cloudUsername)' from CloudKit to local User model")
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No profile yet — that's fine
            myProfile = nil
        } catch {
            print("⚠️ Failed to load profile: \(error)")
        }
    }

    func saveUsername(_ username: String, displayName: String, context: ModelContext) async throws {
        print("🔵 saveUsername called with: \(username)")

        guard let userID = currentUserID else {
            print("❌ No currentUserID - user not authenticated")
            throw SocialError.notAuthenticated
        }
        print("✅ CurrentUserID: \(userID)")

        let lowercased = username.lowercased()

        // Validate format
        guard isValidUsername(lowercased) else {
            print("❌ Invalid username format: \(lowercased)")
            usernameStatus = .invalid
            throw SocialError.invalidUsername
        }
        print("✅ Username format valid")

        // Check uniqueness
        print("🔍 Checking username availability...")
        let isAvailable = try await isUsernameAvailable(lowercased)
        guard isAvailable else {
            print("❌ Username already taken: \(lowercased)")
            usernameStatus = .taken
            throw SocialError.usernameTaken
        }
        print("✅ Username is available")

        // Create or update profile record
        print("💾 Creating CloudKit record...")
        let recordID = CKRecord.ID(recordName: userID)
        let record: CKRecord
        if let existing = myProfile {
            print("📝 Updating existing profile")
            record = existing
        } else {
            print("✨ Creating new profile")
            record = CKRecord(recordType: "UserProfile", recordID: recordID)
            record["appleUserID"] = userID
            record["createdAt"] = Date() as NSDate
        }

        record["username"] = lowercased
        record["displayName"] = displayName

        print("☁️ Saving to CloudKit public database...")
        let saved = try await publicDB.save(record)
        print("✅ CloudKit save successful")

        myProfile = saved
        usernameStatus = .available

        // Update local User model
        print("💾 Updating local SwiftData User model...")
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.appleUserID == userID })
        if let users = try? context.fetch(descriptor), let user = users.first {
            user.username = lowercased
            try? context.save()
            print("✅ Local user updated successfully")
        } else {
            print("⚠️ Could not find local user to update")
        }

        print("🎉 saveUsername completed successfully!")
    }

    func checkUsernameAvailability(_ username: String) async {
        print("🔍 checkUsernameAvailability called with: '\(username)'")

        let lowercased = username.lowercased()
        print("   Lowercased: '\(lowercased)'")

        guard isValidUsername(lowercased) else {
            print("   ❌ Invalid format (must be 3-20 chars, start with letter, only a-z 0-9 _)")
            usernameStatus = .invalid
            return
        }
        print("   ✅ Format valid")

        // If it's our current username, it's available
        if let current = myProfile?["username"] as? String, current == lowercased {
            print("   ℹ️ This is already your username")
            usernameStatus = .available
            return
        }

        print("   🔄 Checking availability in CloudKit...")
        usernameStatus = .checking
        do {
            let available = try await isUsernameAvailable(lowercased)
            usernameStatus = available ? .available : .taken
            print("   \(available ? "✅ Available" : "❌ Taken")")
        } catch {
            usernameStatus = .unchecked
            print("   ⚠️ Username check failed: \(error)")
            errorMessage = "Could not check username availability. Check iCloud connection."
        }
    }

    private func isUsernameAvailable(_ username: String) async throws -> Bool {
        do {
            let predicate = NSPredicate(format: "username == %@", username)
            let query = CKQuery(recordType: "UserProfile", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            // If any record found that isn't ours, it's taken
            for (recordID, _) in results {
                if recordID.recordName != currentUserID {
                    return false
                }
            }
            return true
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — no users at all, so username is available
            print("   ℹ️ UserProfile record type not found yet — username is available")
            return true
        }
    }

    private func isValidUsername(_ username: String) -> Bool {
        let pattern = "^[a-z][a-z0-9_]{2,19}$"
        return username.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Search

    func searchUsers(query: String) async {
        guard !query.isEmpty, let userID = currentUserID else {
            searchResults = []
            return
        }

        let lowercased = query.lowercased()
        isLoading = true
        defer { isLoading = false }

        do {
            // Search by username prefix
            let usernamePredicate = NSPredicate(format: "username BEGINSWITH %@", lowercased)
            let usernameQuery = CKQuery(recordType: "UserProfile", predicate: usernamePredicate)
            let (usernameResults, _) = try await publicDB.records(matching: usernameQuery, resultsLimit: 20)

            // Search by display name prefix
            let namePredicate = NSPredicate(format: "displayName BEGINSWITH %@", query)
            let nameQuery = CKQuery(recordType: "UserProfile", predicate: namePredicate)
            let (nameResults, _) = try await publicDB.records(matching: nameQuery, resultsLimit: 20)

            // Merge and deduplicate, exclude self
            var seen = Set<String>()
            var results: [UserProfileResult] = []

            for (recordID, result) in usernameResults + nameResults {
                guard case .success(let record) = result else { continue }
                let appleID = record["appleUserID"] as? String ?? recordID.recordName
                guard appleID != userID, !seen.contains(appleID) else { continue }
                seen.insert(appleID)
                results.append(UserProfileResult(
                    id: appleID,
                    username: record["username"] as? String ?? "",
                    displayName: record["displayName"] as? String ?? "",
                    recordID: recordID
                ))
            }

            searchResults = results
        } catch {
            print("⚠️ Search failed: \(error)")
            errorMessage = "Search failed. Please try again."
        }
    }

    // MARK: - Friend Requests

    func sendFriendRequest(to receiverID: String) async {
        guard let userID = currentUserID else { return }

        do {
            // Check for existing request (skip if record type doesn't exist yet)
            var alreadyExists = false
            do {
                let outgoingPredicate = NSPredicate(format: "senderID == %@ AND receiverID == %@", userID, receiverID)
                let outgoingQuery = CKQuery(recordType: "FriendRequest", predicate: outgoingPredicate)
                let (outgoing, _) = try await publicDB.records(matching: outgoingQuery, resultsLimit: 1)

                let incomingPredicate = NSPredicate(format: "senderID == %@ AND receiverID == %@", receiverID, userID)
                let incomingQuery = CKQuery(recordType: "FriendRequest", predicate: incomingPredicate)
                let (incoming, _) = try await publicDB.records(matching: incomingQuery, resultsLimit: 1)

                alreadyExists = !outgoing.isEmpty || !incoming.isEmpty
            } catch let error as CKError where error.code == .unknownItem {
                // Record type doesn't exist yet — no requests exist, proceed to create first one
                print("ℹ️ FriendRequest type doesn't exist yet — will be created on first save")
            }

            guard !alreadyExists else {
                sentRequestIDs.insert(receiverID)
                return
            }

            let myUsername = myProfile?["username"] as? String ?? ""
            let myDisplayName = myProfile?["displayName"] as? String ?? ""

            let record = CKRecord(recordType: "FriendRequest")
            record["senderID"] = userID
            record["receiverID"] = receiverID
            record["senderUsername"] = myUsername
            record["senderDisplayName"] = myDisplayName
            record["status"] = "pending"
            record["createdAt"] = Date() as NSDate

            _ = try await publicDB.save(record)
            sentRequestIDs.insert(receiverID)
            HapticService.shared.lightImpact()
        } catch let error as CKError {
            let errorMsg: String
            if error.code == .unknownItem {
                errorMsg = "FriendRequest type not deployed to Production. Test from Xcode first."
            } else {
                errorMsg = "Could not send friend request: \(error.localizedDescription)"
            }
            await MainActor.run {
                self.errorMessage = errorMsg
            }
            print("⚠️ Failed to send friend request: \(error)")
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not send friend request."
            }
            print("⚠️ Failed to send friend request: \(error)")
        }
    }

    func loadPendingRequests() async {
        guard let userID = currentUserID else { return }

        do {
            // Get pending requests sent to me
            let predicate = NSPredicate(format: "receiverID == %@ AND status == %@", userID, "pending")
            let query = CKQuery(recordType: "FriendRequest", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)

            // Get my response records (to filter out already-handled requests)
            let responsePredicate = NSPredicate(format: "senderID == %@", userID)
            let responseQuery = CKQuery(recordType: "FriendRequest", predicate: responsePredicate)
            let (responseResults, _) = try await publicDB.records(matching: responseQuery, resultsLimit: 100)

            let respondedToIDs = Set(responseResults.compactMap { _, result -> String? in
                guard case .success(let record) = result,
                      let status = record["status"] as? String,
                      status == "accepted" || status == "rejected" else { return nil }
                return record["receiverID"] as? String
            })

            pendingRequests = results.compactMap { recordID, result in
                guard case .success(let record) = result else { return nil }
                let senderID = record["senderID"] as? String ?? ""
                // Skip if we've already responded to this sender
                guard !respondedToIDs.contains(senderID) else { return nil }
                return FriendRequestResult(
                    id: recordID.recordName,
                    senderID: senderID,
                    senderUsername: record["senderUsername"] as? String ?? "",
                    senderDisplayName: record["senderDisplayName"] as? String ?? "",
                    status: record["status"] as? String ?? "",
                    createdAt: record["createdAt"] as? Date ?? Date(),
                    record: record
                )
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — no requests
            pendingRequests = []
        } catch {
            print("⚠️ Failed to load pending requests: \(error)")
        }
    }

    func acceptRequest(_ request: FriendRequestResult) async {
        guard let userID = currentUserID else { return }

        do {
            // Create a NEW acceptance record owned by the receiver (us)
            // CloudKit only lets the creator modify their records, so we can't edit the sender's record
            let record = CKRecord(recordType: "FriendRequest")
            record["senderID"] = userID
            record["receiverID"] = request.senderID
            record["senderUsername"] = myProfile?["username"] as? String ?? ""
            record["senderDisplayName"] = myProfile?["displayName"] as? String ?? ""
            record["status"] = "accepted"
            record["createdAt"] = Date() as NSDate

            _ = try await publicDB.save(record)

            // Remove from pending, refresh friends
            pendingRequests.removeAll { $0.id == request.id }
            await loadFriends()
            await loadFriendActivity()
            HapticService.shared.lightImpact()
        } catch {
            print("⚠️ Failed to accept request: \(error)")
            errorMessage = "Could not accept request."
        }
    }

    func rejectRequest(_ request: FriendRequestResult) async {
        guard let userID = currentUserID else { return }

        do {
            // Create a rejection record owned by us
            let record = CKRecord(recordType: "FriendRequest")
            record["senderID"] = userID
            record["receiverID"] = request.senderID
            record["status"] = "rejected"
            record["createdAt"] = Date() as NSDate

            _ = try await publicDB.save(record)
            pendingRequests.removeAll { $0.id == request.id }
            HapticService.shared.lightImpact()
        } catch {
            print("⚠️ Failed to reject request: \(error)")
            errorMessage = "Could not reject request."
        }
    }

    // MARK: - Friends List

    func loadFriends() async {
        guard let userID = currentUserID else { return }

        do {
            // Query accepted requests where we're sender or receiver
            let senderPredicate = NSPredicate(format: "senderID == %@ AND status == %@", userID, "accepted")
            let senderQuery = CKQuery(recordType: "FriendRequest", predicate: senderPredicate)
            let (senderResults, _) = try await publicDB.records(matching: senderQuery, resultsLimit: 100)

            let receiverPredicate = NSPredicate(format: "receiverID == %@ AND status == %@", userID, "accepted")
            let receiverQuery = CKQuery(recordType: "FriendRequest", predicate: receiverPredicate)
            let (receiverResults, _) = try await publicDB.records(matching: receiverQuery, resultsLimit: 100)

            // Extract friend IDs
            var friendIDs: Set<String> = []
            for (_, result) in senderResults {
                guard case .success(let record) = result else { continue }
                if let receiverID = record["receiverID"] as? String { friendIDs.insert(receiverID) }
            }
            for (_, result) in receiverResults {
                guard case .success(let record) = result else { continue }
                if let senderID = record["senderID"] as? String { friendIDs.insert(senderID) }
            }

            // Batch-fetch friend profiles
            guard !friendIDs.isEmpty else {
                friends = []
                return
            }

            let profileIDs = friendIDs.map { CKRecord.ID(recordName: $0) }
            var profiles: [UserProfileResult] = []

            for profileID in profileIDs {
                do {
                    let record = try await publicDB.record(for: profileID)
                    profiles.append(UserProfileResult(
                        id: record["appleUserID"] as? String ?? profileID.recordName,
                        username: record["username"] as? String ?? "",
                        displayName: record["displayName"] as? String ?? "",
                        recordID: profileID
                    ))
                } catch {
                    // Skip profiles that can't be fetched
                    continue
                }
            }

            friends = profiles
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — no friends
            friends = []
        } catch {
            print("⚠️ Failed to load friends: \(error)")
        }
    }

    // MARK: - Shared Workouts

    func publishWorkout(
        workoutType: String,
        date: Date,
        totalTime: String,
        totalDistance: Int,
        averageSplit: String,
        intensityZone: String,
        isErgTest: Bool,
        localWorkoutID: String
    ) async {
        guard let userID = currentUserID else { return }
        guard myProfile != nil else { return } // Must have a profile to share

        let username = myProfile?["username"] as? String ?? ""
        let displayName = myProfile?["displayName"] as? String ?? ""

        do {
            // Check for existing shared workout with same localWorkoutID (dedup)
            // Skip if record type doesn't exist yet
            var existingRecord: CKRecord? = nil
            do {
                let dedupPredicate = NSPredicate(format: "ownerID == %@ AND localWorkoutID == %@", userID, localWorkoutID)
                let dedupQuery = CKQuery(recordType: "SharedWorkout", predicate: dedupPredicate)
                let (existing, _) = try await publicDB.records(matching: dedupQuery, resultsLimit: 1)
                if let (_, result) = existing.first, case .success(let record) = result {
                    existingRecord = record
                }
            } catch let error as CKError where error.code == .unknownItem {
                print("ℹ️ SharedWorkout type doesn't exist yet — will be created on first save")
            }

            let record = existingRecord ?? CKRecord(recordType: "SharedWorkout")

            record["ownerID"] = userID
            record["ownerUsername"] = username
            record["ownerDisplayName"] = displayName
            record["workoutDate"] = date as NSDate
            record["workoutType"] = workoutType
            record["totalTime"] = totalTime
            record["totalDistance"] = totalDistance as NSNumber
            record["averageSplit"] = averageSplit
            record["intensityZone"] = intensityZone
            record["isErgTest"] = (isErgTest ? 1 : 0) as NSNumber
            record["localWorkoutID"] = localWorkoutID
            record["createdAt"] = Date() as NSDate

            _ = try await publicDB.save(record)
        } catch {
            print("⚠️ Failed to publish workout: \(error)")
        }
    }

    func loadFriendActivity() async {
        // Ensure friends are loaded
        if friends.isEmpty {
            await loadFriends()
        }

        guard !friends.isEmpty else {
            friendActivity = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var allWorkouts: [SharedWorkoutResult] = []

            // Query last 3 workouts per friend
            for friend in friends {
                let predicate = NSPredicate(format: "ownerID == %@", friend.id)
                let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]
                let (results, _) = try await publicDB.records(matching: query, resultsLimit: 3)

                for (recordID, result) in results {
                    guard case .success(let record) = result else { continue }
                    allWorkouts.append(SharedWorkoutResult(
                        id: recordID.recordName,
                        ownerUsername: record["ownerUsername"] as? String ?? friend.username,
                        ownerDisplayName: record["ownerDisplayName"] as? String ?? friend.displayName,
                        workoutDate: record["workoutDate"] as? Date ?? Date(),
                        workoutType: record["workoutType"] as? String ?? "",
                        totalTime: record["totalTime"] as? String ?? "",
                        totalDistance: (record["totalDistance"] as? NSNumber)?.intValue ?? 0,
                        averageSplit: record["averageSplit"] as? String ?? "",
                        intensityZone: record["intensityZone"] as? String ?? "",
                        isErgTest: (record["isErgTest"] as? NSNumber)?.intValue == 1
                    ))
                }
            }

            // Sort all by date descending
            friendActivity = allWorkouts.sorted { $0.workoutDate > $1.workoutDate }
        } catch let error as CKError where error.code == .unknownItem {
            // SharedWorkout type doesn't exist yet — no activity
            friendActivity = []
        } catch {
            print("⚠️ Failed to load friend activity: \(error)")
            errorMessage = "Could not load activity feed."
        }
    }

    // MARK: - Errors

    enum SocialError: LocalizedError {
        case notAuthenticated
        case invalidUsername
        case usernameTaken

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not signed in"
            case .invalidUsername: return "Invalid username format"
            case .usernameTaken: return "Username is already taken"
            }
        }
    }
}
