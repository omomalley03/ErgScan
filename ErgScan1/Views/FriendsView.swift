//
//  FriendsView.swift
//  ErgScan1
//
//  Created by Claude on 2/11/26.
//

import SwiftUI

struct FriendsView: View {
    @Binding var showSearch: Bool
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService

    @State private var searchText = ""
    @State private var debounceTask: Task<Void, Never>?

    var hasUsername: Bool {
        currentUser?.username != nil && !(currentUser?.username?.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !hasUsername {
                        // Username gate
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            Text("Set a username to connect with friends")
                                .font(.headline)
                                .multilineTextAlignment(.center)

                            NavigationLink(destination: SettingsView()) {
                                Text("Go to Settings")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.vertical, 40)
                    } else {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)

                            TextField("Search by username or name", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: searchText) { _, newValue in
                                    debounceTask?.cancel()
                                    debounceTask = Task {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        if !Task.isCancelled && !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                            await socialService.searchUsers(query: newValue)
                                        } else if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                            await MainActor.run {
                                                socialService.searchResults = []
                                            }
                                        }
                                    }
                                }

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    socialService.searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .padding(.horizontal)

                        // Search results
                        if !socialService.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Search Results")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(socialService.searchResults) { user in
                                    UserSearchResultRow(
                                        user: user,
                                        sentRequestIDs: socialService.sentRequestIDs,
                                        onAddFriend: {
                                            Task {
                                                await socialService.sendFriendRequest(to: user.id)
                                            }
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Pending requests
                        if !socialService.pendingRequests.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Friend Requests")
                                        .font(.headline)

                                    Text("\(socialService.pendingRequests.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal)

                                ForEach(socialService.pendingRequests) { request in
                                    FriendRequestCard(
                                        request: request,
                                        onAccept: {
                                            Task {
                                                await socialService.acceptRequest(request)
                                            }
                                        },
                                        onReject: {
                                            Task {
                                                await socialService.rejectRequest(request)
                                            }
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Friend activity feed
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Activity")
                                .font(.headline)
                                .padding(.horizontal)

                            if socialService.friendActivity.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "figure.rowing")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)

                                    Text(socialService.friends.isEmpty ? "No friends yet" : "No recent activity")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    if socialService.friends.isEmpty {
                                        Text("Search for friends to see their workouts")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.vertical, 40)
                                .frame(maxWidth: .infinity)
                            } else {
                                ForEach(socialService.friendActivity) { workout in
                                    FriendActivityCard(workout: workout)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.top)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Friends")
            .refreshable {
                if hasUsername {
                    await socialService.loadPendingRequests()
                    await socialService.loadFriendActivity()
                }
            }
            .onAppear {
                if hasUsername {
                    Task {
                        await socialService.loadPendingRequests()
                        await socialService.loadFriendActivity()
                    }
                }
            }
            .alert("Error", isPresented: .constant(socialService.errorMessage != nil)) {
                Button("OK") {
                    socialService.errorMessage = nil
                }
            } message: {
                Text(socialService.errorMessage ?? "")
            }
        }
    }
}
