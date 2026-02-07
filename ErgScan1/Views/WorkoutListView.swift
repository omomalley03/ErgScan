import SwiftUI
import SwiftData

/// List view showing all saved workouts
struct WorkoutListView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            if workouts.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(workouts) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            WorkoutRow(workout: workout)
                        }
                    }
                    .onDelete(perform: deleteWorkouts)
                }
                .navigationTitle("Workouts")
                .toolbar {
                    EditButton()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.rowing")
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

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(workouts[index])
        }
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {

    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Workout type
                Text(workout.workoutType)
                    .font(.headline)

                Spacer()

                // Category badge
                Text(workout.category == .interval ? "INTERVAL" : "SINGLE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            workout.category == .interval ? Color.blue : Color.green
                        )
                    )
            }

            HStack {
                // Date
                Text(workout.date, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // Total time
                Text(workout.totalTime)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                // Number of intervals/splits
                Label(
                    "\(workout.intervals.count) \(workout.category == .interval ? "intervals" : "splits")",
                    systemImage: "list.number"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                // Confidence indicator
                HStack(spacing: 4) {
                    Image(systemName: confidenceIcon)
                        .foregroundColor(confidenceColor)
                    Text(String(format: "%.0f%%", workout.ocrConfidence * 100))
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // Edited badge
                if workout.wasManuallyEdited {
                    Label("Edited", systemImage: "pencil")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed Properties

    private var confidenceIcon: String {
        if workout.ocrConfidence > 0.8 {
            return "checkmark.circle.fill"
        } else if workout.ocrConfidence > 0.5 {
            return "exclamationmark.circle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }

    private var confidenceColor: Color {
        if workout.ocrConfidence > 0.8 {
            return .green
        } else if workout.ocrConfidence > 0.5 {
            return .yellow
        } else {
            return .red
        }
    }
}

#Preview {
    WorkoutListView()
        .modelContainer(for: [Workout.self, Interval.self])
}
