import SwiftUI
import SwiftData

struct AssignmentDetailView: View {
    let assignment: AssignedWorkoutInfo
    let teamID: String

    @Environment(\.currentUser) private var currentUser
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var assignmentService: AssignmentService
    @EnvironmentObject var teamService: TeamService
    @EnvironmentObject var socialService: SocialService
    @State private var showScanner = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedWorkout: SocialService.SharedWorkoutResult?
    @State private var selectedLocalWorkout: Workout?

    private var hasSubmitted: Bool {
        assignmentService.hasSubmitted(assignmentID: assignment.id)
    }

    private var isCoach: Bool {
        teamService.hasRole(.coach, teamID: teamID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Assignment header
                VStack(alignment: .leading, spacing: 8) {
                    Text(assignment.workoutName)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 12) {
                        Label {
                            Text("Assigned by @\(assignment.assignerUsername)")
                                .font(.subheadline)
                        } icon: {
                            Image(systemName: "person.fill")
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding()

                Divider()

                // Description
                if !assignment.description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instructions")
                            .font(.headline)

                        Text(assignment.description)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding()
                }

                // Dates
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timeline")
                        .font(.headline)

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                        Text("Opens:")
                        Spacer()
                        Text(assignment.startDate, style: .date)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(assignment.isPast ? .red : .blue)
                        Text("Due:")
                        Spacer()
                        Text(assignment.endDate, style: .date)
                            .foregroundColor(assignment.isPast ? .red : .primary)
                    }

                    if assignment.daysUntilDue > 0 && !assignment.isPast {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("\(assignment.daysUntilDue) days remaining")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if assignment.isPast && !hasSubmitted {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Overdue")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Divider()

                // Submission status
                if hasSubmitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Submitted!")
                            .font(.title3)
                            .fontWeight(.bold)

                        if let submission = assignmentService.mySubmissions.first(where: { $0.assignmentID == assignment.id }) {
                            VStack(spacing: 6) {
                                Text("Submitted on \(submission.submittedAt, style: .date)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let coxUsername = submission.submittedByCoxUsername {
                                    Text("Submitted by @\(coxUsername)")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }

                                Button {
                                    Task {
                                        await loadAndShowWorkout(submission: submission)
                                    }
                                } label: {
                                    HStack(spacing: 16) {
                                        VStack {
                                            Text(submission.totalTime)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text("Time")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        VStack {
                                            Text("\(submission.totalDistance)m")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text("Distance")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        VStack {
                                            Text(submission.averageSplit)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text("Avg Split")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .foregroundColor(.primary)
                                    .padding()
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if isCoach {
                    // Coach view: show submission tracker
                    NavigationLink(destination: SubmissionTrackerView(assignment: assignment, teamID: teamID)) {
                        HStack {
                            Image(systemName: "list.bullet.clipboard")
                                .foregroundColor(.blue)
                            Text("View Submissions")
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
                } else {
                    // Athlete view: submit workout button
                    VStack(spacing: 12) {
                        Button {
                            showScanner = true
                        } label: {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Scan Workout")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                    }
                }

                Spacer()
            }
        }
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ScannerView(
                    cameraService: CameraService(),
                    assignmentID: assignment.id,
                    assignmentTeamID: teamID
                )
            }
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
