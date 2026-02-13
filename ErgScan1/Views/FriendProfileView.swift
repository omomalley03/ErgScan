import SwiftUI

struct FriendProfileView: View {
    let userID: String
    let username: String
    let displayName: String

    @EnvironmentObject var socialService: SocialService
    @Environment(\.currentUser) private var currentUser

    @State private var relationship: ProfileRelationship = .notFriends
    @State private var workouts: [SocialService.SharedWorkoutResult] = []
    @State private var friendCount: Int = 0
    @State private var isLoading = true
    @State private var selectedWorkout: SocialService.SharedWorkoutResult?

    private var myUserID: String {
        currentUser?.appleUserID ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile header
                VStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text(displayName.isEmpty ? username : displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(.blue)

                    Text("\(friendCount) Friends")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                if isLoading {
                    ProgressView()
                        .padding(.vertical, 40)
                } else if relationship == .friends {
                    // Full workout list
                    if workouts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "figure.rowing")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No workouts shared yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(workouts) { workout in
                                WorkoutFeedCard(
                                    workout: workout,
                                    showProfileHeader: false,
                                    currentUserID: myUserID
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedWorkout = workout
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    // Private profile
                    PrivateProfilePlaceholder(
                        relationship: relationship,
                        onSendRequest: { sendFriendRequest() },
                        onAcceptRequest: { acceptRequest() },
                        onDeclineRequest: { declineRequest() }
                    )
                }
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedWorkout) { workout in
            UnifiedWorkoutDetailView(sharedWorkout: workout, currentUserID: myUserID)
        }
        .task {
            await loadProfileData()
        }
    }

    // MARK: - Data Loading

    private func loadProfileData() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch friend count
        friendCount = await socialService.fetchFriendCount(for: userID)

        // Check relationship
        let isFriend = await socialService.checkFriendship(currentUserID: myUserID, otherUserID: userID)
        if isFriend {
            relationship = .friends
            workouts = await socialService.fetchSharedWorkouts(for: userID)
        } else {
            let sentByMe = await socialService.hasPendingRequest(from: myUserID, to: userID)
            if sentByMe {
                relationship = .requestSentByMe
            } else {
                let sentToMe = await socialService.hasPendingRequest(from: userID, to: myUserID)
                if sentToMe {
                    relationship = .requestSentToMe
                } else {
                    relationship = .notFriends
                }
            }
        }
    }

    // MARK: - Actions

    private func sendFriendRequest() {
        Task {
            await socialService.sendFriendRequest(to: userID)
            relationship = .requestSentByMe
        }
    }

    private func acceptRequest() {
        Task {
            // Find the pending request from this user to accept it
            let pending = socialService.pendingRequests.first { $0.senderID == userID }
            if let request = pending {
                await socialService.acceptRequest(request)
            }
            await loadProfileData()
        }
    }

    private func declineRequest() {
        Task {
            let pending = socialService.pendingRequests.first { $0.senderID == userID }
            if let request = pending {
                await socialService.rejectRequest(request)
            }
            relationship = .notFriends
        }
    }
}
