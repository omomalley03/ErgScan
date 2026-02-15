import SwiftUI

struct MyTeamsListView: View {
    @EnvironmentObject var teamService: TeamService

    var body: some View {
        List {
            // Pending requests section
            if !teamService.myPendingTeamRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(teamService.myPendingTeamRequests) { membership in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "clock.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Team Request")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Awaiting approval")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            Text("Pending")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Your teams section
            Section("Your Teams") {
                if teamService.myTeams.isEmpty {
                    VStack(spacing: 8) {
                        Text("No teams yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(teamService.myTeams) { team in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "person.3.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                if teamService.isAdmin(teamID: team.id) {
                                    Text("Admin")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    Text("Member")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("My Teams")
        .task {
            await teamService.loadMyTeams()
            await teamService.loadMyPendingRequests()
        }
        .refreshable {
            await teamService.loadMyTeams()
            await teamService.loadMyPendingRequests()
        }
    }
}
