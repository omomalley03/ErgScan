import SwiftUI
import SwiftData

struct BenchmarkResultsView: View {
    @Query private var benchmarks: [BenchmarkWorkout]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if allImages.isEmpty {
                    emptyStateView
                } else if testedImages.isEmpty {
                    noTestsView
                } else {
                    // Overall stats
                    overallStatsSection

                    Divider()

                    // Field-level breakdown with bar charts
                    fieldBreakdownSection

                    Divider()

                    // Worst performing images
                    worstPerformingSection

                    Divider()

                    // Debug report button
                    debugReportSection
                }
            }
            .padding()
        }
        .navigationTitle("Results Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: BenchmarkReportView()) {
                    Label("Debug Report", systemImage: "doc.text")
                }
                .disabled(testedImages.isEmpty)
            }
        }
    }

    // MARK: - Computed Properties

    private var allImages: [BenchmarkImage] {
        benchmarks.flatMap { $0.images }
    }

    private var testedImages: [BenchmarkImage] {
        allImages.filter { $0.accuracyScore != nil }
    }

    private var overallAccuracy: Double {
        guard !testedImages.isEmpty else { return 0.0 }
        let total = testedImages.reduce(0.0) { $0 + ($1.accuracyScore ?? 0) }
        return total / Double(testedImages.count)
    }

    private var lastTestDate: Date? {
        testedImages.compactMap { $0.lastTestedDate }.max()
    }

    // MARK: - Overall Stats Section

    private var overallStatsSection: some View {
        VStack(spacing: 16) {
            // Main accuracy display
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall Accuracy")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("\(Int(overallAccuracy * 100))%")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(accuracyColor(overallAccuracy))
                }

                Spacer()

                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 12)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: overallAccuracy)
                        .stroke(accuracyColor(overallAccuracy), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(overallAccuracy * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Summary stats
            HStack(spacing: 20) {
                StatBox(
                    title: "Images Tested",
                    value: "\(testedImages.count) / \(allImages.count)",
                    icon: "photo.on.rectangle.angled"
                )

                StatBox(
                    title: "Benchmarks",
                    value: "\(benchmarks.count)",
                    icon: "chart.bar.doc.horizontal"
                )
            }

            if let lastTest = lastTestDate {
                Text("Last tested: \(lastTest, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Field Breakdown Section

    private var fieldBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Field-Level Accuracy")
                .font(.headline)
                .foregroundColor(.primary)

            let stats = calculateFieldStats()

            ForEach(stats, id: \.field) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stat.field)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(stat.matched)/\(stat.total)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("\(Int(stat.accuracy * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(accuracyColor(stat.accuracy))
                            .frame(width: 50, alignment: .trailing)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                                .cornerRadius(4)

                            Rectangle()
                                .fill(accuracyColor(stat.accuracy))
                                .frame(width: geometry.size.width * stat.accuracy, height: 8)
                                .cornerRadius(4)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Worst Performing Section

    private var worstPerformingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lowest Accuracy Images")
                .font(.headline)
                .foregroundColor(.primary)

            let worstImages = testedImages
                .sorted { ($0.accuracyScore ?? 1.0) < ($1.accuracyScore ?? 1.0) }
                .prefix(5)

            ForEach(Array(worstImages.enumerated()), id: \.offset) { index, image in
                NavigationLink(destination: ComparisonDetailView(image: image)) {
                    HStack {
                        // Rank
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(accuracyColor(image.accuracyScore ?? 0))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(image.angleDescription ?? "Unknown")
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            if let workout = image.workout {
                                Text(workout.workoutType ?? "Unknown workout")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Accuracy
                        Text("\(Int((image.accuracyScore ?? 0) * 100))%")
                            .font(.headline)
                            .foregroundColor(accuracyColor(image.accuracyScore ?? 0))

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Debug Report Section

    private var debugReportSection: some View {
        NavigationLink(destination: BenchmarkReportView()) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generate Debug Report")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Copy full details to Claude for analysis")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Empty/No Tests Views

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Benchmark Data")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Create benchmark datasets by scanning and saving workouts")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var noTestsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Test Results Yet")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Run 'Retest All' from the Benchmarks tab to generate accuracy statistics")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Field Statistics Calculation

    private func calculateFieldStats() -> [FieldStat] {
        var stats: [String: (matched: Int, total: Int)] = [:]

        for image in testedImages {
            guard let parsedData = image.parsedTable,
                  let parsedTable = try? JSONDecoder().decode(RecognizedTable.self, from: parsedData),
                  let workout = image.workout else {
                continue
            }

            // Metadata fields
            compareField("Workout Type", gt: workout.workoutType, parsed: parsedTable.workoutType, stats: &stats)
            compareField("Total Time", gt: workout.totalTime, parsed: parsedTable.totalTime, stats: &stats)
            compareField("Description", gt: workout.workoutDescription, parsed: parsedTable.description, stats: &stats)
            compareField("Total Distance",
                         gt: workout.totalDistance != nil ? "\(workout.totalDistance!)" : nil,
                         parsed: parsedTable.totalDistance != nil ? "\(parsedTable.totalDistance!)" : nil,
                         stats: &stats)

            // Interval fields
            let gtIntervals = workout.intervals.sorted(by: { $0.orderIndex < $1.orderIndex })
            for (index, gtInterval) in gtIntervals.enumerated() {
                guard index < parsedTable.rows.count else { continue }
                let parsedRow = parsedTable.rows[index]

                compareField("Time", gt: gtInterval.time, parsed: parsedRow.time?.text, stats: &stats)
                compareField("Meters",
                             gt: gtInterval.meters != nil ? String(gtInterval.meters!) : nil,
                             parsed: parsedRow.meters?.text,
                             stats: &stats)
                compareField("Split", gt: gtInterval.splitPer500m, parsed: parsedRow.splitPer500m?.text, stats: &stats)
                compareField("Stroke Rate",
                             gt: gtInterval.strokeRate != nil ? String(gtInterval.strokeRate!) : nil,
                             parsed: parsedRow.strokeRate?.text,
                             stats: &stats)
                compareField("Heart Rate",
                             gt: gtInterval.heartRate != nil ? String(gtInterval.heartRate!) : nil,
                             parsed: parsedRow.heartRate?.text,
                             stats: &stats)
            }
        }

        // Convert to array and sort by accuracy
        return stats.map { field, counts in
            FieldStat(
                field: field,
                matched: counts.matched,
                total: counts.total,
                accuracy: counts.total > 0 ? Double(counts.matched) / Double(counts.total) : 0.0
            )
        }.sorted { $0.accuracy < $1.accuracy }  // Show worst first
    }

    private func compareField(_ field: String, gt: String?, parsed: String?, stats: inout [String: (matched: Int, total: Int)]) {
        // Only compare if ground truth exists
        guard let groundTruth = gt else { return }

        if stats[field] == nil {
            stats[field] = (matched: 0, total: 0)
        }

        stats[field]!.total += 1

        if parsed == groundTruth {
            stats[field]!.matched += 1
        }
    }

    // MARK: - Helper Functions

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.9 { return .green }
        if accuracy >= 0.7 { return .orange }
        return .red
    }
}

// MARK: - Supporting Types

struct FieldStat {
    let field: String
    let matched: Int
    let total: Int
    let accuracy: Double
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)

            Text(value)
                .font(.headline)
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }
}
