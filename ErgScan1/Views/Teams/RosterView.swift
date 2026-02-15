import SwiftUI

struct RosterView: View {
    let teamID: String
    @EnvironmentObject var teamService: TeamService
    @State private var roster: [TeamMembershipInfo] = []
    @State private var isLoading = true
    @State private var editingMember: TeamMembershipInfo?

    private var isAdmin: Bool {
        teamService.isAdmin(teamID: teamID)
    }

    // Members grouped by highest-privilege role (no duplicates)
    private var coaches: [TeamMembershipInfo] {
        roster.filter { $0.hasRole(.coach) }
    }

    private var coxswains: [TeamMembershipInfo] {
        roster.filter { $0.hasRole(.coxswain) && !$0.hasRole(.coach) }
    }

    private var rowers: [TeamMembershipInfo] {
        roster.filter { !$0.hasRole(.coach) && !$0.hasRole(.coxswain) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if roster.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No members yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !coaches.isEmpty {
                        Section("Coaches") {
                            ForEach(coaches) { member in
                                rosterRow(member)
                            }
                        }
                    }

                    if !coxswains.isEmpty {
                        Section("Coxswains") {
                            ForEach(coxswains) { member in
                                rosterRow(member)
                            }
                        }
                    }

                    if !rowers.isEmpty {
                        Section("Rowers") {
                            ForEach(rowers) { member in
                                rosterRow(member)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Roster")
        .task {
            await teamService.loadRoster(teamID: teamID)
            roster = teamService.selectedTeamRoster
            isLoading = false
        }
        .sheet(item: $editingMember) { member in
            NavigationStack {
                RoleEditorSheet(member: member, teamID: teamID) {
                    // Refresh roster after role change
                    Task {
                        await teamService.loadRoster(teamID: teamID)
                        roster = teamService.selectedTeamRoster
                    }
                }
                .environmentObject(teamService)
            }
        }
    }

    private func rosterRow(_ member: TeamMembershipInfo) -> some View {
        Button {
            if isAdmin {
                editingMember = member
            }
        } label: {
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
                    HStack(spacing: 6) {
                        Text("@\(member.username)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if member.membershipRole == "admin" {
                            Text("Admin")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    Text(member.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Role tags — show all roles
                HStack(spacing: 4) {
                    ForEach(member.roleList) { role in
                        Text(role.displayName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }
                }

                if isAdmin {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Role Editor Sheet (Admin only)

private struct RoleEditorSheet: View {
    let member: TeamMembershipInfo
    let teamID: String
    let onSaved: () -> Void

    @EnvironmentObject var teamService: TeamService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRoles: Set<UserRole> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            // Member info
            VStack(spacing: 8) {
                Text("@\(member.username)")
                    .font(.headline)
                Text(member.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top)

            Text("Assign Roles")
                .font(.title3)
                .fontWeight(.semibold)

            // Role toggles
            VStack(spacing: 10) {
                ForEach(UserRole.allCases) { role in
                    Button {
                        if selectedRoles.contains(role) {
                            selectedRoles.remove(role)
                        } else {
                            selectedRoles.insert(role)
                        }
                    } label: {
                        HStack {
                            Image(systemName: role.icon)
                                .font(.title3)
                                .foregroundColor(selectedRoles.contains(role) ? .white : .blue)
                                .frame(width: 40, height: 40)
                                .background(selectedRoles.contains(role) ? Color.blue : Color.blue.opacity(0.1))
                                .clipShape(Circle())

                            Text(role.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: selectedRoles.contains(role) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedRoles.contains(role) ? .blue : .secondary)
                                .font(.title3)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedRoles.contains(role) ? Color.blue : Color.clear, lineWidth: 2)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            Button {
                saveRoles()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .cornerRadius(14)
                } else {
                    Text("Save Roles")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(!selectedRoles.isEmpty ? Color.blue : Color.gray)
                        .cornerRadius(14)
                }
            }
            .disabled(selectedRoles.isEmpty || isSaving)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .navigationTitle("Edit Roles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            selectedRoles = Set(member.roleList)
        }
    }

    private func saveRoles() {
        isSaving = true
        errorMessage = nil
        let newRolesCSV = UserRole.toCSV(selectedRoles)

        Task {
            do {
                try await teamService.updateMemberRoles(
                    membershipRecordName: member.id,
                    newRoles: newRolesCSV,
                    teamID: teamID
                )
                await MainActor.run {
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
