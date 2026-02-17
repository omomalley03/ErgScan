//
//  ProfileView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var teamService: TeamService
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Binding var showSearch: Bool
    @State private var showSettings = false
    @State private var friendCount: Int = 0

    private var workoutCount: Int {
        guard let currentUser = currentUser else { return 0 }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID && $0.scannedForUserID == nil }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)

                        if let user = currentUser {
                            Text(user.fullName ?? "User")
                                .font(.title2)
                                .fontWeight(.bold)

                            // Username
                            if let username = user.username, !username.isEmpty {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            } else {
                                Button {
                                    showSettings = true
                                } label: {
                                    Text("Set up your username")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }

                            if let email = user.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 20)

                    // Quick Stats
                    HStack(spacing: 20) {
                        ProfileStatBox(label: "Workouts", value: "\(workoutCount)")
                        // ProfileStatBox(label: "This Week", value: "0")
                        // ProfileStatBox(label: "Total Time", value: "0h")
                    }
                    .padding(.horizontal)

                    // Power Curve Link
                    NavigationLink(destination: PowerCurveView()) {
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundColor(.blue)
                            Text("Power Curve")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                    // Friends Link
                    NavigationLink(destination: FriendsListView()) {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.blue)
                            Text("\(friendCount) Friends")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                    // Teams Link
                    NavigationLink(destination: MyTeamsListView()) {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.blue)
                            Text("\(teamService.myTeams.count) Teams")
                                .font(.headline)

                            if !teamService.myPendingTeamRequests.isEmpty {
                                Text("\(teamService.myPendingTeamRequests.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                    // Settings Button
                    Button {
                        showSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("Settings")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.bottom, 80)
            }
            .navigationTitle("Profile")
            .task {
                friendCount = socialService.friends.count
                if socialService.friends.isEmpty {
                    await socialService.loadFriends()
                    friendCount = socialService.friends.count
                }
            }
            .refreshable {
                await socialService.loadFriends()
                friendCount = socialService.friends.count
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showSettings = false
                                }
                            }
                        }
                }
            }
        }
    }
}

private struct ProfileStatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
