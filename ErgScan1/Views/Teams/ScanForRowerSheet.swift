import SwiftUI

struct ScanForRowerSheet: View {
    let teamID: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var teamService: TeamService
    @State private var roster: [TeamMembershipInfo] = []
    @State private var isLoading = true
    @State private var selectedMember: TeamMembershipInfo?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if roster.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No team members found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text("Select a rower to scan their workout")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Section("Team Members") {
                            ForEach(roster) { member in
                                Button {
                                    selectedMember = member
                                    showScanner = true
                                } label: {
                                    rosterRow(member)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Enter Team Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadRoster()
            }
            .sheet(isPresented: $showScanner) {
                if let member = selectedMember {
                    NavigationStack {
                        ScannerView(
                            cameraService: CameraService(),
                            scanOnBehalfOf: member.userID,
                            scanOnBehalfOfUsername: member.username
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rosterRow(_ member: TeamMembershipInfo) -> some View {
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
                Text("@\(member.username)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(member.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show role tags
                HStack(spacing: 4) {
                    ForEach(member.roleList) { role in
                        Text(role.displayName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadRoster() async {
        isLoading = true
        await teamService.loadRoster(teamID: teamID)
        roster = teamService.selectedTeamRoster
        isLoading = false
    }
}
