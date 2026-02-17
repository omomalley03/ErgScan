import SwiftUI
import SwiftData

struct PrivacySettingsView: View {
    @Environment(\.currentUser) private var currentUser
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var teamService: TeamService

    @State private var selectedPrivacy: WorkoutPrivacy = .friends
    @State private var selectedTeams: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        List {
            Section {
                Text("Choose who can see your workouts by default")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section("Default Privacy") {
                ForEach(WorkoutPrivacy.allCases) { privacy in
                    privacyButton(for: privacy)
                }
            }

            // Team selector if Team privacy is selected
            if selectedPrivacy == .team && !teamService.myTeams.isEmpty {
                Section("Select Teams") {
                    Text("Your workouts will be visible to these teams")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(teamService.myTeams), id: \.id) { team in
                        teamButton(for: team)
                    }
                }
            }

            Section {
                Button {
                    savePrivacySettings()
                } label: {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            Text("Save Settings")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
                .disabled(isSaving || (selectedPrivacy == .team && selectedTeams.isEmpty))
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentSettings()
            Task {
                await teamService.loadMyTeams()
            }
        }
    }

    @ViewBuilder
    private func privacyButton(for privacy: WorkoutPrivacy) -> some View {
        Button {
            selectedPrivacy = privacy
        } label: {
            HStack {
                Image(systemName: privacy.icon)
                    .font(.title3)
                    .foregroundColor(selectedPrivacy == privacy ? .white : .blue)
                    .frame(width: 40, height: 40)
                    .background(selectedPrivacy == privacy ? Color.blue : Color.blue.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(privacy.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(privacy.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if selectedPrivacy == privacy {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func teamButton(for team: TeamInfo) -> some View {
        Button {
            if selectedTeams.contains(team.id) {
                selectedTeams.remove(team.id)
            } else {
                selectedTeams.insert(team.id)
            }
        } label: {
            HStack {
                Text(team.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()

                if selectedTeams.contains(team.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func loadCurrentSettings() {
        guard let user = currentUser else { return }

        if let privacyString = user.defaultPrivacy {
            // Parse the privacy string
            if privacyString == "private" {
                selectedPrivacy = .privateOnly
            } else if WorkoutPrivacy.includesFriends(privacyString) && WorkoutPrivacy.includesTeam(privacyString) {
                // This screen supports a single default audience; prefer friends when both are present.
                selectedPrivacy = .friends
                selectedTeams = Set(WorkoutPrivacy.parseTeamIDs(from: privacyString))
            } else if WorkoutPrivacy.includesFriends(privacyString) {
                selectedPrivacy = .friends
            } else if WorkoutPrivacy.includesTeam(privacyString) {
                selectedPrivacy = .team
                // Parse team IDs if present
                selectedTeams = Set(WorkoutPrivacy.parseTeamIDs(from: privacyString))
            } else {
                selectedPrivacy = .friends
            }
        } else {
            selectedPrivacy = .friends
        }
    }

    private func savePrivacySettings() {
        guard let user = currentUser else { return }

        isSaving = true

        // Build privacy string
        let privacyString: String
        if selectedPrivacy == .team && !selectedTeams.isEmpty {
            privacyString = WorkoutPrivacy.teamPrivacy(teamIDs: Array(selectedTeams))
        } else {
            privacyString = selectedPrivacy.rawValue
        }

        // Update user model
        user.defaultPrivacy = privacyString

        // Save to database
        do {
            try modelContext.save()
            isSaving = false
        } catch {
            print("Failed to save privacy settings: \(error)")
            isSaving = false
        }
    }
}
