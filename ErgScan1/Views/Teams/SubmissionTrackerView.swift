import SwiftUI
import SwiftData

struct SubmissionTrackerView: View {
    let assignment: AssignedWorkoutInfo
    let teamID: String

    @EnvironmentObject var assignmentService: AssignmentService
    @EnvironmentObject var teamService: TeamService
    @EnvironmentObject var socialService: SocialService
    @Environment(\.currentUser) private var currentUser
    @Environment(\.modelContext) private var modelContext
    @State private var trackerEntries: [SubmissionTrackerEntry] = []
    @State private var isLoading = true
    @State private var selectedWorkout: SocialService.SharedWorkoutResult?
    @State private var selectedLocalWorkout: Workout?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trackerEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No team members")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Text("Assignment: \(assignment.workoutName)")
                            .font(.headline)

                        HStack {
                            Text("Submitted:")
                            Spacer()
                            Text("\(submittedCount) / \(trackerEntries.count)")
                                .fontWeight(.semibold)
                                .foregroundColor(submittedCount == trackerEntries.count ? .green : .orange)
                        }
                    }

                    Section("Team Members") {
                        ForEach(trackerEntries) { entry in
                            memberRow(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("Submissions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .navigationDestination(item: $selectedWorkout) { workout in
            UnifiedWorkoutDetailView(
                sharedWorkout: workout,
                currentUserID: currentUser?.appleUserID ?? ""
            )
        }
        .navigationDestination(item: $selectedLocalWorkout) { workout in
            UnifiedWorkoutDetailView(
                localWorkout: workout,
                currentUserID: currentUser?.appleUserID ?? ""
            )
        }
    }

    private var submittedCount: Int {
        trackerEntries.filter { $0.hasSubmitted }.count
    }

    @ViewBuilder
    private func memberRow(_ entry: SubmissionTrackerEntry) -> some View {
        Button {
            if let submission = entry.submission {
                Task {
                    await loadAndShowWorkout(submission: submission)
                }
            }
        } label: {
            HStack(spacing: 12) {
            Circle()
                .fill(entry.hasSubmitted ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: entry.hasSubmitted ? "checkmark" : "xmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(entry.hasSubmitted ? .green : .red)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("@\(entry.username)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(entry.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let submittedText = entry.submittedAtText {
                    Text("Submitted: \(submittedText)")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if let coxUsername = entry.submission?.submittedByCoxUsername {
                    Text("Submitted by @\(coxUsername)")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
            }

            Spacer()

            if let submission = entry.submission {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(submission.averageSplit)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(submission.totalDistance)m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .background(entry.hasSubmitted ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
        .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!entry.hasSubmitted)
    }

    private func loadData() async {
        isLoading = true

        // Load roster and submissions
        await teamService.loadRoster(teamID: teamID)
        await assignmentService.loadSubmissions(assignmentID: assignment.id, teamID: teamID)

        // Build tracker entries
        let roster = teamService.selectedTeamRoster
        let entries = assignmentService.buildSubmissionTracker(
            assignmentID: assignment.id,
            roster: roster
        )

        await MainActor.run {
            trackerEntries = entries.sorted { entry1, entry2 in
                // Sort: submitted first, then by username
                if entry1.hasSubmitted != entry2.hasSubmitted {
                    return entry1.hasSubmitted
                }
                return entry1.username < entry2.username
            }
            isLoading = false
        }
    }

    private func loadAndShowWorkout(submission: WorkoutSubmissionInfo) async {
        // If viewing own submission, show local workout with full details
        if submission.submitterID == currentUser?.appleUserID {
            // Try to fetch local workout
            let workoutUUID = UUID(uuidString: submission.workoutRecordID)
            if let workoutUUID = workoutUUID {
                let descriptor = FetchDescriptor<Workout>(
                    predicate: #Predicate { workout in
                        workout.id == workoutUUID
                    }
                )
                if let localWorkout = try? modelContext.fetch(descriptor).first {
                    await MainActor.run {
                        selectedLocalWorkout = localWorkout
                    }
                    return
                }
            }
        }

        // Otherwise, fetch shared workout from CloudKit
        guard let sharedWorkoutID = submission.sharedWorkoutRecordID else {
            print("No shared workout ID for submission")
            return
        }

        if let sharedWorkout = await socialService.fetchSharedWorkout(recordID: sharedWorkoutID) {
            await MainActor.run {
                selectedWorkout = sharedWorkout
            }
        }
    }
}
