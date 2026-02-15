import SwiftUI

struct JoinTeamSheet: View {
    let roles: Set<UserRole>
    let onJoined: () -> Void

    @EnvironmentObject var teamService: TeamService
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var requestSentTeamIDs: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search teams by name", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        debounceTask?.cancel()
                        debounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            if !Task.isCancelled && !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                await teamService.searchTeams(query: newValue)
                            } else if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                await MainActor.run {
                                    teamService.teamSearchResults = []
                                }
                            }
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        teamService.teamSearchResults = []
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

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // Results
            if teamService.isLoading {
                ProgressView()
                    .padding(.top, 40)
                Spacer()
            } else if teamService.teamSearchResults.isEmpty && !searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No teams found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                Spacer()
            } else if teamService.teamSearchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Search for a team to join")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(teamService.teamSearchResults) { team in
                            teamRow(team)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Find a Team")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func teamRow(_ team: TeamInfo) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer()

            if requestSentTeamIDs.contains(team.id) {
                Text("Pending")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            } else if teamService.myTeams.contains(where: { $0.id == team.id }) {
                Text("Joined")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Button {
                    requestJoin(team: team)
                } label: {
                    Text("Join")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func requestJoin(team: TeamInfo) {
        errorMessage = nil
        Task {
            do {
                try await teamService.requestToJoinTeam(teamID: team.id, roles: UserRole.toCSV(roles))
                await MainActor.run {
                    requestSentTeamIDs.insert(team.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
