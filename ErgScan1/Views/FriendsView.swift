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

                            TextField("Search by username or name to add", text: $searchText)
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

                                let friendIDs = Set(socialService.friends.map { $0.id })
                                ForEach(socialService.searchResults) { user in
                                    UserSearchResultRow(
                                        user: user,
                                        sentRequestIDs: socialService.sentRequestIDs,
                                        friendIDs: friendIDs,
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

                        // Friends quick-access
                        if !socialService.friends.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Your Friends")
                                        .font(.headline)
                                    Spacer()
                                    NavigationLink(destination: FriendsListView()) {
                                        Text("See All")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal)

                                ForEach(socialService.friends.prefix(5)) { friend in
                                    NavigationLink(destination: FriendProfileView(
                                        userID: friend.id,
                                        username: friend.username,
                                        displayName: friend.displayName
                                    )) {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(Color.blue.opacity(0.2))
                                                .frame(width: 36, height: 36)
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
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top)
                        } else if searchText.isEmpty && socialService.searchResults.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.2.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No friends yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Search for friends above to connect")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Friends")
            .refreshable {
                if hasUsername {
                    await socialService.loadPendingRequests()
                    await socialService.loadFriends()
                }
            }
            .onAppear {
                if hasUsername {
                    Task {
                        await socialService.loadPendingRequests()
                        await socialService.loadFriends()
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
