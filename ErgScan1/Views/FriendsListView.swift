import SwiftUI

struct FriendsListView: View {
    @EnvironmentObject var socialService: SocialService
    @Environment(\.currentUser) private var currentUser

    @State private var isLoading = true

    var body: some View {
        List {
            // Friend Requests section
            if !socialService.pendingRequests.isEmpty {
                Section("Friend Requests") {
                    ForEach(socialService.pendingRequests) { request in
                        NavigationLink(destination: FriendProfileView(
                            userID: request.senderID,
                            username: request.senderUsername,
                            displayName: request.senderDisplayName
                        )) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(request.senderUsername)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(request.senderDisplayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    Button {
                                        Task { await socialService.rejectRequest(request) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(Color.red)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task { await socialService.acceptRequest(request) }
                                    } label: {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .frame(width: 28, height: 28)
                                            .background(Color.green)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            // Sent Requests section
            if !socialService.sentRequestIDs.isEmpty {
                Section("Sent Requests") {
                    ForEach(Array(socialService.sentRequestIDs), id: \.self) { requestedUserID in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                )

                            Text(requestedUserID)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("Pending")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Friends section
            Section("Friends (\(socialService.friends.count))") {
                if socialService.friends.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No friends yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(socialService.friends) { friend in
                        NavigationLink(destination: FriendProfileView(
                            userID: friend.id,
                            username: friend.username,
                            displayName: friend.displayName
                        )) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(friend.username)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(friend.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await socialService.loadPendingRequests()
            await socialService.loadFriends()
        }
        .task {
            await socialService.loadPendingRequests()
            await socialService.loadFriends()
            isLoading = false
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }
}
