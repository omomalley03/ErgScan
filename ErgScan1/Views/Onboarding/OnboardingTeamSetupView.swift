import SwiftUI

struct OnboardingTeamSetupView: View {
    let selectedRoles: Set<UserRole>
    let onComplete: () -> Void
    let onSkip: () -> Void

    @EnvironmentObject var teamService: TeamService
    @State private var showCreateTeam = false
    @State private var showJoinTeam = false
    @State private var weeklyGoal = ""
    @State private var showGoalInput = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Join or Create a Team")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 40)

            Text("Connect with your rowing club or teammates")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                // Join existing team
                Button { showJoinTeam = true } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                        Text("Find a Team to Join")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                // Create new team
                Button { showCreateTeam = true } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Create a Team")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Optional weekly mileage goal
            VStack(spacing: 8) {
                Button {
                    withAnimation { showGoalInput.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.blue)
                        Text("Set Weekly Mileage Goal")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: showGoalInput ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

                if showGoalInput {
                    HStack {
                        TextField("e.g. 50000", text: $weeklyGoal)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Text("meters")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal)

            Spacer()

            Button {
                onSkip()
            } label: {
                Text("Skip for Now")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showCreateTeam) {
            NavigationStack {
                CreateTeamSheet(onCreated: { onComplete() })
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { showCreateTeam = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showJoinTeam) {
            NavigationStack {
                JoinTeamSheet(roles: selectedRoles, onJoined: { onComplete() })
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { showJoinTeam = false }
                        }
                    }
            }
        }
    }
}
