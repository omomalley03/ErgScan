import SwiftUI
import SwiftData

/// Detail view showing individual workout data
struct WorkoutDetailView: View {

    @Bindable var workout: Workout
    @State private var showingEditSheet = false

    var body: some View {
        List {
            // Header section
            Section("Workout Info") {
                LabeledContent("Type", value: workout.workoutType)

                LabeledContent("Category") {
                    Text(workout.category == .interval ? "INTERVAL" : "SINGLE")
                        .font(.caption)
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

                LabeledContent("Date") {
                    Text(workout.date, style: .date)
                }

                LabeledContent("Total Time", value: workout.totalTime)

                LabeledContent("OCR Confidence") {
                    HStack {
                        Text(String(format: "%.0f%%", workout.ocrConfidence * 100))
                        Image(systemName: confidenceIcon)
                            .foregroundColor(confidenceColor)
                    }
                }

                if workout.wasManuallyEdited {
                    LabeledContent("Status") {
                        Label("Manually Edited", systemImage: "pencil")
                            .foregroundColor(.orange)
                    }
                }
            }

            // Intervals/Splits section
            Section(workout.category == .interval ? "Intervals" : "Splits") {
                ForEach(sortedIntervals) { interval in
                    IntervalRow(
                        interval: interval,
                        isInterval: workout.category == .interval
                    )
                }
            }
        }
        .navigationTitle(workout.workoutType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                EditWorkoutView(workout: workout)
            }
        }
    }

    // MARK: - Computed Properties

    private var sortedIntervals: [Interval] {
        (workout.intervals ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

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

// MARK: - Interval Row

struct IntervalRow: View {

    let interval: Interval
    let isInterval: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isInterval ? "Interval #\(interval.orderIndex + 1)" : "Split #\(interval.orderIndex + 1)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Time:")
                        .foregroundColor(.secondary)
                    Text(interval.time)
                    confidenceBadge(interval.timeConfidence)
                }

                GridRow {
                    Text("Meters:")
                        .foregroundColor(.secondary)
                    Text(interval.meters)
                    confidenceBadge(interval.metersConfidence)
                }

                GridRow {
                    Text("Split (/500m):")
                        .foregroundColor(.secondary)
                    Text(interval.splitPer500m)
                    confidenceBadge(interval.splitConfidence)
                }

                GridRow {
                    Text("Rate (s/m):")
                        .foregroundColor(.secondary)
                    Text(interval.strokeRate)
                    confidenceBadge(interval.rateConfidence)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: Double) -> some View {
        if confidence > 0 {
            Text(String(format: "%.0f%%", confidence * 100))
                .font(.caption2)
                .foregroundColor(confidenceBadgeColor(confidence))
        }
    }

    private func confidenceBadgeColor(_ confidence: Double) -> Color {
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

    let interval1 = Interval(
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

    if workout.intervals == nil { workout.intervals = [] }
    workout.intervals?.append(interval1)
    container.mainContext.insert(workout)

    return NavigationStack {
        WorkoutDetailView(workout: workout)
    }
    .modelContainer(container)
}
