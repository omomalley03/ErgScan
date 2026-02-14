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

    // MARK: - Profile Management

    func setCurrentUser(_ appleUserID: String, context: ModelContext) {
        currentUserID = appleUserID
        modelContext = context
        Task {
            await checkCloudKitStatus()
            await loadMyProfile()
            // Publish any existing workouts that haven't been shared yet
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
        } catch {
            print("⚠️ Failed to publish workout: \(error)")
        }
    }

    func deleteSharedWorkout(localWorkoutID: String) async {
        guard let userID = currentUserID else {
            print("⚠️ deleteSharedWorkout: no currentUserID")
            return
        }
        do {
            let predicate = NSPredicate(format: "ownerID == %@ AND localWorkoutID == %@", userID, localWorkoutID)
            let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            if results.isEmpty {
                print("ℹ️ deleteSharedWorkout: no SharedWorkout found for localWorkoutID=\(localWorkoutID)")
            }
            for (recordID, result) in results {
                guard case .success(_) = result else { continue }
                try await publicDB.deleteRecord(withID: recordID)
                print("✅ Deleted SharedWorkout record: \(recordID.recordName)")
            }
        } catch let error as CKError where error.code == .unknownItem {
            // SharedWorkout type doesn't exist yet — nothing to delete
        } catch {
            print("⚠️ Failed to delete SharedWorkout (localWorkoutID=\(localWorkoutID)): \(error)")
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
    func publishExistingWorkouts() async {
        guard let userID = currentUserID,
              let context = modelContext,
              myProfile != nil else { return }

        let username = myProfile?["username"] as? String ?? ""
        guard !username.isEmpty else { return }

        let targetUserID = userID
        do {
            let descriptor = FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.userID == targetUserID
                }
            )
            let workouts = try context.fetch(descriptor)
            guard !workouts.isEmpty else { return }
            print("📤 Publishing \(workouts.count) existing workouts...")

            for workout in workouts {
                await publishWorkout(
                    workoutType: workout.workoutType,
                    date: workout.date,
                    totalTime: workout.totalTime,
                    totalDistance: workout.totalDistance ?? 0,
                    averageSplit: workout.averageSplit ?? "",
                    intensityZone: workout.intensityZone ?? "",
                    isErgTest: workout.isErgTest,
                    localWorkoutID: workout.id.uuidString
                )
            }
            print("✅ Finished publishing existing workouts")
        } catch {
            print("⚠️ Failed to publish existing workouts: \(error)")
        }
    }

    func loadFriendActivity() async {
        // Ensure friends are loaded
        if friends.isEmpty {
            await loadFriends()
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var allWorkouts: [SharedWorkoutResult] = []

            // Include current user's own shared workouts
            if let userID = currentUserID {
                let ownPredicate = NSPredicate(format: "ownerID == %@", userID)
                let ownQuery = CKQuery(recordType: "SharedWorkout", predicate: ownPredicate)
                ownQuery.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]
                let (ownResults, _) = try await publicDB.records(matching: ownQuery, resultsLimit: 10)
                for (recordID, result) in ownResults {
                    guard case .success(let record) = result else { continue }
                    allWorkouts.append(sharedWorkoutResult(from: record, recordID: recordID, fallbackID: userID, fallbackUsername: myProfile?["username"] as? String ?? "", fallbackDisplayName: myProfile?["displayName"] as? String ?? ""))
                }
            }

            // Query last 3 workouts per friend
            for friend in friends {
                let predicate = NSPredicate(format: "ownerID == %@", friend.id)
                let query = CKQuery(recordType: "SharedWorkout", predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "workoutDate", ascending: false)]
                let (results, _) = try await publicDB.records(matching: query, resultsLimit: 3)

                for (recordID, result) in results {
                    guard case .success(let record) = result else { continue }
                    allWorkouts.append(sharedWorkoutResult(from: record, recordID: recordID, fallbackID: friend.id, fallbackUsername: friend.username, fallbackDisplayName: friend.displayName))
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
            isErgTest: (record["isErgTest"] as? NSNumber)?.intValue == 1
        )
    }

    // MARK: - Chups

    func toggleChup(workoutID: String, userID: String, username: String) async throws -> Bool {
        // Check if user already chupped
        do {
            let predicate = NSPredicate(format: "workoutID == %@ AND userID == %@", workoutID, userID)
            let query = CKQuery(recordType: "WorkoutChup", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

            if let (recordID, result) = results.first, case .success(_) = result {
                // Already chupped — remove it
                try await publicDB.deleteRecord(withID: recordID)
                return false
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Record type doesn't exist yet — will be created on first save
        }

        // Not chupped yet — create chup
        do {
            let record = CKRecord(recordType: "WorkoutChup")
            record["workoutID"] = workoutID
            record["userID"] = userID
            record["username"] = username
            record["timestamp"] = Date() as NSDate
            _ = try await publicDB.save(record)
            return true
        } catch let error as CKError where error.code == .permissionFailure {
            print("⚠️ Chup permission failure — record type may not exist in CloudKit schema. Run from Xcode first to auto-create, then deploy schema to Production.")
            errorMessage = "Chups not available yet. Please run the app from Xcode to initialize CloudKit schema."
            throw error
        }
    }

    func fetchChups(for workoutID: String) async -> ChupInfo {
        guard let userID = currentUserID else {
            return ChupInfo(count: 0, currentUserChupped: false)
        }
        do {
            let predicate = NSPredicate(format: "workoutID == %@", workoutID)
            let query = CKQuery(recordType: "WorkoutChup", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            var count = 0
            var currentUserChupped = false
            for (_, result) in results {
                guard case .success(let record) = result else { continue }
                count += 1
                if let chupUserID = record["userID"] as? String, chupUserID == userID {
                    currentUserChupped = true
                }
            }
            return ChupInfo(count: count, currentUserChupped: currentUserChupped)
        } catch {
            return ChupInfo(count: 0, currentUserChupped: false)
        }
    }

    func fetchChupUsers(for workoutID: String) async -> [String] {
        do {
            let predicate = NSPredicate(format: "workoutID == %@", workoutID)
            let query = CKQuery(recordType: "WorkoutChup", predicate: predicate)
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 100)

            return results.compactMap { _, result in
                guard case .success(let record) = result else { return nil }
                return record["username"] as? String
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

            var comments: [CommentInfo] = []
            for (recordID, result) in results {
                guard case .success(let record) = result else { continue }
                let commentID = recordID.recordName

                // Check if current user hearted this comment
                var hearted = false
                do {
                    let heartPred = NSPredicate(format: "commentID == %@ AND userID == %@", commentID, userID)
                    let heartQuery = CKQuery(recordType: "CommentHeart", predicate: heartPred)
                    let (heartResults, _) = try await publicDB.records(matching: heartQuery, resultsLimit: 1)
                    hearted = !heartResults.isEmpty
                } catch {
                    // Ignore heart fetch errors
                }

                comments.append(CommentInfo(
                    id: commentID,
                    userID: record["userID"] as? String ?? "",
                    username: record["username"] as? String ?? "",
                    text: record["text"] as? String ?? "",
                    timestamp: record["timestamp"] as? Date ?? Date(),
                    heartCount: (record["hearts"] as? NSNumber)?.intValue ?? 0,
                    currentUserHearted: hearted
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
                    isErgTest: (record["isErgTest"] as? NSNumber)?.intValue == 1
                )
            }
        } catch {
            return []
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
