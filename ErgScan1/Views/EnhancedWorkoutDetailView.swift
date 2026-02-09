import SwiftUI

struct EnhancedWorkoutDetailView: View {
    let workout: Workout
    @State private var currentIntervalIndex = 0
    @State private var showSwipeHint = true
    @State private var showImageViewer = false
    @State private var showEditSheet = false

    var sortedIntervals: [Interval] {
        workout.intervals
            .filter { $0.orderIndex >= 1 }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    var averagesInterval: Interval? {
        workout.intervals.first(where: { $0.orderIndex == 0 })
    }

    var body: some View {
        content
            .navigationTitle(workout.workoutType)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showEditSheet = true
                    }
                }
            }
            .sheet(isPresented: $showImageViewer) {
                imageViewerSheet
            }
            .sheet(isPresented: $showEditSheet) {
                NavigationStack {
                    EditWorkoutView(workout: workout)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showSwipeHint = false
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                savedImageView

                if let averages = averagesInterval {
                    AveragesSummaryCard(interval: averages, category: workout.category)
                }

                intervalsContent
            }
            .padding()
        }
    }

    @ViewBuilder
    private var savedImageView: some View {
        if let imageData = workout.imageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .onTapGesture {
                    showImageViewer = true
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(8)
                }
        }
    }

    @ViewBuilder
    private var intervalsContent: some View {
        if workout.category == .interval && !sortedIntervals.isEmpty {
            intervalCardsView
            PageIndicator(currentPage: currentIntervalIndex, totalPages: sortedIntervals.count)
            swipeHintView
        } else if !sortedIntervals.isEmpty {
            SplitsListView(
                intervals: sortedIntervals,
                workoutType: workout.workoutType,
                fastestId: fastestInterval?.id,
                slowestId: slowestInterval?.id
            )
        }
    }

    private var intervalCardsView: some View {
        TabView(selection: $currentIntervalIndex) {
            ForEach(Array(sortedIntervals.enumerated()), id: \.element.id) { index, interval in
                IntervalCardView(
                    interval: interval,
                    number: index + 1,
                    total: sortedIntervals.count,
                    isFastest: interval.id == fastestInterval?.id,
                    isSlowest: interval.id == slowestInterval?.id
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 450)
        .onChange(of: currentIntervalIndex) { _, _ in
            HapticService.shared.lightImpact()
        }
    }

    @ViewBuilder
    private var swipeHintView: some View {
        if showSwipeHint && sortedIntervals.count > 1 {
            Text("← Swipe to navigate →")
                .font(.caption)
                .foregroundColor(.secondary)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var imageViewerSheet: some View {
        if let imageData = workout.imageData,
           let uiImage = UIImage(data: imageData) {
            FullScreenImageViewer(image: uiImage, workoutType: workout.workoutType)
        }
    }

    private var fastestInterval: Interval? {
        sortedIntervals.min { parseTime($0.time) < parseTime($1.time) }
    }

    private var slowestInterval: Interval? {
        sortedIntervals.max { parseTime($0.time) < parseTime($1.time) }
    }

    private func parseTime(_ timeString: String) -> Double {
        // Parse "4:02.1" to 242.1 seconds
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else {
            return 0
        }
        return minutes * 60 + seconds
    }
}

// MARK: - Supporting Components

struct AveragesSummaryCard: View {
    let interval: Interval
    let category: WorkoutCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUMMARY")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    DataRow(label: "Time", value: interval.time)
                    DataRow(label: "Distance", value: "\(interval.meters)m")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    DataRow(label: "Split", value: interval.splitPer500m)
                    DataRow(label: "Rate", value: "\(interval.strokeRate) s/m")
                    if let hr = interval.heartRate {
                        DataRow(label: "HR", value: "\(hr) bpm")
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }
}

struct DataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

struct IntervalCardView: View {
    let interval: Interval
    let number: Int
    let total: Int
    let isFastest: Bool
    let isSlowest: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("INTERVAL \(number) of \(total)")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                if isFastest {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.green)
                }
                if isSlowest {
                    Image(systemName: "tortoise.fill")
                        .foregroundColor(.red)
                }
            }

            Divider()

            // Data fields
            VStack(spacing: 16) {
                LargeDataField(label: "Time", value: interval.time)
                LargeDataField(label: "Distance", value: "\(interval.meters)m")
                LargeDataField(label: "Split", value: interval.splitPer500m, suffix: "/500m")
                LargeDataField(label: "Rate", value: interval.strokeRate, suffix: "s/m")

                if let hr = interval.heartRate {
                    LargeDataField(label: "Heart Rate", value: hr, suffix: "bpm")
                }
            }

            Spacer()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackgroundColor)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.horizontal)
    }

    private var cardBackgroundColor: Color {
        if isFastest {
            return Color.green.opacity(0.1)
        } else if isSlowest {
            return Color.red.opacity(0.1)
        } else {
            return Color(.systemBackground)
        }
    }

}

struct LargeDataField: View {
    let label: String
    let value: String
    let suffix: String?

    init(label: String, value: String, suffix: String? = nil) {
        self.label = label
        self.value = value
        self.suffix = suffix
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Spacer()

            HStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                if let suffix = suffix {
                    Text(suffix)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct SplitsListView: View {
    let intervals: [Interval]
    let workoutType: String
    let fastestId: UUID?
    let slowestId: UUID?

    private var isDistanceBased: Bool {
        // Check if workout type ends with "m" (e.g., "2000m", "5000m")
        workoutType.trimmingCharacters(in: .whitespaces).hasSuffix("m")
    }

    private var splitInterval: String {
        guard let firstInterval = intervals.first else {
            return "500m"  // Default fallback
        }

        if isDistanceBased {
            // Distance-based split (e.g., "400" -> "400m")
            if let metersValue = Int(firstInterval.meters.trimmingCharacters(in: .whitespaces)),
               metersValue > 0 {
                return "\(metersValue)m"
            }
            return "500m"  // Default distance split
        } else {
            // Time-based split (e.g., "6:00.0" -> "6:00")
            let timeValue = firstInterval.time.trimmingCharacters(in: .whitespaces)
            // Remove trailing .0 or decimal for cleaner display
            if let dotIndex = timeValue.firstIndex(of: ".") {
                return String(timeValue[..<dotIndex])
            }
            return timeValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SPLITS")// (\(splitInterval))")
                .font(.headline)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                ForEach(Array(intervals.enumerated()), id: \.element.id) { index, interval in
                    SplitRow(
                        interval: interval,
                        isDistanceBased: isDistanceBased,
                        isFastest: interval.id == fastestId,
                        isSlowest: interval.id == slowestId
                    )
                }
            }

            // Summary stats
            if let fastest = intervals.first(where: { $0.id == fastestId }),
               let slowest = intervals.first(where: { $0.id == slowestId }) {
                Divider()
                    .padding(.vertical, 8)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fastest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(fastest.splitPer500m)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Slowest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(slowest.splitPer500m)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }
}

struct SplitRow: View {
    let interval: Interval
    let isDistanceBased: Bool
    let isFastest: Bool
    let isSlowest: Bool

    private var splitLabel: String {
        if isDistanceBased {
            // Show distance (e.g., "400m", "800m")
            return interval.meters.trimmingCharacters(in: .whitespaces) + "m"
        } else {
            // Show time (e.g., "6:00", "12:00") - remove decimal
            let timeValue = interval.time.trimmingCharacters(in: .whitespaces)
            if let dotIndex = timeValue.firstIndex(of: ".") {
                return String(timeValue[..<dotIndex])
            }
            return timeValue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(splitLabel)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)

            Text(interval.splitPer500m)
                .font(.body)
                .fontWeight(isFastest || isSlowest ? .bold : .regular)
                .foregroundColor(isFastest ? .green : (isSlowest ? .red : .primary))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text("\(interval.strokeRate)s/m")
                .font(.body)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            if let hr = interval.heartRate {
                Text(hr)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackgroundColor)
        )
    }

    private var rowBackgroundColor: Color {
        if isFastest {
            return Color.green.opacity(0.1)
        } else if isSlowest {
            return Color.red.opacity(0.1)
        } else {
            return Color(.secondarySystemBackground)
        }
    }
}

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }
}
