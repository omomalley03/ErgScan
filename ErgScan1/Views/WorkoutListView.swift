import SwiftUI
import SwiftData

/// List view showing all saved workouts
struct WorkoutListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var teamService: TeamService
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]

    // Filter workouts by current user
    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID && $0.scannedForUserID == nil }
    }

    private var myUserID: String {
        currentUser?.appleUserID ?? ""
    }

    var body: some View {
        NavigationStack {
            if workouts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(workouts) { workout in
                            NavigationLink(destination: UnifiedWorkoutDetailView(
                                localWorkout: workout,
                                currentUserID: myUserID
                            )) {
                                LogWorkoutCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteWorkout(workout)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .navigationTitle("Workouts")
                .refreshable {
                    // Triggers SwiftData @Query refresh
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Workouts Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Use the Scanner tab to capture your first workout from the erg monitor")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Workouts")
    }

    // MARK: - Actions

    private func deleteWorkout(_ workout: Workout) {
        let workoutIDString = workout.id.uuidString
        Task {
            if let deletedID = await socialService.deleteSharedWorkout(
                localWorkoutID: workoutIDString,
                sharedWorkoutRecordID: workout.sharedWorkoutRecordID
            ) {
                await MainActor.run {
                    teamService.removeFromTeamActivity(workoutID: deletedID)
                }
            }
            await socialService.loadFriendActivity(forceRefresh: true)
            if let teamID = teamService.selectedTeamID {
                await teamService.loadTeamActivity(teamID: teamID, forceRefresh: true)
            }
        }
        modelContext.delete(workout)
    }
}
