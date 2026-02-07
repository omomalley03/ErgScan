import SwiftUI
import SwiftData

/// View for manually editing workout data
struct EditWorkoutView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var workout: Workout

    var body: some View {
        Form {
            // Workout info section
            Section("Workout Info") {
                TextField("Workout Type", text: $workout.workoutType)

                Picker("Category", selection: $workout.category) {
                    Text("Single Piece").tag(WorkoutCategory.single)
                    Text("Interval Piece").tag(WorkoutCategory.interval)
                }

                DatePicker("Date", selection: $workout.date, displayedComponents: .date)

                TextField("Total Time", text: $workout.totalTime)
            }

            // Intervals/Splits section
            Section(workout.category == .interval ? "Intervals" : "Splits") {
                ForEach(sortedIntervals) { interval in
                    IntervalEditSection(
                        interval: interval,
                        isInterval: workout.category == .interval
                    )
                }
            }
        }
        .navigationTitle("Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveChanges()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var sortedIntervals: [Interval] {
        workout.intervals.sorted { $0.orderIndex < $1.orderIndex }
    }

    // MARK: - Actions

    private func saveChanges() {
        workout.wasManuallyEdited = true
        workout.lastModifiedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving workout: \(error)")
        }
    }
}

// MARK: - Interval Edit Section

struct IntervalEditSection: View {

    @Bindable var interval: Interval
    let isInterval: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isInterval ? "Interval #\(interval.orderIndex + 1)" : "Split #\(interval.orderIndex + 1)")
                .font(.headline)

            // Time field
            HStack {
                Text("Time:")
                    .frame(width: 100, alignment: .leading)
                TextField("4:00.0", text: $interval.time)
                    .textFieldStyle(.roundedBorder)
                confidenceBadge(interval.timeConfidence)
            }

            // Meters field
            HStack {
                Text("Meters:")
                    .frame(width: 100, alignment: .leading)
                TextField("1179", text: $interval.meters)
                    .textFieldStyle(.roundedBorder)
                confidenceBadge(interval.metersConfidence)
            }

            // Split field
            HStack {
                Text("Split (/500m):")
                    .frame(width: 100, alignment: .leading)
                TextField("1:41.2", text: $interval.splitPer500m)
                    .textFieldStyle(.roundedBorder)
                confidenceBadge(interval.splitConfidence)
            }

            // Stroke rate field
            HStack {
                Text("Rate (s/m):")
                    .frame(width: 100, alignment: .leading)
                TextField("29", text: $interval.strokeRate)
                    .textFieldStyle(.roundedBorder)
                confidenceBadge(interval.rateConfidence)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: Double) -> some View {
        if confidence > 0 {
            HStack(spacing: 4) {
                Image(systemName: confidenceIcon(confidence))
                    .foregroundColor(confidenceColor(confidence))
                Text(String(format: "%.0f%%", confidence * 100))
                    .font(.caption)
            }
        }
    }

    private func confidenceIcon(_ confidence: Double) -> String {
        if confidence > 0.8 {
            return "checkmark.circle.fill"
        } else if confidence > 0.5 {
            return "exclamationmark.circle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.5 {
            return .yellow
        } else {
            return .red
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Workout.self, Interval.self, configurations: config)

    let workout = Workout(
        date: Date(),
        workoutType: "3x4:00/3:00r",
        category: .interval,
        totalTime: "21:00.3",
        ocrConfidence: 0.85
    )

    let interval = Interval(
        orderIndex: 0,
        time: "4:00.0",
        meters: "1179",
        splitPer500m: "1:41.2",
        strokeRate: "29",
        timeConfidence: 0.9,
        metersConfidence: 0.85,
        splitConfidence: 0.88,
        rateConfidence: 0.92
    )

    workout.intervals.append(interval)
    container.mainContext.insert(workout)

    return NavigationStack {
        EditWorkoutView(workout: workout)
    }
    .modelContainer(container)
}
