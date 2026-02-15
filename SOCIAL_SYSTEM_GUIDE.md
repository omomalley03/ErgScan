# Social System Architecture Guide

## Overview

The ErgScan1 social system enables users to connect with friends, share workouts, and interact through "chups" (likes) and comments. Built on **CloudKit Public Database**, the system provides real-time social features without requiring a custom backend server.

---

## Table of Contents

1. [Core Components](#core-components)
2. [User Identity & Profiles](#user-identity--profiles)
3. [Friend System](#friend-system)
4. [Workout Sharing](#workout-sharing)
5. [Social Interactions](#social-interactions)
6. [CloudKit Record Types](#cloudkit-record-types)
7. [Key Files & Architecture](#key-files--architecture)
8. [Data Flow Diagrams](#data-flow-diagrams)

---

## Core Components

### 1. SocialService (`SocialService.swift`)

The central service managing all social features. Marked `@MainActor` for thread-safe UI updates.

**Key Responsibilities:**
- User profile management (create, update, fetch)
- Friend request handling (send, accept, reject, unfriend)
- Workout publishing and fetching
- Social interactions (chups, comments)
- CloudKit communication

**Published State:**
```swift
@Published var myProfile: CKRecord?              // Current user's CloudKit profile
@Published var friends: [UserProfileResult]       // List of accepted friends
@Published var pendingRequests: [FriendRequestResult]  // Incoming friend requests
@Published var friendActivity: [SharedWorkoutResult]   // Recent workouts from friends + self
@Published var searchResults: [UserProfileResult]      // User search results
@Published var sentRequestIDs: Set<String>        // Track sent requests (UI state)
```

**Initialization:**
```swift
func setCurrentUser(_ appleUserID: String, context: ModelContext)
```
- Called when user signs in with Apple ID
- Checks CloudKit availability
- Loads user's profile
- Publishes existing workouts (delayed background task)

---

## User Identity & Profiles

### Local User Model (SwiftData)

**File:** `Models/User.swift`

```swift
@Model
final class User {
    var id: UUID                    // Local database ID
    var appleUserID: String         // ⭐ Unique Apple ID (primary identifier)
    var email: String?              // Optional (may be hidden)
    var fullName: String?           // Optional (may be hidden)
    var username: String?           // ⭐ Social username (unique, required for social features)
    var createdAt: Date
    var lastSignInAt: Date

    @Relationship(deleteRule: .cascade)
    var workouts: [Workout]?
}
```

**Key Points:**
- **appleUserID**: The primary identifier across the entire app. Every CloudKit record references this.
- **username**: Must be set before using social features (3-20 chars, lowercase, alphanumeric + underscore, must start with letter)
- Stored locally in SwiftData, synced with CloudKit UserProfile

### CloudKit UserProfile Record

**Record Type:** `UserProfile`
**Record Name:** User's `appleUserID` (ensures one profile per Apple ID)

**Fields:**
```
appleUserID: String       // Apple ID (indexed)
username: String          // Unique social handle (indexed for search)
displayName: String       // Full name or display name (indexed for search)
createdAt: Date          // Profile creation timestamp
```

**Creation Flow:**

1. User completes onboarding and chooses a username
2. `SocialService.saveUsername(_:displayName:context:)` called
3. Validates username format (regex: `^[a-z][a-z0-9_]{2,19}$`)
4. Checks uniqueness via CloudKit query
5. Creates/updates CloudKit record with `recordName = appleUserID`
6. Syncs username back to local SwiftData User model
7. Publishes all existing workouts to CloudKit

**Username Validation:**
- Must be 3-20 characters
- Lowercase only
- Start with a letter
- Only letters, numbers, and underscores
- Must be globally unique across all users

---

## Friend System

### Friend Request Model

**CloudKit Record Type:** `FriendRequest`

**Fields:**
```
senderID: String          // Apple ID of request sender
receiverID: String        // Apple ID of request receiver
senderUsername: String    // Display info for UI
senderDisplayName: String // Display info for UI
status: String            // "pending", "accepted", or "rejected"
createdAt: Date          // Request timestamp
```

### Friendship Mechanics

**Bidirectional Relationship:**
- When User A sends a request to User B → creates `FriendRequest` record
- When User B accepts → creates **new** `FriendRequest` record (reversed direction)
- Both records have `status: "accepted"`
- Why two records? CloudKit security: only record creator can modify their own records

**Example:**
```
User A sends request to User B:
  Record 1: { senderID: A, receiverID: B, status: "pending" }

User B accepts:
  Record 2: { senderID: B, receiverID: A, status: "accepted" }
  (Record 1 stays as "pending" — both records establish friendship)
```

**Checking Friendship:**
```swift
func checkFriendship(currentUserID: String, otherUserID: String) async -> Bool
```
- Queries for accepted requests in **both** directions
- Returns `true` if either direction has `status: "accepted"`

### Friend Request Flow

#### 1. Send Friend Request
**Function:** `sendFriendRequest(to receiverID: String)`

**Steps:**
1. Validate: prevent self-friending (`receiverID != currentUserID`)
2. Check for existing request (either direction)
3. Create new `FriendRequest` record with `status: "pending"`
4. Add to `sentRequestIDs` set (for UI state)

**UI:** `FriendsView.swift` → Search bar → Send request button

#### 2. Accept Friend Request
**Function:** `acceptRequest(_ request: FriendRequestResult)`

**Steps:**
1. Creates **new** `FriendRequest` record:
   - `senderID`: Current user
   - `receiverID`: Original sender
   - `status: "accepted"`
2. Refreshes friends list
3. Loads friend activity

**UI:** `FriendsView.swift` → Pending Requests section → Accept button

#### 3. Reject Friend Request
**Function:** `rejectRequest(_ request: FriendRequestResult)`

**Steps:**
1. Creates rejection record with `status: "rejected"`
2. Removes from `pendingRequests` array
3. No friendship established

#### 4. Unfriend
**Function:** `unfriend(_ friendID: String)`

**Steps:**
1. Query for **all** accepted requests between users (both directions)
2. Delete all found records via `modifyRecords(saving: [], deleting:)`
3. Refresh friends list and activity feed

**UI:** `FriendProfileView.swift` → Toolbar → Unfriend button (with confirmation alert)

### Loading Friends
**Function:** `loadFriends()`

**Steps:**
1. Query `FriendRequest` where `senderID == currentUserID AND status == "accepted"`
2. Query `FriendRequest` where `receiverID == currentUserID AND status == "accepted"`
3. Extract unique friend IDs from both result sets
4. Fetch `UserProfile` records for each friend ID
5. Populate `friends` array with `UserProfileResult` objects

---

## Workout Sharing

### SharedWorkout Record

**CloudKit Record Type:** `SharedWorkout`

**Fields:**
```
ownerID: String              // Apple ID of workout owner (indexed)
ownerUsername: String        // Display name for feed
ownerDisplayName: String     // Display name for feed
workoutDate: Date            // Workout date (indexed for sorting)
workoutType: String          // "2000m", "3x4:00/3:00r", etc.
totalTime: String            // "06:30.0"
totalDistance: Int           // Meters
averageSplit: String         // "01:37.5"
intensityZone: String        // "Zone2", "Zone4", etc.
isErgTest: Bool              // Test flag (stored as 0/1)
localWorkoutID: String       // UUID of local Workout (for deduplication)
createdAt: Date             // Share timestamp
```

### WorkoutDetail Record (Full Data)

**CloudKit Record Type:** `WorkoutDetail`

**Fields:**
```
localWorkoutID: String            // UUID reference
ownerID: String                   // Apple ID
sharedWorkoutID: CKReference      // Link to SharedWorkout (cascade delete)
ergImage: CKAsset                // Photo of erg monitor
intervalsJSON: String            // JSON-encoded array of intervals
ocrConfidence: Double            // OCR quality score
wasManuallyEdited: Bool          // Edit flag (0/1)
createdAt: Date
```

**Intervals JSON Format:**
```json
[
  {
    "orderIndex": 0,
    "time": "20:00.0",
    "meters": 5000,
    "splitPer500m": "02:00.0",
    "strokeRate": 22,
    "heartRate": 165,
    "timeConfidence": 0.98,
    "metersConfidence": 0.99,
    "splitConfidence": 0.97,
    "rateConfidence": 0.96,
    "heartRateConfidence": 0.95
  },
  ...
]
```

### Publishing Workouts

**Automatic Publishing:**
- Triggered on app startup (5-second delay)
- Called after username setup
- Function: `publishExistingWorkouts()`

**Manual Publishing:**
- Called when saving a new workout
- Function: `publishWorkout(...)`

**Publishing Process:**

1. **Check Prerequisites:**
   - User has valid CloudKit profile
   - Username is set

2. **Create/Update SharedWorkout:**
   - Check for existing record by `localWorkoutID` (deduplication)
   - Save/update record with workout summary data

3. **Upload WorkoutDetail (if available):**
   - Fetch full Workout from SwiftData by UUID
   - Encode intervals array to JSON
   - Write image data to temp file → create `CKAsset`
   - Link to SharedWorkout via `CKReference` (cascade delete)
   - Save WorkoutDetail record

**Deduplication:**
- Uses `localWorkoutID` (UUID) to prevent duplicate shares
- Updates existing record instead of creating new one

### Fetching Friend Workouts

**Function:** `loadFriendActivity()`

**Steps:**
1. Query `SharedWorkout` for current user (last 10)
2. Query `SharedWorkout` for each friend (last 3 per friend)
3. Combine results
4. Sort by `workoutDate` descending
5. Populate `friendActivity` array

**Result Type:**
```swift
struct SharedWorkoutResult: Identifiable, Hashable {
    let id: String                    // CloudKit recordName
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
```

**Display:** `DashboardView.swift` → Friends Activity section → `WorkoutFeedCard`

---

## Social Interactions

### Chups (Likes)

**CloudKit Record Type:** `WorkoutChup`

**Fields:**
```
workoutID: String      // SharedWorkout recordName
userID: String         // Apple ID of user who chupped
username: String       // Display name
timestamp: Date        // When chupped
```

**Toggle Chup:**
```swift
func toggleChup(workoutID: String, userID: String, username: String) async throws -> Bool
```
- Query for existing chup by `workoutID` and `userID`
- If exists: delete record (unchup) → return `false`
- If not: create record (chup) → return `true`

**Fetch Chups:**
```swift
func fetchChups(for workoutID: String) async -> ChupInfo
```
- Returns count and whether current user chupped
- Used by `WorkoutFeedCard` to display chup button state

**Special Feature: Big Chup**
- Long-press on chup button (1+ seconds)
- Triggers haptic feedback + animation
- Also chups if not already chupped

### Comments

**CloudKit Record Type:** `WorkoutComment`

**Fields:**
```
workoutID: String      // SharedWorkout recordName
userID: String         // Apple ID of commenter
username: String       // Display name
text: String           // Comment content
timestamp: Date        // When posted
hearts: Int            // Heart count (placeholder field)
```

**Post Comment:**
```swift
func postComment(workoutID: String, userID: String, username: String, text: String) async throws -> CommentInfo
```
- Creates new `WorkoutComment` record
- Returns `CommentInfo` for immediate UI update

**Fetch Comments:**
```swift
func fetchComments(for workoutID: String) async -> [CommentInfo]
```
- Queries all comments for workout
- Sorted by timestamp (ascending)
- Checks if current user hearted each comment

**Comment Hearts:**

**CloudKit Record Type:** `CommentHeart`

**Fields:**
```
commentID: String      // WorkoutComment recordName
userID: String         // Apple ID of user who hearted
```

**Toggle Heart:**
```swift
func toggleCommentHeart(commentID: String, userID: String) async throws -> Bool
```
- Similar to chup toggle logic
- Returns `true` if hearted, `false` if unhearted

**UI:** `CommentsView.swift` → Sheet presented from `WorkoutFeedCard`

---

## CloudKit Record Types

### Summary Table

| Record Type | Purpose | Key Fields | Indexed Fields |
|------------|---------|------------|----------------|
| **UserProfile** | User identity | appleUserID, username, displayName | appleUserID, username, displayName |
| **FriendRequest** | Friend connections | senderID, receiverID, status | senderID, receiverID, status |
| **SharedWorkout** | Workout summaries | ownerID, workoutDate, workoutType | ownerID, workoutDate |
| **WorkoutDetail** | Full workout data | ergImage, intervalsJSON, sharedWorkoutID | localWorkoutID, ownerID |
| **WorkoutChup** | Likes | workoutID, userID | workoutID, userID |
| **WorkoutComment** | Comments | workoutID, userID, text | workoutID |
| **CommentHeart** | Comment likes | commentID, userID | commentID, userID |

### Record Type Creation

CloudKit record types are **auto-created** on first write when running from Xcode (Development environment). For Production:
1. Run app from Xcode to create record types in Development
2. Use CloudKit Dashboard to deploy schema to Production
3. Permission errors in production indicate schema not deployed

---

## Key Files & Architecture

### Service Layer

**File:** `Services/SocialService.swift` (1230 lines)

**Major Functions:**
- Profile: `loadMyProfile()`, `saveUsername()`, `checkUsernameAvailability()`
- Search: `searchUsers(query:)`
- Friends: `sendFriendRequest()`, `acceptRequest()`, `rejectRequest()`, `unfriend()`, `loadFriends()`, `loadPendingRequests()`
- Workouts: `publishWorkout()`, `deleteSharedWorkout()`, `publishWorkoutDetail()`, `fetchWorkoutDetail()`, `loadFriendActivity()`
- Interactions: `toggleChup()`, `fetchChups()`, `postComment()`, `fetchComments()`, `toggleCommentHeart()`

### Models

**Files:**
- `Models/User.swift` - Local user model (SwiftData)
- `Models/SocialModels.swift` - `ChupInfo`, `CommentInfo`, `ProfileRelationship`
- `Models/WorkoutDisplayable.swift` - Protocol for unified workout display

**WorkoutDisplayable Protocol:**
```swift
protocol WorkoutDisplayable {
    var displayName: String { get }
    var displayUsername: String { get }
    var displayDate: Date { get }
    var displayWorkoutType: String { get }
    var displayTotalTime: String { get }
    var displayTotalDistance: Int { get }
    var displayAverageSplit: String { get }
    var displayIntensityZone: IntensityZone? { get }
    var displayIsErgTest: Bool { get }
    var workoutRecordID: String { get }
    var ownerUserID: String { get }
}
```

Conformed by:
- `Workout` (local SwiftData model)
- `SocialService.SharedWorkoutResult` (CloudKit result)

**Purpose:** Allows `WorkoutFeedCard` to display both local and remote workouts with same UI

### Views

#### Main Social Views

**File:** `Views/FriendsView.swift`
- Search bar with debounced user search
- Pending friend requests section
- Friends list preview (first 5)
- Search results with "Add Friend" buttons
- Requires username to be set (gate screen if not)

**File:** `Views/FriendsListView.swift`
- Full friends list
- Pending requests (with accept/reject buttons)
- Sent requests (pending status)
- Navigation to friend profiles

**File:** `Views/FriendProfileView.swift`
- Profile header (avatar, username, display name, friend count)
- Relationship status handling:
  - `.friends` → Show full workout list
  - `.notFriends` → Private profile placeholder with "Send Request"
  - `.requestSentByMe` → "Request Pending"
  - `.requestSentToMe` → "Accept Request" button
- Unfriend button (toolbar, friends only)
- Navigation to `UnifiedWorkoutDetailView` on tap

**File:** `Views/DashboardView.swift`
- Weekly meter goal progress
- Swipeable weekly chart
- **Friends Activity Feed:**
  - Displays `socialService.friendActivity` (own workouts + friends)
  - Uses `WorkoutFeedCard` components
  - Tap to open `UnifiedWorkoutDetailView`

#### Components

**File:** `Views/Components/WorkoutFeedCard.swift`
- Profile header (avatar, username, date)
- Workout summary (type, time, distance, split, zone)
- Chup button with counter
- Comment button with count
- Comment preview (latest comment)
- Long-press chup → Big Chup animation
- Opens `CommentsView` sheet

**File:** `Views/Components/FriendRequestCard.swift`
- Request sender info
- Accept/reject buttons
- Used in `FriendsView` pending section

**File:** `Views/CommentsView.swift`
- Full comment thread
- Post new comment
- Heart button per comment
- Workout summary header

**File:** `Views/EnhancedWorkoutDetailView.swift`
- Displays full workout details
- Handles both local workouts and shared workouts
- Fetches `WorkoutDetail` from CloudKit for shared workouts
- Shows erg image, intervals/splits, chups, comments

---

## Data Flow Diagrams

### 1. App Startup → Social Initialization

```
App Launch
  └─> AuthService.signInSilently()
       └─> Creates/loads User in SwiftData
            └─> SocialService.setCurrentUser(appleUserID, context)
                 ├─> checkCloudKitStatus()
                 ├─> loadMyProfile() (parallel)
                 └─> publishExistingWorkouts() (delayed background, 5s)
```

### 2. Friend Request Flow

```
User A                          CloudKit                        User B
  │                                │                              │
  │ 1. Search for User B           │                              │
  ├───> searchUsers("userB")       │                              │
  │     (query UserProfile)        │                              │
  │                                │                              │
  │ 2. Send Friend Request         │                              │
  ├───> sendFriendRequest()        │                              │
  │     (create FriendRequest      │                              │
  │      senderID=A, receiverID=B  │                              │
  │      status="pending")         │                              │
  │                                │                              │
  │                                │     3. Load Pending Requests │
  │                                │     <───────────────────────┤
  │                                │     (query receiverID=B,     │
  │                                │      status="pending")       │
  │                                │                              │
  │                                │     4. Accept Request        │
  │                                │     <───────────────────────┤
  │                                │     (create FriendRequest    │
  │                                │      senderID=B, receiverID=A│
  │                                │      status="accepted")      │
  │                                │                              │
  │ 5. Load Friends                │                              │
  ├───> loadFriends()              │                              │
  │     (query accepted requests   │                              │
  │      in both directions)       │                              │
  │                                │                              │
  │ ✅ Users A & B are friends     │     ✅ Users A & B are friends
```

### 3. Workout Publishing Flow

```
User saves workout in app
  │
  └─> WorkoutManager.saveWorkout()
       ├─> Save to local SwiftData
       └─> SocialService.publishWorkout()
            ├─> Check for existing SharedWorkout (by localWorkoutID)
            ├─> Create/update SharedWorkout record
            │    └─> Summary data (type, time, distance, split, zone)
            └─> publishWorkoutDetail()
                 ├─> Encode intervals → JSON
                 ├─> Write image → temp file → CKAsset
                 └─> Create WorkoutDetail record
                      └─> Reference to SharedWorkout (cascade delete)
```

### 4. Friend Activity Feed Loading

```
DashboardView appears
  │
  └─> socialService.loadFriendActivity()
       ├─> Query own SharedWorkouts (last 10)
       ├─> For each friend:
       │    └─> Query SharedWorkout (last 3)
       ├─> Combine all results
       ├─> Sort by workoutDate descending
       └─> Set friendActivity array
            │
            └─> UI updates
                 └─> ForEach(friendActivity) { workout in
                          WorkoutFeedCard(workout)
                               ├─> Fetch chups for workout
                               └─> Fetch comments for workout
                     }
```

### 5. Viewing Friend's Workout

```
User taps WorkoutFeedCard on dashboard
  │
  └─> Set selectedFeedWorkout state
       │
       └─> Navigate to UnifiedWorkoutDetailView(sharedWorkout:)
            │
            ├─> Check if localWorkout exists (is it own workout?)
            │    ├─> Yes → Load from SwiftData (full data available)
            │    └─> No → Fetch from CloudKit
            │             │
            │             └─> fetchWorkoutDetail(sharedWorkoutID)
            │                  ├─> Query WorkoutDetail by reference
            │                  ├─> Download ergImage (CKAsset)
            │                  ├─> Parse intervalsJSON
            │                  └─> Display full workout with image
            │
            ├─> Show workout summary
            ├─> Show erg image (if available)
            ├─> Show intervals/splits
            ├─> Load chups
            └─> Load comments
```

### 6. Chup (Like) Interaction

```
User taps Chup button on WorkoutFeedCard
  │
  └─> SocialService.toggleChup(workoutID, userID, username)
       │
       ├─> Query existing WorkoutChup (workoutID + userID)
       │
       ├─> If found:
       │    └─> Delete record (unchup)
       │         └─> Return false
       │
       └─> If not found:
            └─> Create WorkoutChup record
                 └─> Return true
                      │
                      └─> Update UI:
                           ├─> Toggle heart icon
                           ├─> Update count (+1 or -1)
                           └─> Play haptic feedback
```

---

## Security & Privacy

### CloudKit Permissions

- **Public Database:** All social data stored here (anyone can read)
- **Record Ownership:** Only record creator can modify their records
- **Friend Request Pattern:** Uses dual records to enforce ownership boundaries
- **Private Data:** User email/fullName stored only locally (SwiftData), never in CloudKit

### Data Visibility

**Before Friendship:**
- Can see username, display name, friend count
- Cannot see workouts
- Can send friend request

**After Friendship:**
- Can see all shared workouts
- Can view full workout details (image, intervals)
- Can chup and comment

**Self-Friending Prevention:**
- Blocked at API level (`receiverID != currentUserID`)
- Blocked at UI level (own profile shows as friend, no add button)

---

## Common Patterns

### CloudKit Query Pattern

```swift
let predicate = NSPredicate(format: "field == %@", value)
let query = CKQuery(recordType: "RecordType", predicate: predicate)
query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
let (results, _) = try await publicDB.records(matching: query, resultsLimit: 50)

for (recordID, result) in results {
    guard case .success(let record) = result else { continue }
    // Process record
}
```

### Error Handling: Unknown Item

When record type doesn't exist yet (first run, Development → Production):

```swift
catch let error as CKError where error.code == .unknownItem {
    // Record type doesn't exist yet — will auto-create on first save
    return []  // or default value
}
```

### Deduplication Pattern

```swift
// Check for existing record
let predicate = NSPredicate(format: "uniqueField == %@", uniqueValue)
let query = CKQuery(recordType: "RecordType", predicate: predicate)
let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)

var record: CKRecord
if let (_, result) = results.first, case .success(let existingRecord) = result {
    record = existingRecord  // Update existing
} else {
    record = CKRecord(recordType: "RecordType")  // Create new
}

// Update fields
record["field"] = value

// Save
try await publicDB.save(record)
```

---

## Troubleshooting

### "Username not available yet"

**Cause:** User hasn't set username in Settings
**Solution:** Navigate to Settings → Set Username

### "CloudKit temporarily unavailable"

**Cause:** Network issues or iCloud signed out
**Solution:** Check iCloud settings, ensure signed in

### "Chups/Comments not available yet"

**Cause:** Record types don't exist in Production
**Solution:**
1. Run app from Xcode (creates types in Development)
2. CloudKit Dashboard → Deploy schema to Production

### "Duplicate workout IDs in feed"

**Cause:** Rare — user friended themselves before prevention added
**Solution:** Unfriend self, prevention now blocks this

### Friend workouts not loading

**Cause:** Not friends / friendship not established
**Solution:**
1. Check friendship status: `checkFriendship()`
2. Verify accepted FriendRequest records exist (both directions)
3. Refresh friends list

---

## Performance Considerations

### Query Limits

- Friends list: 100 records
- Friend activity: 10 own workouts + 3 per friend
- Search results: 20 records
- Chups: 100 per workout
- Comments: 100 per workout

### Background Publishing

Existing workouts published with 5-second delay on startup to avoid blocking UI

### Caching

No explicit caching — relies on CloudKit's built-in caching and `@Published` state

---

## Future Enhancements

Potential features not yet implemented:

- **Notifications:** Push notifications for friend requests, chups, comments
- **Workout Privacy:** Option to share only specific workouts
- **Friend Groups:** Organize friends into teams/crews
- **Leaderboards:** Weekly/monthly distance rankings
- **Activity Feed Filtering:** Filter by friend, workout type, date range
- **Direct Messaging:** Private messages between friends
- **Profile Pictures:** Upload custom avatars
- **Workout Reactions:** More expressive reactions beyond chups
- **Comment Threading:** Reply to specific comments

---

## Summary

The ErgScan1 social system provides a complete social workout-sharing platform using CloudKit as the backend. Key design principles:

1. **Simplicity:** No custom server required
2. **Security:** CloudKit record ownership + bidirectional friendship pattern
3. **Performance:** Efficient queries with limits and indexes
4. **Extensibility:** Clear separation of concerns (service, models, views)
5. **User Control:** Username required before social features unlock

The system successfully enables users to connect, share workouts, and engage with each other's fitness progress in a privacy-respecting, performant way.
