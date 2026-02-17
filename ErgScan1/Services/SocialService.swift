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

    struct SharedWorkoutResult: Identifiable, Hashable {
        let id: String
        let ownerID: String
        let ownerUsername: String
        let ownerDisplayName: String
        let workoutDate: Date
        let workoutType: String
        let totalTime: String
        let totalDistance: Int
        let averageSplit: String
        let intensityZone: String
        let isErgTest: Bool
        let privacy: String  // "private", "friends", "team(:ids)", or "friends+team(:ids)"
        let submittedByCoxUsername: String?  // coxswain username if scanned on behalf
    }

    struct WorkoutDetailResult {
        let ergImageData: Data?
        let intervals: [[String: Any]]
        let ocrConfidence: Double
        let wasManuallyEdited: Bool
    }

    // Track which users we've already sent requests to (for UI state)
    @Published var sentRequestIDs: Set<String> = []

    // MARK: - Private

    private let container = CKContainer(identifier: "iCloud.com.omomalley03.ErgScan1")
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private(set) var currentUserID: String?
    private var modelContext: ModelContext?

    // MARK: - Cache

    var cacheService: SocialCacheService?
    private var friendActivityPaginator: PaginatedCloudKitFetcher?

    // MARK: - Profile Management

    func setCurrentUser(_ appleUserID: String, context: ModelContext) {
        currentUserID = appleUserID
        modelContext = context

        // Load cached data immediately (instant UI)
        if let cache = cacheService {
            let cachedFriends = cache.getCachedFriends()
            if !cachedFriends.isEmpty { friends = cachedFriends }
            let cachedActivity = cache.getCachedFriendActivity()
            if !cachedActivity.isEmpty { friendActivity = cachedActivity }
        }

        // Profile + status check in parallel (needed for UI)
        Task {
            async let statusCheck: Void = checkCloudKitStatus()
            async let profileLoad: Void = loadMyProfile()
            _ = await (statusCheck, profileLoad)
        }

        // Background sync social data
        Task {
            await loadFriends()
            await loadFriendActivity()
        }

        // Defer heavy workout sync — not needed immediately at startup
        Task(priority: .background) {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s delay
            await publishExistingWorkouts()
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

        // Publish all existing workouts now that we have a username
        await publishExistingWorkouts()
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

        // Prevent friending yourself
        guard receiverID != userID else {
            print("⚠️ Cannot send friend request to yourself")
            return
        }

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
            await loadFriends(forceRefresh: true)
            await loadFriendActivity(forceRefresh: true)
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

    func unfriend(_ friendID: String) async {
        guard let userID = currentUserID else { return }

        do {
            // Find all accepted friend requests between current user and friend
            let predicate1 = NSPredicate(format: "senderID == %@ AND receiverID == %@ AND status == %@", userID, friendID, "accepted")
            let query1 = CKQuery(recordType: "FriendRequest", predicate: predicate1)
            let (results1, _) = try await publicDB.records(matching: query1, resultsLimit: 100)

            let predicate2 = NSPredicate(format: "senderID == %@ AND receiverID == %@ AND status == %@", friendID, userID, "accepted")
            let query2 = CKQuery(recordType: "FriendRequest", predicate: predicate2)
            let (results2, _) = try await publicDB.records(matching: query2, resultsLimit: 100)

            // Delete all friendship records
            var recordsToDelete: [CKRecord.ID] = []
            for (recordID, result) in results1 {
                guard case .success(_) = result else { continue }
                recordsToDelete.append(recordID)
            }
            for (recordID, result) in results2 {
                guard case .success(_) = result else { continue }
                recordsToDelete.append(recordID)
            }

            if !recordsToDelete.isEmpty {
                _ = try await publicDB.modifyRecords(saving: [], deleting: recordsToDelete)
                print("✅ Unfriended user: \(friendID)")
            }

            // Refresh friends list and activity
            await loadFriends(forceRefresh: true)
            await loadFriendActivity(forceRefresh: true)
            HapticService.shared.lightImpact()
        } catch {
            print("⚠️ Failed to unfriend: \(error)")
            errorMessage = "Could not remove friend."
        }
    }

    // MARK: - Friends List

    func loadFriends(forceRefresh: Bool = false) async {
        guard let userID = currentUserID else { return }

        // Show cache first if available and fresh
        if !forceRefresh, let cache = cacheService {
            let cached = cache.getCachedFriends()
            if !cached.isEmpty {
                friends = cached
            }
            if !cache.isCacheStale(category: "friends", threshold: SocialCacheService.friendsStaleness) {
                return
            }
        }

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
                cacheService?.saveFriends([])
                cacheService?.updateSyncTimestamp(category: "friends")
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

            // Save to cache with pruning
            cacheService?.saveFriends(profiles)
            cacheService?.updateSyncTimestamp(category: "friends")
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — no friends
            friends = []
        } catch {
            print("⚠️ Failed to load friends: \(error)")
            // Keep showing cached data on network failure
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
        localWorkoutID: String,
        privacy: String = "friends",
        onBehalfOfUserID: String? = nil,
        onBehalfOfUsername: String? = nil,
        onBehalfOfDisplayName: String? = nil
    ) async -> String? {
        guard let userID = currentUserID else { return nil }
        guard myProfile != nil else { return nil } // Must have a profile to share

        let coxUsername = myProfile?["username"] as? String ?? ""
        let myDisplayName = myProfile?["displayName"] as? String ?? ""

        // Use rower's info if scanning on behalf, otherwise use current user
        let effectiveOwnerID = onBehalfOfUserID ?? userID
        let effectiveOwnerUsername = onBehalfOfUsername ?? coxUsername
        let effectiveOwnerDisplayName = onBehalfOfDisplayName ?? myDisplayName

        do {
            // Check for existing shared workout with same localWorkoutID (dedup)
            // Skip if record type doesn't exist yet
            var existingRecord: CKRecord? = nil
            do {
                let dedupPredicate = NSPredicate(format: "ownerID == %@ AND localWorkoutID == %@", effectiveOwnerID, localWorkoutID)
                let dedupQuery = CKQuery(recordType: "SharedWorkout", predicate: dedupPredicate)
                let (existing, _) = try await publicDB.records(matching: dedupQuery, resultsLimit: 1)
                if let (_, result) = existing.first, case .success(let record) = result {
                    existingRecord = record
                }
            } catch let error as CKError where error.code == .unknownItem {
                print("ℹ️ SharedWorkout type doesn't exist yet — will be created on first save")
            }

            let record = existingRecord ?? CKRecord(recordType: "SharedWorkout")

            record["ownerID"] = effectiveOwnerID
            record["ownerUsername"] = effectiveOwnerUsername
            record["ownerDisplayName"] = effectiveOwnerDisplayName

            // Tag with coxswain info if scanning on behalf
            if onBehalfOfUserID != nil {
                record["submittedByCoxUsername"] = coxUsername
            }
            record["workoutDate"] = date as NSDate
            record["workoutType"] = workoutType
            record["totalTime"] = totalTime
            record["totalDistance"] = totalDistance as NSNumber
            record["averageSplit"] = averageSplit
            record["intensityZone"] = intensityZone
            record["isErgTest"] = (isErgTest ? 1 : 0) as NSNumber
            record["localWorkoutID"] = localWorkoutID
            record["privacy"] = privacy
            record["createdAt"] = Date() as NSDate

            let savedRecord = try await publicDB.save(record)

            // Upload full workout detail (image + intervals) if available
            if let context = modelContext, let workoutUUID = UUID(uuidString: localWorkoutID) {
                let descriptor = FetchDescriptor<Workout>(
                    predicate: #Predicate { $0.id == workoutUUID }
                )
                if let workout = try? context.fetch(descriptor).first {
                    do {
                        try await publishWorkoutDetail(workout: workout, sharedWorkoutRecordID: savedRecord.recordID.recordName)
                    } catch {
                        print("⚠️ Failed to publish workout detail (non-fatal): \(error)")
                        // Don't fail the overall publish if detail upload fails
                    }
                }
            }

            // Return the shared workout record ID
            return savedRecord.recordID.recordName
        } catch {
            print("⚠️ Failed to publish workout: \(error)")
            return nil
        }
    }

    @discardableResult
    func deleteSharedWorkout(localWorkoutID: String, sharedWorkoutRecordID: String? = nil) async -> String? {
        guard let userID = currentUserID else {
            print("⚠️ deleteSharedWorkout: no currentUserID")
            return nil
        }
        var deletedRecordNames: Set<String> = []

        func deleteAndCleanup(recordID: CKRecord.ID) async -> Bool {
            do {
                try await publicDB.deleteRecord(withID: recordID)
                let recordName = recordID.recordName
                deletedRecordNames.insert(recordName)
                print("✅ Deleted SharedWorkout record: \(recordName)")

                // Remove from in-memory activity
                friendActivity.removeAll { $0.id == recordName }

                // Remove from persisted feed caches (friend + all team sources)
                cacheService?.removeCachedSharedWorkout(recordID: recordName)

                // Delete orphaned chups/comments
                await deleteAssociatedRecords(type: "WorkoutChup", workoutID: recordName)
                await deleteAssociatedRecords(type: "WorkoutComment", workoutID: recordName)
                return true
            } catch let error as CKError where error.code == .unknownItem {
                return false
            } catch {
                print("⚠️ Failed deleting SharedWorkout record \(recordID.recordName): \(error)")
                return false
            }
        }

        do {
            // 1) Fast path: if we know the record ID, delete directly.
            if let sharedWorkoutRecordID = sharedWorkoutRecordID {
                let ckID = CKRecord.ID(recordName: sharedWorkoutRecordID)
                _ = await deleteAndCleanup(recordID: ckID)
            }

            // 2) Fallback: find by owner + localWorkoutID.
            let ownedPredicate = NSPredicate(format: "ownerID == %@ AND localWorkoutID == %@", userID, localWorkoutID)
            let ownedQuery = CKQuery(recordType: "SharedWorkout", predicate: ownedPredicate)
            let (ownedResults, _) = try await publicDB.records(matching: ownedQuery, resultsLimit: 10)
            for (recordID, result) in ownedResults {
                guard case .success(_) = result else { continue }
                _ = await deleteAndCleanup(recordID: recordID)
            }

            // 3) Final fallback: query by localWorkoutID only (covers legacy/mismatched owner records).
            if deletedRecordNames.isEmpty {
                let localPredicate = NSPredicate(format: "localWorkoutID == %@", localWorkoutID)
                let localQuery = CKQuery(recordType: "SharedWorkout", predicate: localPredicate)
                let (localResults, _) = try await publicDB.records(matching: localQuery, resultsLimit: 10)
                for (recordID, result) in localResults {
                    guard case .success(let record) = result else { continue }
                    // Safety: only delete records owned by current user if owner is present.
                    let ownerID = record["ownerID"] as? String
                    if ownerID == nil || ownerID == userID {
                        _ = await deleteAndCleanup(recordID: recordID)
                    }
                }
            }

            if deletedRecordNames.isEmpty {
                print("ℹ️ deleteSharedWorkout: no SharedWorkout found for localWorkoutID=\(localWorkoutID)")
            }

            return deletedRecordNames.first
        } catch let error as CKError where error.code == .unknownItem {
            // SharedWorkout type doesn't exist yet — nothing to delete
            return deletedRecordNames.first
        } catch {
            print("⚠️ Failed to delete SharedWorkout (localWorkoutID=\(localWorkoutID)): \(error)")
            return deletedRecordNames.first
        }
    }

    /// Delete all CloudKit records of a given type that reference a workoutID
    private func deleteAssociatedRecords(type: String, workoutID: String) async {
        do {
            let predicate = NSPredicate(format: "workoutID == %@", workoutID)
            let query = CKQuery(recordType: type, predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)
            for (recordID, _) in results {
                try? await publicDB.deleteRecord(withID: recordID)
            }
            if !results.isEmpty {
                print("✅ Deleted \(results.count) \(type) records for workout \(workoutID)")
            }
        } catch {
            print("⚠️ Failed to delete \(type) records for workout \(workoutID): \(error)")
        }
    }

    // MARK: - Workout Detail (Full Data Sync)

    /// Encode intervals array to JSON data for CloudKit storage
    private func encodeIntervals(_ intervals: [Interval]) throws -> Data {
        let intervalsArray = intervals.map { interval -> [String: Any] in
            var dict: [String: Any] = [
                "orderIndex": interval.orderIndex,
                "time": interval.time,
                "meters": interval.meters,
                "splitPer500m": interval.splitPer500m,
                "strokeRate": interval.strokeRate,
                "timeConfidence": interval.timeConfidence,
                "metersConfidence": interval.metersConfidence,
                "splitConfidence": interval.splitConfidence,
                "rateConfidence": interval.rateConfidence,
                "heartRateConfidence": interval.heartRateConfidence
            ]
            if let heartRate = interval.heartRate {
                dict["heartRate"] = heartRate
            }
            return dict
        }
        return try JSONSerialization.data(withJSONObject: intervalsArray, options: [])
    }

    /// Upload full workout detail (erg image + intervals) to CloudKit
    func publishWorkoutDetail(workout: Workout, sharedWorkoutRecordID: String) async throws {
        guard let userID = currentUserID else { return }

        do {
            // Check for existing WorkoutDetail by localWorkoutID (dedup)
            var existingRecord: CKRecord? = nil
            do {
                let dedupPredicate = NSPredicate(format: "ownerID == %@ AND localWorkoutID == %@", userID, workout.id.uuidString)
                let dedupQuery = CKQuery(recordType: "WorkoutDetail", predicate: dedupPredicate)
                let (existing, _) = try await publicDB.records(matching: dedupQuery, resultsLimit: 1)
                if let (_, result) = existing.first, case .success(let record) = result {
                    existingRecord = record
                }
            } catch let error as CKError where error.code == .unknownItem {
                print("ℹ️ WorkoutDetail type doesn't exist yet — will be created on first save")
            }

            let record = existingRecord ?? CKRecord(recordType: "WorkoutDetail")

            record["localWorkoutID"] = workout.id.uuidString
            record["ownerID"] = userID

            // Set reference to SharedWorkout (for cascade delete and linking)
            let sharedWorkoutID = CKRecord.ID(recordName: sharedWorkoutRecordID)
            record["sharedWorkoutID"] = CKRecord.Reference(recordID: sharedWorkoutID, action: .deleteSelf)

            // Upload erg image as CKAsset
            if let imageData = workout.imageData {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try imageData.write(to: tempURL)
                let asset = CKAsset(fileURL: tempURL)
                record["ergImage"] = asset
                // Note: Temp file will be cleaned up automatically after upload
            }

            // Encode intervals as JSON string
            if let intervals = workout.intervals, !intervals.isEmpty {
                let intervalsData = try encodeIntervals(intervals)
                let intervalsJSON = String(data: intervalsData, encoding: .utf8) ?? "[]"
                record["intervalsJSON"] = intervalsJSON
            } else {
                record["intervalsJSON"] = "[]"
            }

            // Set confidence and edit flag
            record["ocrConfidence"] = workout.ocrConfidence as NSNumber
            record["wasManuallyEdited"] = (workout.wasManuallyEdited ? 1 : 0) as NSNumber
            record["createdAt"] = Date() as NSDate

            _ = try await publicDB.save(record)
            print("✅ Published WorkoutDetail for workout \(workout.id.uuidString)")
        } catch {
            print("⚠️ Failed to publish workout detail: \(error)")
            throw error
        }
    }

    /// Fetch full workout detail from CloudKit for a friend's workout
    func fetchWorkoutDetail(sharedWorkoutID: String) async -> WorkoutDetailResult? {
        do {
            // Query WorkoutDetail by reference to SharedWorkout
            let sharedWorkoutRecordID = CKRecord.ID(recordName: sharedWorkoutID)
            let reference = CKRecord.Reference(recordID: sharedWorkoutRecordID, action: .none)
            let predicate = NSPredicate(format: "sharedWorkoutID == %@", reference)
            let query = CKQuery(recordType: "WorkoutDetail", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

            guard let (_, result) = results.first, case .success(let record) = result else {
                print("ℹ️ No WorkoutDetail found for SharedWorkout \(sharedWorkoutID)")
                return nil
            }

            // Download erg image from CKAsset
            var ergImageData: Data? = nil
            if let asset = record["ergImage"] as? CKAsset, let fileURL = asset.fileURL {
                ergImageData = try? Data(contentsOf: fileURL)
            }

            // Decode intervals JSON
            var intervals: [[String: Any]] = []
            if let intervalsJSON = record["intervalsJSON"] as? String,
               let jsonData = intervalsJSON.data(using: .utf8) {
                if let decoded = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                    intervals = decoded
                }
            }

            let ocrConfidence = record["ocrConfidence"] as? Double ?? 0.0
            let wasManuallyEdited = (record["wasManuallyEdited"] as? Int ?? 0) == 1

            return WorkoutDetailResult(
                ergImageData: ergImageData,
                intervals: intervals,
                ocrConfidence: ocrConfidence,
                wasManuallyEdited: wasManuallyEdited
            )
        } catch let error as CKError where error.code == .unknownItem {
            print("ℹ️ WorkoutDetail type doesn't exist yet")
            return nil
        } catch {
            print("⚠️ Failed to fetch workout detail: \(error)")
            return nil
        }
    }

    /// Resolves the CloudKit SharedWorkout record ID for a local workout UUID.
    /// Used to bridge local Workout → CloudKit record ID for chup/comment operations.
    func resolveSharedWorkoutRecordID(localWorkoutID: String) async -> String? {
        guard let userID = currentUserID else { return nil }
        do {
            let predicate = NSPredicate(format: "ownerID == %@ AND localWorkoutID == %@", userID, localWorkoutID)
            let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            if let (recordID, result) = results.first, case .success(_) = result {
                return recordID.recordName
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Publishes all existing local workouts that haven't been shared yet.
    /// Called on startup and after username setup to ensure friends can see all workouts.
    /// Only publishes workouts without a sharedWorkoutRecordID (not yet published).
    func publishExistingWorkouts() async {
        guard let userID = currentUserID,
              let context = modelContext,
              myProfile != nil else { return }

        let username = myProfile?["username"] as? String ?? ""
        guard !username.isEmpty else { return }

        let targetUserID = userID
        do {
            // Only fetch workouts that haven't been published yet (no sharedWorkoutRecordID)
            let descriptor = FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.userID == targetUserID && workout.sharedWorkoutRecordID == nil
                }
            )
            let unpublishedWorkouts = try context.fetch(descriptor)
            guard !unpublishedWorkouts.isEmpty else { return }

            print("📤 Publishing \(unpublishedWorkouts.count) new workouts...")

            for workout in unpublishedWorkouts {
                let privacy = workout.sharePrivacy ?? WorkoutPrivacy.friends.rawValue
                if privacy == WorkoutPrivacy.privateOnly.rawValue {
                    continue
                }
                if let recordID = await publishWorkout(
                    workoutType: workout.workoutType,
                    date: workout.date,
                    totalTime: workout.workTime,
                    totalDistance: workout.totalDistance ?? 0,
                    averageSplit: workout.averageSplit ?? "",
                    intensityZone: workout.intensityZone ?? "",
                    isErgTest: workout.isErgTest,
                    localWorkoutID: workout.id.uuidString,
                    privacy: privacy
                ) {
                    // Mark workout as published
                    workout.sharedWorkoutRecordID = recordID
                }
            }

            try? context.save()
            print("✅ Finished publishing \(unpublishedWorkouts.count) workouts")
        } catch {
            print("⚠️ Failed to publish existing workouts: \(error)")
        }
    }

    func loadFriendActivity(forceRefresh: Bool = false) async {
        // Ensure friends are loaded
        if friends.isEmpty {
            await loadFriends()
        }

        // Show cache first if available and fresh
        if !forceRefresh, let cache = cacheService {
            let cached = cache.getCachedFriendActivity()
            if !cached.isEmpty {
                friendActivity = cached
            }
            if !cache.isCacheStale(category: "friendActivity", threshold: SocialCacheService.feedStaleness) {
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            guard let userID = currentUserID else { return }

            // Build a single array of all IDs to query (self + all friends)
            var allIDs = friends.map { $0.id }
            allIDs.append(userID)

            // Build a lookup map for fallback display info
            var displayInfoMap: [String: (username: String, displayName: String)] = [:]
            displayInfoMap[userID] = (
                username: myProfile?["username"] as? String ?? "",
                displayName: myProfile?["displayName"] as? String ?? ""
            )
            for friend in friends {
                displayInfoMap[friend.id] = (username: friend.username, displayName: friend.displayName)
            }

            // Single batched CloudKit query using IN predicate (replaces N+1 loop)
            let predicate = NSPredicate(format: "ownerID IN %@", allIDs)
            let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]

            // Use paginator for cursor-based pagination
            let paginator = PaginatedCloudKitFetcher(database: publicDB, pageSize: 20)
            let page = try await paginator.fetchFirstPage(query: query)
            friendActivityPaginator = paginator

            var allWorkouts: [SharedWorkoutResult] = []
            for record in page.records {
                let privacyString = record["privacy"] as? String ?? WorkoutPrivacy.friends.rawValue
                guard WorkoutPrivacy.includesFriends(privacyString) else { continue }
                let ownerID = record["ownerID"] as? String ?? ""
                let info = displayInfoMap[ownerID] ?? (username: "", displayName: "")
                allWorkouts.append(sharedWorkoutResult(
                    from: record,
                    recordID: record.recordID,
                    fallbackID: ownerID,
                    fallbackUsername: info.username,
                    fallbackDisplayName: info.displayName
                ))
            }

            friendActivity = allWorkouts

            // Save to cache with zombie pruning
            cacheService?.saveFriendActivity(friendActivity, prune: true)
            cacheService?.updateSyncTimestamp(category: "friendActivity")
        } catch let error as CKError where error.code == .unknownItem {
            // SharedWorkout type doesn't exist yet — no activity
            friendActivity = []
        } catch {
            print("⚠️ Failed to load friend activity: \(error)")
            // Keep showing cached data on network failure
            if friendActivity.isEmpty {
                errorMessage = "Could not load activity feed."
            }
        }
    }

    func loadMoreFriendActivity() async -> [SharedWorkoutResult] {
        guard let paginator = friendActivityPaginator else { return [] }
        guard let userID = currentUserID else { return [] }

        // Build display info map
        var displayInfoMap: [String: (username: String, displayName: String)] = [:]
        displayInfoMap[userID] = (
            username: myProfile?["username"] as? String ?? "",
            displayName: myProfile?["displayName"] as? String ?? ""
        )
        for friend in friends {
            displayInfoMap[friend.id] = (username: friend.username, displayName: friend.displayName)
        }

        do {
            guard let page = try await paginator.fetchNextPage() else { return [] }

            var newWorkouts: [SharedWorkoutResult] = []
            for record in page.records {
                let privacyString = record["privacy"] as? String ?? WorkoutPrivacy.friends.rawValue
                guard WorkoutPrivacy.includesFriends(privacyString) else { continue }
                let ownerID = record["ownerID"] as? String ?? ""
                let info = displayInfoMap[ownerID] ?? (username: "", displayName: "")
                newWorkouts.append(sharedWorkoutResult(
                    from: record,
                    recordID: record.recordID,
                    fallbackID: ownerID,
                    fallbackUsername: info.username,
                    fallbackDisplayName: info.displayName
                ))
            }

            friendActivity.append(contentsOf: newWorkouts)

            // Append to cache without pruning (pagination appends, doesn't replace)
            cacheService?.saveFriendActivity(friendActivity, prune: false)

            return newWorkouts
        } catch {
            print("⚠️ Failed to load more friend activity: \(error)")
            return []
        }
    }

    private func sharedWorkoutResult(from record: CKRecord, recordID: CKRecord.ID, fallbackID: String, fallbackUsername: String, fallbackDisplayName: String) -> SharedWorkoutResult {
        SharedWorkoutResult(
            id: recordID.recordName,
            ownerID: record["ownerID"] as? String ?? fallbackID,
            ownerUsername: record["ownerUsername"] as? String ?? fallbackUsername,
            ownerDisplayName: record["ownerDisplayName"] as? String ?? fallbackDisplayName,
            workoutDate: record["workoutDate"] as? Date ?? Date(),
            workoutType: record["workoutType"] as? String ?? "",
            totalTime: record["totalTime"] as? String ?? "",
            totalDistance: (record["totalDistance"] as? NSNumber)?.intValue ?? 0,
            averageSplit: record["averageSplit"] as? String ?? "",
            intensityZone: record["intensityZone"] as? String ?? "",
            isErgTest: (record["isErgTest"] as? NSNumber)?.intValue == 1,
            privacy: record["privacy"] as? String ?? "friends",
            submittedByCoxUsername: record["submittedByCoxUsername"] as? String
        )
    }

    // MARK: - Chups

    func toggleChup(workoutID: String, userID: String, username: String, isBigChup: Bool = false) async throws -> ChupType {
        // Check if user already chupped
        do {
            let predicate = NSPredicate(format: "workoutID == %@ AND userID == %@", workoutID, userID)
            let query = CKQuery(recordType: "WorkoutChup", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

            if let (recordID, result) = results.first, case .success(let existingRecord) = result {
                // Already chupped — delete the existing chup first
                try await publicDB.deleteRecord(withID: recordID)

                // If this is a big chup request, create a new one (allows upgrading/downgrading)
                // If it's a regular tap, just remove it (toggle off)
                if !isBigChup {
                    return .none
                }
                // Fall through to create big chup below
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — will be created on first save
        }

        // Create chup (either new or upgrade)
        do {
            let record = CKRecord(recordType: "WorkoutChup")
            record["workoutID"] = workoutID
            record["userID"] = userID
            record["username"] = username
            record["timestamp"] = Date() as NSDate
            record["isBigChup"] = (isBigChup ? 1 : 0) as NSNumber
            _ = try await publicDB.save(record)
            return isBigChup ? .big : .regular
        } catch let error as CKError where error.code == .permissionFailure {
            print("⚠️ Chup permission failure — record type may not exist in CloudKit schema. Run from Xcode first to auto-create, then deploy schema to Production.")
            errorMessage = "Chups not available yet. Please run the app from Xcode to initialize CloudKit schema."
            throw error
        }
    }

    func fetchChups(for workoutID: String) async -> ChupInfo {
        guard let userID = currentUserID else {
            return ChupInfo(totalCount: 0, regularCount: 0, bigChupCount: 0, currentUserChupType: .none)
        }
        do {
            let predicate = NSPredicate(format: "workoutID == %@", workoutID)
            let query = CKQuery(recordType: "WorkoutChup", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            var regularCount = 0
            var bigChupCount = 0
            var currentUserChupType: ChupType = .none

            for (_, result) in results {
                guard case .success(let record) = result else { continue }

                // Parse isBigChup field (default to 0/false for old records without this field)
                let isBigChup = (record["isBigChup"] as? NSNumber)?.intValue == 1

                if isBigChup {
                    bigChupCount += 1
                } else {
                    regularCount += 1
                }

                // Check if this is the current user's chup
                if let chupUserID = record["userID"] as? String, chupUserID == userID {
                    currentUserChupType = isBigChup ? .big : .regular
                }
            }

            return ChupInfo(
                totalCount: regularCount + bigChupCount,
                regularCount: regularCount,
                bigChupCount: bigChupCount,
                currentUserChupType: currentUserChupType
            )
        } catch {
            return ChupInfo(totalCount: 0, regularCount: 0, bigChupCount: 0, currentUserChupType: .none)
        }
    }

    func fetchChupUsers(for workoutID: String) async -> [ChupUser] {
        do {
            let predicate = NSPredicate(format: "workoutID == %@", workoutID)
            let query = CKQuery(recordType: "WorkoutChup", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            // Collect all chup records and unique user IDs
            var chupRecords: [(userID: String, username: String, timestamp: Date, isBigChup: Bool)] = []
            var userIDs: Set<String> = []

            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                guard let userID = record["userID"] as? String,
                      let username = record["username"] as? String,
                      let timestamp = record["timestamp"] as? Date else { continue }
                let isBigChup = (record["isBigChup"] as? NSNumber)?.intValue == 1
                chupRecords.append((userID, username, timestamp, isBigChup))
                userIDs.insert(userID)
            }

            // Build display name map: first check cached friends, then batch-fetch remaining from CloudKit
            var displayNames: [String: String] = [:]

            // Use cached friend data first (avoids CloudKit queries for known friends)
            for friend in friends {
                displayNames[friend.id] = friend.displayName
            }

            // Batch fetch profiles for users not in friend list
            let unknownIDs = userIDs.filter { displayNames[$0] == nil }
            for uid in unknownIDs {
                let profileID = CKRecord.ID(recordName: uid)
                if let record = try? await publicDB.record(for: profileID) {
                    displayNames[uid] = record["displayName"] as? String
                }
            }

            let chupUsers = chupRecords.map { r in
                ChupUser(
                    id: r.userID,
                    username: r.username,
                    displayName: displayNames[r.userID],
                    isBigChup: r.isBigChup,
                    timestamp: r.timestamp
                )
            }

            // Sort: big chups first (by timestamp desc), then regular chups (by timestamp desc)
            return chupUsers.sorted { lhs, rhs in
                if lhs.isBigChup && !rhs.isBigChup {
                    return true
                } else if !lhs.isBigChup && rhs.isBigChup {
                    return false
                } else {
                    return lhs.timestamp > rhs.timestamp
                }
            }
        } catch {
            return []
        }
    }

    // MARK: - Comments

    func postComment(workoutID: String, userID: String, username: String, text: String) async throws -> CommentInfo {
        let record = CKRecord(recordType: "WorkoutComment")
        record["workoutID"] = workoutID
        record["userID"] = userID
        record["username"] = username
        record["text"] = text
        record["timestamp"] = Date() as NSDate
        record["hearts"] = 0 as NSNumber

        do {
            let saved = try await publicDB.save(record)
            return CommentInfo(
                id: saved.recordID.recordName,
                userID: userID,
                username: username,
                text: text,
                timestamp: Date(),
                heartCount: 0,
                currentUserHearted: false
            )
        } catch let error as CKError where error.code == .permissionFailure {
            print("⚠️ Comment permission failure — record type may not exist in CloudKit schema. Run from Xcode first to auto-create, then deploy schema to Production.")
            errorMessage = "Comments not available yet. Please run the app from Xcode to initialize CloudKit schema."
            throw error
        }
    }

    func fetchComments(for workoutID: String) async -> [CommentInfo] {
        guard let userID = currentUserID else { return [] }
        do {
            let predicate = NSPredicate(format: "workoutID == %@", workoutID)
            let query = CKQuery(recordType: "WorkoutComment", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            // Collect all comment IDs for batch heart check
            let commentIDs = results.compactMap { (recordID, result) -> String? in
                guard case .success = result else { return nil }
                return recordID.recordName
            }

            // Batch fetch all hearts for current user in ONE query (replaces N+1 loop)
            var heartedCommentIDs: Set<String> = []
            if !commentIDs.isEmpty {
                do {
                    let heartPred = NSPredicate(format: "userID == %@ AND commentID IN %@", userID, commentIDs)
                    let heartQuery = CKQuery(recordType: "CommentHeart", predicate: heartPred)
                    let (heartResults, _) = try await publicDB.records(matching: heartQuery, resultsLimit: 200)
                    for (_, heartResult) in heartResults {
                        guard case .success(let record) = heartResult else { continue }
                        if let commentID = record["commentID"] as? String {
                            heartedCommentIDs.insert(commentID)
                        }
                    }
                } catch {
                    // Ignore heart fetch errors
                }
            }

            var comments: [CommentInfo] = []
            for (recordID, result) in results {
                guard case .success(let record) = result else { continue }
                let commentID = recordID.recordName

                comments.append(CommentInfo(
                    id: commentID,
                    userID: record["userID"] as? String ?? "",
                    username: record["username"] as? String ?? "",
                    text: record["text"] as? String ?? "",
                    timestamp: record["timestamp"] as? Date ?? Date(),
                    heartCount: (record["hearts"] as? NSNumber)?.intValue ?? 0,
                    currentUserHearted: heartedCommentIDs.contains(commentID)
                ))
            }
            return comments
        } catch {
            return []
        }
    }

    func toggleCommentHeart(commentID: String, userID: String) async throws -> Bool {
        // Check if user already hearted
        do {
            let predicate = NSPredicate(format: "commentID == %@ AND userID == %@", commentID, userID)
            let query = CKQuery(recordType: "CommentHeart", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

            if let (recordID, result) = results.first, case .success(_) = result {
                // Already hearted — remove it
                try await publicDB.deleteRecord(withID: recordID)
                return false
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet
        }

        // Not hearted — create heart
        let record = CKRecord(recordType: "CommentHeart")
        record["commentID"] = commentID
        record["userID"] = userID
        _ = try await publicDB.save(record)
        return true
    }

    // MARK: - Friendship Checks

    func checkFriendship(currentUserID: String, otherUserID: String) async -> Bool {
        do {
            // Check if there's an accepted request in either direction
            let pred1 = NSPredicate(format: "senderID == %@ AND receiverID == %@ AND status == %@", currentUserID, otherUserID, "accepted")
            let q1 = CKQuery(recordType: "FriendRequest", predicate: pred1)
            let (r1, _) = try await publicDB.records(matching: q1, resultsLimit: 1)
            if !r1.isEmpty { return true }

            let pred2 = NSPredicate(format: "senderID == %@ AND receiverID == %@ AND status == %@", otherUserID, currentUserID, "accepted")
            let q2 = CKQuery(recordType: "FriendRequest", predicate: pred2)
            let (r2, _) = try await publicDB.records(matching: q2, resultsLimit: 1)
            return !r2.isEmpty
        } catch {
            return false
        }
    }

    func hasPendingRequest(from senderID: String, to receiverID: String) async -> Bool {
        do {
            let predicate = NSPredicate(format: "senderID == %@ AND receiverID == %@ AND status == %@", senderID, receiverID, "pending")
            let query = CKQuery(recordType: "FriendRequest", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            return !results.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Friend Profile Data

    func fetchSharedWorkouts(for userID: String) async -> [SharedWorkoutResult] {
        do {
            let predicate = NSPredicate(format: "ownerID == %@", userID)
            let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)

            return results.compactMap { recordID, result in
                guard case .success(let record) = result else { return nil }
                let privacyString = record["privacy"] as? String ?? WorkoutPrivacy.friends.rawValue
                guard WorkoutPrivacy.includesFriends(privacyString) || WorkoutPrivacy.includesTeam(privacyString) else {
                    return nil
                }
                return SharedWorkoutResult(
                    id: recordID.recordName,
                    ownerID: record["ownerID"] as? String ?? userID,
                    ownerUsername: record["ownerUsername"] as? String ?? "",
                    ownerDisplayName: record["ownerDisplayName"] as? String ?? "",
                    workoutDate: record["workoutDate"] as? Date ?? Date(),
                    workoutType: record["workoutType"] as? String ?? "",
                    totalTime: record["totalTime"] as? String ?? "",
                    totalDistance: (record["totalDistance"] as? NSNumber)?.intValue ?? 0,
                    averageSplit: record["averageSplit"] as? String ?? "",
                    intensityZone: record["intensityZone"] as? String ?? "",
                    isErgTest: (record["isErgTest"] as? NSNumber)?.intValue == 1,
                    privacy: privacyString,
                    submittedByCoxUsername: record["submittedByCoxUsername"] as? String
                )
            }
        } catch {
            return []
        }
    }

    func fetchSharedWorkout(recordID: String) async -> SharedWorkoutResult? {
        do {
            let ckRecordID = CKRecord.ID(recordName: recordID)
            let record = try await publicDB.record(for: ckRecordID)

            return SharedWorkoutResult(
                id: ckRecordID.recordName,
                ownerID: record["ownerID"] as? String ?? "",
                ownerUsername: record["ownerUsername"] as? String ?? "",
                ownerDisplayName: record["ownerDisplayName"] as? String ?? "",
                workoutDate: record["workoutDate"] as? Date ?? Date(),
                workoutType: record["workoutType"] as? String ?? "",
                totalTime: record["totalTime"] as? String ?? "",
                totalDistance: (record["totalDistance"] as? NSNumber)?.intValue ?? 0,
                averageSplit: record["averageSplit"] as? String ?? "",
                intensityZone: record["intensityZone"] as? String ?? "",
                isErgTest: (record["isErgTest"] as? NSNumber)?.intValue == 1,
                privacy: record["privacy"] as? String ?? "friends",
                submittedByCoxUsername: record["submittedByCoxUsername"] as? String
            )
        } catch {
            print("⚠️ Failed to fetch shared workout \(recordID): \(error)")
            return nil
        }
    }

    func fetchFriendCount(for userID: String) async -> Int {
        do {
            let pred1 = NSPredicate(format: "senderID == %@ AND status == %@", userID, "accepted")
            let q1 = CKQuery(recordType: "FriendRequest", predicate: pred1)
            let (r1, _) = try await publicDB.records(matching: q1, resultsLimit: 200)

            let pred2 = NSPredicate(format: "receiverID == %@ AND status == %@", userID, "accepted")
            let q2 = CKQuery(recordType: "FriendRequest", predicate: pred2)
            let (r2, _) = try await publicDB.records(matching: q2, resultsLimit: 200)

            // Collect unique friend IDs
            var friendIDs = Set<String>()
            for (_, result) in r1 {
                guard case .success(let record) = result else { continue }
                if let receiverID = record["receiverID"] as? String { friendIDs.insert(receiverID) }
            }
            for (_, result) in r2 {
                guard case .success(let record) = result else { continue }
                if let senderID = record["senderID"] as? String { friendIDs.insert(senderID) }
            }
            return friendIDs.count
        } catch {
            return 0
        }
    }

    func fetchUserProfile(for userID: String) async -> UserProfileResult? {
        do {
            let recordID = CKRecord.ID(recordName: userID)
            let record = try await publicDB.record(for: recordID)
            return UserProfileResult(
                id: record["appleUserID"] as? String ?? userID,
                username: record["username"] as? String ?? "",
                displayName: record["displayName"] as? String ?? "",
                recordID: recordID
            )
        } catch {
            return nil
        }
    }

    // MARK: - Profile Role

    func updateProfileRole(_ role: String) async {
        guard let userID = currentUserID else { return }

        // Load profile if needed
        if myProfile == nil {
            await loadMyProfile()
        }

        guard let profile = myProfile else {
            print("⚠️ No profile to update role on")
            return
        }

        profile["role"] = role
        do {
            let saved = try await publicDB.save(profile)
            myProfile = saved
            print("✅ Updated profile role to: \(role)")
        } catch {
            print("❌ Failed to update profile role: \(error)")
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
