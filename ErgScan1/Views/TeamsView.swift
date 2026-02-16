import SwiftUI

struct TeamsView: View {
    @Binding var showSearch: Bool
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var teamService: TeamService
    @EnvironmentObject var assignmentService: AssignmentService

    @State private var searchText = ""
    @State private var searchMode: SearchMode = .teams
    @State private var debounceTask: Task<Void, Never>?
    @State private var showCreateTeam = false
    @State private var showCreateAssignment = false
    @State private var showScanForRower = false
    @State private var selectedAssignmentTab: AssignmentTab = .toDo
    @State private var selectedWorkout: SocialService.SharedWorkoutResult?

    enum SearchMode: String, CaseIterable {
        case teams = "Teams"
        case users = "Users"
    }

    enum AssignmentTab {
        case toDo
        case completed
    }

    private var hasUsername: Bool {
        currentUser?.username != nil && !(currentUser?.username?.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !hasUsername {
                        usernameGate
                    } else {
                        searchSection
                        if !searchText.isEmpty {
                            searchResultsSection
                        } else {
                            teamContentSection
                            friendsSection
                        }
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Teams")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateTeam = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!hasUsername)
                }
            }
            .refreshable {
                await teamService.loadMyTeams(forceRefresh: true)
                await teamService.loadMyPendingRequests()
                if let teamID = teamService.selectedTeamID {
                    await teamService.loadTeamActivity(teamID: teamID, forceRefresh: true)
                    await teamService.loadRoster(teamID: teamID)
                    await assignmentService.loadAssignments(teamID: teamID)
                    await assignmentService.loadMySubmissions(teamID: teamID)
                }
                await socialService.loadPendingRequests()
                await socialService.loadFriends(forceRefresh: true)
            }
            .task {
                if hasUsername {
                    await socialService.loadPendingRequests()
                    await socialService.loadFriends()
                    if let teamID = teamService.selectedTeamID {
                        await teamService.loadTeamActivity(teamID: teamID)
                        await assignmentService.loadAssignments(teamID: teamID)
                        await assignmentService.loadMySubmissions(teamID: teamID)
                    }
                }
            }
            .sheet(isPresented: $showCreateTeam) {
                NavigationStack {
                    CreateTeamSheet(onCreated: {})
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cancel") { showCreateTeam = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showCreateAssignment) {
                if let teamID = teamService.selectedTeamID {
                    CreateAssignmentSheet(teamID: teamID) {
                        // Reload assignments after creation
                        Task {
                            await assignmentService.loadAssignments(teamID: teamID)
                        }
                    }
                }
            }
            .sheet(isPresented: $showScanForRower) {
                if let teamID = teamService.selectedTeamID {
                    ScanForRowerSheet(teamID: teamID)
                }
            }
            .alert("Error", isPresented: .constant(socialService.errorMessage != nil)) {
                Button("OK") { socialService.errorMessage = nil }
            } message: {
                Text(socialService.errorMessage ?? "")
            }
            .navigationDestination(item: $selectedWorkout) { workout in
                UnifiedWorkoutDetailView(
                    sharedWorkout: workout,
                    currentUserID: currentUser?.appleUserID ?? ""
                )
            }
        }
    }

    // MARK: - Username Gate

    private var usernameGate: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Set a username to connect with teams")
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
    }

    // MARK: - Search

    private var searchSection: some View {
        VStack(spacing: 8) {
            // Segmented picker for search mode
            Picker("Search", selection: $searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField(
                    searchMode == .teams ? "Search teams by name" : "Search users by username",
                    text: $searchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        if !Task.isCancelled && !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                            if searchMode == .teams {
                                await teamService.searchTeams(query: newValue)
                            } else {
                                await socialService.searchUsers(query: newValue)
                            }
                        } else if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                            await MainActor.run {
                                teamService.teamSearchResults = []
                                socialService.searchResults = []
                            }
                        }
                    }
                }
                .onChange(of: searchMode) { _, _ in
                    // Re-search when mode changes
                    if !searchText.isEmpty {
                        debounceTask?.cancel()
                        debounceTask = Task {
                            if searchMode == .teams {
                                socialService.searchResults = []
                                await teamService.searchTeams(query: searchText)
                            } else {
                                teamService.teamSearchResults = []
                                await socialService.searchUsers(query: searchText)
                            }
                        }
                    }
                }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        teamService.teamSearchResults = []
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
        }
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if searchMode == .teams {
                teamSearchResults
            } else {
                userSearchResults
            }
        }
    }

    private var teamSearchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if teamService.teamSearchResults.isEmpty && !teamService.isLoading {
                Text("No teams found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } else {
                Text("Teams")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(teamService.teamSearchResults) { team in
                    teamSearchRow(team)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func teamSearchRow(_ team: TeamInfo) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                )

            Text(team.name)
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            if teamService.myTeams.contains(where: { $0.id == team.id }) {
                Text("Joined")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if teamService.myPendingTeamRequests.contains(where: { $0.teamID == team.id }) {
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Button {
                    Task {
                        try? await teamService.requestToJoinTeam(
                            teamID: team.id,
                            roles: currentUser?.role ?? "rower"
                        )
                    }
                } label: {
                    Text("Join")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var userSearchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if socialService.searchResults.isEmpty && !socialService.isLoading {
                Text("No users found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } else {
                Text("Users")
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
    }

    // MARK: - Team Content

    private var teamContentSection: some View {
        VStack(spacing: 16) {
            if teamService.myTeams.isEmpty {
                noTeamsView
            } else {
                // Team selector (if multiple teams)
                if teamService.myTeams.count > 1 {
                    teamSelector
                }

                // Selected team content
                if let selectedID = teamService.selectedTeamID,
                   let selectedTeam = teamService.myTeams.first(where: { $0.id == selectedID }) {
                    selectedTeamView(team: selectedTeam, teamID: selectedID)
                }
            }
        }
    }

    private var noTeamsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Teams Yet")
                .font(.headline)

            Text("Create a team or search for one to join")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button { showCreateTeam = true } label: {
                    Label("Create", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }

            // Show pending requests if any
            if !teamService.myPendingTeamRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pending Requests")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(teamService.myPendingTeamRequests.count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)

                    ForEach(teamService.myPendingTeamRequests) { membership in
                        HStack {
                            Text(membership.teamID)
                                .font(.caption)
                            Spacer()
                            Text("Pending Approval")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
        }
        .padding(.vertical, 20)
    }

    private var teamSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(teamService.myTeams) { team in
                    Button {
                        teamService.selectedTeamID = team.id
                        Task {
                            await teamService.loadTeamActivity(teamID: team.id)
                            await teamService.loadRoster(teamID: team.id)
                        }
                    } label: {
                        Text(team.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(teamService.selectedTeamID == team.id ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(teamService.selectedTeamID == team.id ? Color.blue : Color(.secondarySystemBackground))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func selectedTeamView(team: TeamInfo, teamID: String) -> some View {
        VStack(spacing: 16) {
            // Team header
            TeamHeaderView(team: team, memberCount: teamService.selectedTeamRoster.count)

            // Action buttons
            VStack(spacing: 8) {
                NavigationLink(destination: RosterView(teamID: teamID)) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.blue)
                        Text("Show Roster")
                            .font(.subheadline)
                            .fontWeight(.semibold)
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

                // Admin: manage requests
                if teamService.isAdmin(teamID: teamID) {
                    NavigationLink(destination: TeamAdminView(teamID: teamID)) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(.orange)
                            Text("Manage Join Requests")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            if !teamService.pendingJoinRequests.isEmpty {
                                Text("\(teamService.pendingJoinRequests.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
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
                }

                // Coach: assign workout
                if teamService.hasRole(.coach, teamID: teamID) {
                    Button {
                        showCreateAssignment = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Assign Workout")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)
                }

                // Coxswain: scan for rowers
                if teamService.hasRole(.coxswain, teamID: teamID) {
                    Button {
                        showScanForRower = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.purple)
                            Text("Enter Team Scores")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal)
                }
            }

            // Assigned Workouts (if user is coach or rower)
            assignedWorkoutsSection(teamID: teamID)

            // Team feed
            teamFeedSection
        }
    }

    // MARK: - Assigned Workouts Section

    @ViewBuilder
    private func assignedWorkoutsSection(teamID: String) -> some View {
        if !assignmentService.myAssignments.isEmpty || teamService.hasRole(.coach, teamID: teamID) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Assigned Workouts")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)

                // Tab selector: To Do / Completed
                Picker("Assignment Filter", selection: $selectedAssignmentTab) {
                    Text("To Do").tag(AssignmentTab.toDo)
                    Text("Completed").tag(AssignmentTab.completed)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedAssignmentTab == .toDo {
                    // To Do: assignments not yet submitted
                    let pendingAssignments = assignmentService.myAssignments.filter { assignment in
                        !assignmentService.hasSubmitted(assignmentID: assignment.id)
                    }

                    if pendingAssignments.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("All caught up!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(pendingAssignments) { assignment in
                            NavigationLink(destination: AssignmentDetailView(assignment: assignment, teamID: teamID)) {
                                assignmentRow(assignment: assignment, hasSubmitted: false)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                } else {
                    // Completed: assignments that have been submitted
                    let completedAssignments = assignmentService.myAssignments.filter { assignment in
                        assignmentService.hasSubmitted(assignmentID: assignment.id)
                    }

                    if completedAssignments.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No completed assignments")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(completedAssignments) { assignment in
                            NavigationLink(destination: AssignmentDetailView(assignment: assignment, teamID: teamID)) {
                                assignmentRow(assignment: assignment, hasSubmitted: true)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.top)
        }
    }

    @ViewBuilder
    private func assignmentRow(assignment: AssignedWorkoutInfo, hasSubmitted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hasSubmitted ? "checkmark.circle.fill" : "clock.fill")
                .font(.title2)
                .foregroundColor(hasSubmitted ? .green : assignment.isPast ? .red : .blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.workoutName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if hasSubmitted {
                    Text("Completed")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if assignment.isPast {
                    Text("Overdue")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if assignment.daysUntilDue == 0 {
                    Text("Due today")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Due in \(assignment.daysUntilDue) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Team Feed

    private var teamFeedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Team Feed")
                .font(.headline)
                .padding(.horizontal)

            if teamService.teamActivity.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No team workouts yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(teamService.teamActivity) { workout in
                    WorkoutFeedCard(workout: workout, showProfileHeader: true, currentUserID: currentUser?.appleUserID ?? "")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedWorkout = workout
                        }
                        .padding(.horizontal)
                }
            }
        }
        .padding(.top)
    }

    // MARK: - Friends Section (preserved from FriendsView)

    private var friendsSection: some View {
        VStack(spacing: 16) {
            // Divider between teams and friends
            if !teamService.myTeams.isEmpty {
                Divider()
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Pending friend requests
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
                                Task { await socialService.acceptRequest(request) }
                            },
                            onReject: {
                                Task { await socialService.rejectRequest(request) }
                            }
                        )
                        .padding(.horizontal)
                    }
                }
            }

            // Friends list
            if !socialService.friends.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Friends")
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
            } else if searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Search for users above to connect")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }
}
