# ErgScan Friends Feature Improvements — Claude Code Implementation Plan

## Overview

This plan covers four major changes:
1. **Profile page friends list** with friend requests management
2. **Clickable profile icons** linking to user profile pages with workout history
3. **Move friends feed to Dashboard** (last 3 workouts per friend, sorted by date then username)
4. **Redesigned workout cards** with Chups (likes), comments, and new layout

---

## Phase 1: Data Model & Service Layer Changes

### 1A. New CloudKit Record Types in `SocialService.swift`

Add support for two new record types in the CloudKit public database:

**`WorkoutChup` record type:**
- `workoutID` (String) — the SharedWorkout record ID
- `userID` (String) — Apple ID of the user who chupped
- `username` (String) — display username of chupper
- `timestamp` (Date)

**`WorkoutComment` record type:**
- `workoutID` (String) — the SharedWorkout record ID  
- `userID` (String) — commenter's Apple ID
- `username` (String) — commenter's display username
- `profileImageURL` (String, optional)
- `text` (String) — comment body
- `timestamp` (Date)
- `hearts` (Int) — number of hearts on this comment

**`CommentHeart` record type:**
- `commentID` (String) — the WorkoutComment record ID
- `userID` (String) — who hearted it

### 1B. Add SocialService Methods

Add these methods to `SocialService.swift`:

```swift
// --- Friends List ---
func fetchAcceptedFriends(for userID: String) async throws -> [UserProfile]
// Query FriendRequest where (senderID == userID OR receiverID == userID) AND status == "accepted"
// Return the other user's profile for each

func fetchPendingRequestsToMe(for userID: String) async throws -> [FriendRequest]
// FriendRequest where receiverID == userID AND status == "pending"

func fetchPendingRequestsFromMe(for userID: String) async throws -> [FriendRequest]
// FriendRequest where senderID == userID AND status == "pending"

// --- Chups ---
func toggleChup(workoutID: String, userID: String, username: String) async throws -> Bool
// If chup exists, delete it (return false). If not, create it (return true).

func fetchChups(for workoutID: String) async throws -> (count: Int, currentUserChupped: Bool)

func fetchChupUsers(for workoutID: String) async throws -> [String]
// Returns list of usernames who chupped

// --- Comments ---
func postComment(workoutID: String, userID: String, username: String, text: String) async throws -> WorkoutComment

func fetchComments(for workoutID: String) async throws -> [WorkoutComment]
// Sorted by timestamp ascending

func toggleCommentHeart(commentID: String, userID: String) async throws -> Bool

func fetchCommentHeartCount(commentID: String) async throws -> Int

// --- Friend Workouts for Dashboard ---
func fetchFriendsFeedWorkouts(for userID: String, limit: Int) async throws -> [SharedWorkout]
// 1. Get all accepted friends
// 2. Query SharedWorkout for each friend
// 3. Sort by date descending, then username alphabetically
// 4. Return up to `limit` most recent (3 per friend, then merged & sorted)

// --- Friendship Status (for profile page gating) ---
func checkFriendship(currentUserID: String, otherUserID: String) async throws -> Bool
// Query FriendRequest where (senderID, receiverID) match in either direction AND status == "accepted"

func hasPendingRequest(from senderID: String, to receiverID: String) async throws -> Bool
// Query FriendRequest where senderID == senderID AND receiverID == receiverID AND status == "pending"
```

### 1C. Local Data Structs

Create a new file `Models/SocialModels.swift` with lightweight structs for the new data:

```swift
struct ChupInfo {
    let count: Int
    let currentUserChupped: Bool
}

struct CommentInfo: Identifiable {
    let id: String
    let userID: String
    let username: String
    let text: String
    let timestamp: Date
    var heartCount: Int
    var currentUserHearted: Bool
}

struct FriendProfile: Identifiable {
    let id: String // userID
    let username: String
    let displayName: String
    // Optional: profileImageURL if you add avatars later
}
```

---

## Phase 2: Profile Page — Friends List & Requests

### 2A. Update `ProfileView.swift`

Currently shows user info and workout count. Add:

1. **"X Friends" tappable row** below workout count
   - Fetch count from `SocialService.fetchAcceptedFriends()`
   - `NavigationLink` to new `FriendsListView`

```swift
// In ProfileView body, after workout count:
NavigationLink(destination: FriendsListView()) {
    HStack {
        Image(systemName: "person.2.fill")
        Text("\(friendCount) Friends")
            .font(.headline)
        Spacer()
        Image(systemName: "chevron.right")
    }
}
.onAppear { Task { friendCount = try await socialService.fetchAcceptedFriends(for: userID).count } }
```

### 2B. Create `Views/FriendsListView.swift`

New view with three sections:

```
FriendsListView
├── Section: "Friend Requests" (if any pending TO you)
│   └── For each: FriendRequestCard (existing component, accept/reject)
├── Section: "Sent Requests" (if any pending FROM you)
│   └── For each: row showing username + "Pending" badge
└── Section: "Friends" (all accepted friends)
    └── For each: row with profile icon (tappable → FriendProfileView), username, display name
```

- Use `@State` arrays loaded on `.onAppear` via `SocialService`
- Pull-to-refresh support
- Empty states for each section

### 2C. Reuse `FriendRequestCard.swift`

The existing `FriendRequestCard` component already handles accept/reject. Reuse it in the "Friend Requests" section of `FriendsListView`.

---

## Phase 3: Clickable Profile Icons → Friend Profile Page

### 3A. Create `Views/FriendProfileView.swift`

A new view that takes a `userID` and `username` as parameters. **This view has two modes depending on friendship status:**

#### Mode 1: Friend Profile (you are friends)
Shows full workout history:

```swift
struct FriendProfileView: View {
    let userID: String
    let username: String
    let displayName: String
    
    @State private var workouts: [SharedWorkout] = []
    @State private var isFriend: Bool = false
    @State private var friendCount: Int = 0
    @State private var isLoading = true
    @State private var friendRequestSent = false
    
    var body: some View {
        ScrollView {
            // Header: profile icon (large), display name, username, "X Friends"
            
            if isFriend {
                // Full workout list (same layout as LogView but for SharedWorkouts)
                LazyVStack(spacing: 12) {
                    ForEach(workouts) { workout in
                        WorkoutFeedCard(workout: workout, showProfileHeader: false)
                    }
                }
            } else {
                // Private profile state (see Mode 2 below)
                PrivateProfilePlaceholder(
                    friendRequestSent: $friendRequestSent,
                    onSendRequest: { sendFriendRequest() }
                )
            }
        }
        .navigationTitle(username)
        .onAppear { loadProfileAndCheckFriendship() }
    }
}
```

#### Mode 2: Non-Friend / Private Profile (you are NOT friends)

This is shown when you tap on a profile icon of someone you're not friends with — most commonly from the **Comments section**, where non-friends may have commented on a mutual friend's workout.

**Layout:**
```
┌─────────────────────────────────────────────────┐
│                                                  │
│              [Large Profile Pic]                 │
│              Person's Name                       │
│              @username                           │
│              X Friends                           │
│                                                  │
│         ┌──────────────────────────┐             │
│         │  🔒 Private Profile      │             │
│         │                          │             │
│         │  Send a friend request   │             │
│         │  to see their workouts   │             │
│         │                          │             │
│         │  [Add Friend]            │             │ ← Button, or "Request Sent ✓" if already sent
│         └──────────────────────────┘             │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Behavior:**
- Same header as the full profile: profile pic, display name, username, "X Friends" count
- No workouts are shown — replaced with a centered private profile message
- "Add Friend" button sends a friend request via `SocialService.sendFriendRequest()`
- After tapping, button changes to "Request Sent ✓" (disabled state) and stores `friendRequestSent = true`
- If a friend request is already pending (you already sent one), show "Request Sent ✓" immediately on load
- Light haptic on successful friend request send

**Check friendship status on appear:**
```swift
enum ProfileRelationship {
    case friends
    case notFriends
    case requestSentByMe    // I sent them a request, waiting for their approval
    case requestSentToMe    // They sent me a request, I can accept/decline
}

func loadProfileAndCheckFriendship() async {
    // 1. Fetch this user's friend count for the header
    friendCount = try await socialService.fetchAcceptedFriends(for: userID).count
    
    // 2. Determine relationship
    if try await socialService.checkFriendship(currentUserID: myUserID, otherUserID: userID) {
        relationship = .friends
        workouts = try await socialService.fetchSharedWorkouts(for: userID)
    } else if try await socialService.hasPendingRequest(from: myUserID, to: userID) {
        relationship = .requestSentByMe  // Show "Request Sent ✓" (disabled)
    } else if try await socialService.hasPendingRequest(from: userID, to: myUserID) {
        relationship = .requestSentToMe  // Show "Accept Request" / "Decline" buttons
    } else {
        relationship = .notFriends  // Show "Add Friend" button
    }
}
```

**Private Profile button states based on relationship:**
- `.notFriends` → "Add Friend" button (tapping sends request, changes to `.requestSentByMe`)
- `.requestSentByMe` → "Request Sent ✓" (disabled/grayed out)
- `.requestSentToMe` → "Accept Request" + "Decline" buttons (accepting changes to `.friends` and loads workouts)
- `.friends` → N/A (full profile shown instead)
```

- Fetch workouts via `SocialService` querying `SharedWorkout` where `userID == friendUserID`
- Sort chronologically (newest first)

### 3B. Make Profile Icons Tappable Everywhere

**UNIVERSAL RULE: Every tappable profile icon or username in the entire app navigates to `FriendProfileView`, which automatically checks friendship status and renders the appropriate mode.** There is no separate "friend profile" vs "non-friend profile" view — it is always `FriendProfileView` with built-in gating:

- **If you ARE friends** → Mode 1: full profile with workout history (see 3A above)
- **If you are NOT friends** → Mode 2: private profile with header, lock icon, and "Add Friend" button (see 3A above)
- **If you have a pending request to them** → Mode 2, but "Add Friend" is replaced with "Request Sent ✓" (disabled)
- **If they have a pending request to you** → Mode 2, but "Add Friend" is replaced with "Accept Request" / "Decline" buttons

This applies in ALL of the following contexts — no exceptions:

| Context | Where profile icons appear |
|---------|---------------------------|
| **Dashboard feed** | Profile pic/name on each friend's workout card |
| **Log tab** | Profile pic/name on your own workout cards (links to your own profile) |
| **Comments section** | Profile pic/username on each comment row (may be non-friends) |
| **Friends tab search results** | Profile pic/username in `UserSearchResultRow` (typically non-friends) |
| **Friends list** (from Profile) | Profile pic/username for each accepted friend |
| **Pending friend requests** | Profile pic/username on `FriendRequestCard` (incoming — not yet friends) |
| **Sent friend requests** | Profile pic/username on sent request rows (not yet friends) |
| **Friend profile page** | "X Friends" count could eventually link to their friends list (future) |

Update these components to wrap profile icons/names in `NavigationLink(destination: FriendProfileView(...))`:
- `WorkoutFeedCard.swift` (new) → wrap profile area
- `UserSearchResultRow.swift` → wrap profile icon and username
- `FriendRequestCard.swift` → wrap profile icon and username
- `CommentRow.swift` (new) → wrap profile icon and username
- `FriendsListView.swift` (new) → wrap each friend row's profile icon
- Sent request rows in `FriendsListView` → wrap profile icon

---

## Phase 4: Redesigned Workout Feed Card

### 4A. Create `Views/Components/WorkoutFeedCard.swift`

This is the unified card used both in the Dashboard feed AND the Log tab.

**Layout spec:**

```
┌─────────────────────────────────────────────────┐
│ [Profile Pic]  Person's Name                    │
│                Feb 12, 2026                     │
│                                                 │
│ 3x500m/3:00r  [UT2 zone tag]                   │  (bold name + color-coded zone pill)
│                                                 │
│ Workout: 3x500m/3:00r          Rate: 28        │
│ Avg Split: 1:30.5              HR: 155          │  (or blank if no HR)
│                                                 │
│ [👍 Chup]  10 people gave a Chup    [💬 Comment]│
│                                                 │
│   "Great workout!" — @john        (1 comment)   │  (preview of latest comment, tappable)
└─────────────────────────────────────────────────┘
```

**Props:**
```swift
struct WorkoutFeedCard: View {
    let workout: SharedWorkout  // or a unified WorkoutDisplayData protocol/struct
    let showProfileHeader: Bool // false when on someone's profile page
    let currentUserID: String
    
    @State private var chupInfo: ChupInfo = .init(count: 0, currentUserChupped: false)
    @State private var latestComment: CommentInfo? = nil
    @State private var commentCount: Int = 0
    @State private var showComments = false
    @State private var isChupAnimating = false
    @State private var isBigChup = false
}
```

### 4B. Chup (Like) Button Behavior

```swift
// Tap: toggle chup
Button {
    Task {
        let result = try await socialService.toggleChup(...)
        chupInfo.currentUserChupped = result
        chupInfo.count += result ? 1 : -1
        if result {
            // Haptic: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            HapticService.shared.lightImpact()
            withAnimation(.spring(response: 0.3)) { isChupAnimating = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isChupAnimating = false }
        }
    }
} label: {
    HStack(spacing: 4) {
        Image(systemName: chupInfo.currentUserChupped ? "hand.thumbsup.fill" : "hand.thumbsup")
            .foregroundColor(chupInfo.currentUserChupped ? .blue : .gray)
            .scaleEffect(isChupAnimating ? 1.3 : 1.0)
        Text("Chup")
    }
}

// Long press (1.0s) → Big Chup
.simultaneousGesture(
    LongPressGesture(minimumDuration: 1.0)
        .onEnded { _ in
            isBigChup = true
            // Gold color, larger animation, stronger haptic
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Additional heavy impact
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            // 1-second animation: big gold thumbs up
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { ... }
        }
)
```

**Big Chup animation:**
- Overlay a large gold `hand.thumbsup.fill` that scales up from 1.0 → 2.0 and fades out over 1 second
- Text "BIG Chup!" appears briefly
- Heavier haptic vibration pattern

**Chup count text:**
- `"\(chupInfo.count) people gave a Chup"` (or `"1 person gave a Chup"` for singular)

### 4C. Comment Button & Preview

```swift
// Right-aligned on same row as Chup button
HStack {
    // Chup button + count (left)
    Spacer()
    // Comment button (right)
    Button {
        showComments = true
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "bubble.right")
            Text("\(commentCount)")
        }
    }
}

// Below: show 1 comment preview if exists
if let comment = latestComment {
    Button { showComments = true } label: {
        HStack {
            Text("\"\(comment.text)\"").lineLimit(1)
            Text("— @\(comment.username)").foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

// Navigation to comments
.fullScreenCover(isPresented: $showComments) {  // or .sheet or NavigationLink
    CommentsView(workout: workout, currentUserID: currentUserID)
}
```

### 4D. Create `Views/CommentsView.swift`

Full-screen comments view:

```
┌─────────────────────────────────────────────────┐
│ ← Comments                                      │
│                                                  │
│ 3x500m/3:00r — @username                        │
│ Feb 12, 2026  ·  Avg Split: 1:30.5              │
│                                                  │
│ [👍 Chup]  10 people gave a Chup                │
│                                                  │
│ ─────────────────────────────────────            │
│                                                  │
│ [pic] @john  ·  2h ago                    [♡]   │
│       Great workout!                             │
│                                                  │
│ [pic] @sarah  ·  1h ago                   [♡]   │
│       That split is insane 🔥                    │
│                                                  │
│ ...scrollable...                                 │
│                                                  │
│ ┌──────────────────────────────────┐  [Send]    │
│ │ Add a comment...                 │             │
│ └──────────────────────────────────┘             │
└─────────────────────────────────────────────────┘
```

**Features:**
- Workout header with name, poster, date, avg split
- Chup button (same behavior as feed card)
- Scrollable list of all comments (oldest first)
- Each comment: profile pic (tappable → `FriendProfileView`), username, relative timestamp, heart button with count
- Text field at bottom with send button
- Heart button on each comment: `toggleCommentHeart()`, with light haptic

**Important: Non-friend profile tapping from comments.**
Since comments are visible to all friends of the workout poster, a user may see comments from people they are NOT friends with. When tapping on a non-friend's profile icon in the comments section, the app navigates to `FriendProfileView` which automatically detects the friendship status and renders the **Private Profile** variant. See Phase 3A, Mode 2 for full details and the universal rule below.

```swift
struct CommentsView: View {
    let workout: SharedWorkout
    let currentUserID: String
    
    @State private var comments: [CommentInfo] = []
    @State private var newCommentText = ""
    @State private var chupInfo: ChupInfo = ...
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                // Workout header
                // Chup row
                Divider()
                // Comments list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment, onHeart: { toggleHeart(comment) })
                        }
                    }
                }
                // Input bar
                HStack {
                    TextField("Add a comment...", text: $newCommentText)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") { postComment() }
                        .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back") { dismiss() } } }
        }
    }
}
```

---

## Phase 5: Move Friends Feed to Dashboard

### 5A. Update `DashboardView.swift`

Currently shows: weekly meters chart (zone-stacked bars) + goal progress widget.

**Add below existing content:**

```swift
// After goal progress widget:
Section {
    Text("Friends Activity")
        .font(.headline)
    
    if friendWorkouts.isEmpty {
        Text("No recent friend activity")
            .foregroundColor(.secondary)
    } else {
        LazyVStack(spacing: 16) {
            ForEach(friendWorkouts) { workout in
                WorkoutFeedCard(workout: workout, showProfileHeader: true, currentUserID: currentUserID)
            }
        }
    }
}

@State private var friendWorkouts: [SharedWorkout] = []

func loadFriendsFeed() async {
    // Fetch all accepted friends
    // For each friend, get their 3 most recent SharedWorkouts
    // Merge all results
    // Sort: primary = date descending, secondary = username alphabetical ascending
    friendWorkouts = try await socialService.fetchFriendsFeedWorkouts(for: userID, limit: nil)
}
```

**Sorting logic (in SocialService):**
```swift
// For each friend, fetch their 3 most recent workouts
// Combine all into one array
// Sort by:
//   1. Date (newest first)
//   2. If same date, alphabetical by username (A-Z)
results.sort { a, b in
    if a.date != b.date { return a.date > b.date }
    return a.username < b.username
}
```

### 5B. Update `FriendsView.swift`

Remove the activity feed section from FriendsView. Keep:
- User search functionality
- Friend request management (or just link to FriendsListView from Profile)

The FriendsView tab can either:
- **Option A:** Become primarily a search/discovery tab (search users, send requests)
- **Option B:** Be removed entirely, with search moved to Profile > Friends List

**Recommended: Option A** — Keep the Friends tab but simplify it to just search + pending requests quick-access. The feed lives on Dashboard now.

### 5C. Update Log Tab to Use WorkoutFeedCard

Update `LogView.swift` to render the user's own workouts using the same `WorkoutFeedCard` component:

```swift
// In LogView, replace current workout list rows with:
ForEach(workouts) { workout in
    WorkoutFeedCard(
        workout: workout.asSharedWorkout(), // adapter or protocol
        showProfileHeader: true, // show your own name/pic
        currentUserID: currentUserID
    )
}
```

You may need a protocol or adapter to unify `Workout` (SwiftData local) and `SharedWorkout` (CloudKit) into a common display format:

```swift
protocol WorkoutDisplayable {
    var displayName: String { get }
    var displayUsername: String { get }
    var displayDate: Date { get }
    var workoutName: String { get }
    var averageSplit: String { get }
    var averageRate: String { get }
    var heartRate: String? { get }
    var intensityZone: IntensityZone? { get }
    var workoutID: String { get }
    var userID: String { get }
}
```

Make both `Workout` and `SharedWorkout` conform to this protocol.

---

## Phase 6: Haptic & Animation Details

### 6A. Update `HapticService.swift`

Add methods for Chup interactions:

```swift
extension HapticService {
    func chupFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    func bigChupFeedback() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
        // Slight delay then another impact for "double tap" feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            heavy.impactOccurred(intensity: 1.0)
        }
    }
    
    func commentHeartFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
```

### 6B. Big Chup Animation Overlay

```swift
struct BigChupOverlay: View {
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            VStack {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.yellow)
                    .shadow(color: .orange, radius: 10)
                Text("BIG Chup!")
                    .font(.title.bold())
                    .foregroundColor(.yellow)
            }
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { isShowing = false }
                }
            }
        }
    }
}
```

---

## Phase 7: Zone Tag Color Coding

Ensure `IntensityZone` has associated colors (may already exist):

```swift
extension IntensityZone {
    var color: Color {
        switch self {
        case .ut2: return .green
        case .ut1: return .blue
        case .at:  return .orange
        case .max: return .red
        }
    }
    
    var label: String {
        switch self {
        case .ut2: return "UT2"
        case .ut1: return "UT1"
        case .at:  return "AT"
        case .max: return "Max"
        }
    }
}

// In WorkoutFeedCard, the zone pill:
Text(zone.label)
    .font(.caption.bold())
    .padding(.horizontal, 8)
    .padding(.vertical, 2)
    .background(zone.color.opacity(0.2))
    .foregroundColor(zone.color)
    .clipShape(Capsule())
```

---

## Execution Order (Recommended)

| Step | Task | Dependencies |
|------|------|-------------|
| 1 | Add `SocialModels.swift` (Chup, Comment structs) | None |
| 2 | Add CloudKit record types + SocialService methods for chups & comments | Step 1 |
| 3 | Create `WorkoutDisplayable` protocol, conform `Workout` and `SharedWorkout` | None |
| 4 | Create `WorkoutFeedCard.swift` (new unified card component) | Steps 1-3 |
| 5 | Create `CommentsView.swift` | Steps 2, 4 |
| 6 | Create `FriendProfileView.swift` | Steps 3, 4 |
| 7 | Create `FriendsListView.swift` | Step 2 |
| 8 | Update `ProfileView.swift` (add friends count + link) | Step 7 |
| 9 | Update `DashboardView.swift` (add friends feed) | Steps 2, 4 |
| 10 | Update `LogView.swift` (use WorkoutFeedCard) | Steps 3, 4 |
| 11 | Simplify `FriendsView.swift` (remove feed, keep search) | Step 9 |
| 12 | Update `HapticService.swift` (chup haptics) | None |
| 13 | Make profile icons tappable everywhere | Step 6 |
| 14 | Polish: Big Chup animation, zone colors, empty states | Steps 4, 12 |

---

## New Files to Create

| File | Purpose |
|------|---------|
| `Models/SocialModels.swift` | ChupInfo, CommentInfo, FriendProfile structs |
| `Models/WorkoutDisplayable.swift` | Protocol unifying Workout & SharedWorkout for cards |
| `Views/FriendsListView.swift` | Friends list + requests (from Profile) |
| `Views/FriendProfileView.swift` | Friend's profile with their workout history |
| `Views/CommentsView.swift` | Full comments screen for a workout |
| `Views/Components/WorkoutFeedCard.swift` | Unified workout card (feed + log) |
| `Views/Components/CommentRow.swift` | Single comment row with heart button |
| `Views/Components/BigChupOverlay.swift` | Big Chup animation overlay |
| `Views/Components/ZoneTag.swift` | Reusable intensity zone color pill |
| `Views/Components/PrivateProfilePlaceholder.swift` | Lock icon, "Private Profile" message, and "Add Friend" button shown on non-friend profiles |

## Files to Modify

| File | Changes |
|------|---------|
| `Services/SocialService.swift` | Add chup, comment, friends list, dashboard feed methods |
| `Services/HapticService.swift` | Add chup and comment haptic methods |
| `Views/ProfileView.swift` | Add "X Friends" tappable row |
| `Views/DashboardView.swift` | Add friends activity feed below existing content |
| `Views/LogView.swift` | Replace workout rows with WorkoutFeedCard |
| `Views/FriendsView.swift` | Remove activity feed, simplify to search + requests |
| `Views/Components/FriendActivityCard.swift` | Deprecate or remove (replaced by WorkoutFeedCard) |
| `Views/Components/UserSearchResultRow.swift` | Make profile icon tappable |
| `Views/Components/FriendRequestCard.swift` | Make profile icon tappable |
| `Models/IntensityZone.swift` | Add color and label properties (if not present) |
