import SwiftUI
import SwiftData

struct ComparisonDetailView: View {
    let image: BenchmarkImage

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Accuracy summary
                if let parsedTable = decodedParsedTable,
                   let groundTruth = image.workout {
                    accuracySummarySection

                    Divider()

                    // Metadata comparison
                    metadataComparisonSection(parsed: parsedTable, groundTruth: groundTruth)

                    Divider()

                    // Averages row comparison
                    averagesComparisonSection(parsed: parsedTable, groundTruth: groundTruth)

                    Divider()

                    // Data rows comparison
                    rowsComparisonSection(parsed: parsedTable, groundTruth: groundTruth)
                } else {
                    noDataView
                }
            }
            .padding()
        }
        .navigationTitle("Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Decoded Data

    private var decodedParsedTable: RecognizedTable? {
        guard let data = image.parsedTable else { return nil }
        return try? JSONDecoder().decode(RecognizedTable.self, from: data)
    }

    // MARK: - Accuracy Summary

    private var accuracySummarySection: some View {
        VStack(spacing: 8) {
            if let accuracy = image.accuracyScore {
                HStack {
                    Image(systemName: accuracy >= 0.9 ? "checkmark.circle.fill" : accuracy >= 0.7 ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(accuracyColor(accuracy))

                    VStack(alignment: .leading) {
                        Text("\(Int(accuracy * 100))%")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(accuracyColor(accuracy))

                        Text("Accuracy")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }

            if let lastTested = image.lastTestedDate {
                Text("Last tested: \(lastTested, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Metadata Comparison

    private func metadataComparisonSection(parsed: RecognizedTable, groundTruth: BenchmarkWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Metadata")
                .font(.headline)
                .foregroundColor(.primary)

            ComparisonRow(
                label: "Workout Type",
                groundTruth: groundTruth.workoutType,
                parsed: parsed.workoutType
            )

            ComparisonRow(
                label: "Description",
                groundTruth: groundTruth.workoutDescription,
                parsed: parsed.description
            )

            ComparisonRow(
                label: "Total Time",
                groundTruth: groundTruth.totalTime,
                parsed: parsed.totalTime
            )

            ComparisonRow(
                label: "Total Distance",
                groundTruth: groundTruth.totalDistance != nil ? "\(groundTruth.totalDistance!)m" : nil,
                parsed: parsed.totalDistance != nil ? "\(parsed.totalDistance!)m" : nil
            )

            if let gtReps = groundTruth.reps {
                ComparisonRow(
                    label: "Reps",
                    groundTruth: "\(gtReps)",
                    parsed: parsed.reps != nil ? "\(parsed.reps!)" : nil
                )
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Averages Row Comparison

    private func averagesComparisonSection(parsed: RecognizedTable, groundTruth: BenchmarkWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Averages Row")
                .font(.headline)
                .foregroundColor(.primary)

            // Extract ground truth averages (orderIndex = 0)
            let gtAverages = groundTruth.intervals.first(where: { $0.orderIndex == 0 })

            if let parsedAvg = parsed.averages {
                ComparisonRow(
                    label: "Time",
                    groundTruth: gtAverages?.time,
                    parsed: parsedAvg.time?.text
                )

                ComparisonRow(
                    label: "Meters",
                    groundTruth: gtAverages?.meters.map { String($0) },
                    parsed: parsedAvg.meters?.text
                )

                ComparisonRow(
                    label: "Split",
                    groundTruth: gtAverages?.splitPer500m,
                    parsed: parsedAvg.splitPer500m?.text
                )

                ComparisonRow(
                    label: "Rate",
                    groundTruth: gtAverages?.strokeRate.map { String($0) },
                    parsed: parsedAvg.strokeRate?.text
                )

                ComparisonRow(
                    label: "Heart Rate",
                    groundTruth: gtAverages?.heartRate.map { String($0) },
                    parsed: parsedAvg.heartRate?.text
                )
            } else {
                Text("No averages row detected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Data Rows Comparison

    private func rowsComparisonSection(parsed: RecognizedTable, groundTruth: BenchmarkWorkout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interval Data")
                .font(.headline)
                .foregroundColor(.primary)

            // Filter out averages row (orderIndex = 0), only show data rows
            let gtIntervals = groundTruth.intervals
                .filter { $0.orderIndex >= 1 }
                .sorted(by: { $0.orderIndex < $1.orderIndex })

            ForEach(Array(gtIntervals.enumerated()), id: \.offset) { index, gtInterval in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interval \(index + 1)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    if index < parsed.rows.count {
                        let parsedRow = parsed.rows[index]

                        ComparisonRow(
                            label: "Time",
                            groundTruth: gtInterval.time,
                            parsed: parsedRow.time?.text
                        )

                        ComparisonRow(
                            label: "Meters",
                            groundTruth: gtInterval.meters != nil ? String(gtInterval.meters!) : nil,
                            parsed: parsedRow.meters?.text
                        )

                        ComparisonRow(
                            label: "Split",
                            groundTruth: gtInterval.splitPer500m,
                            parsed: parsedRow.splitPer500m?.text
                        )

                        ComparisonRow(
                            label: "Rate",
                            groundTruth: gtInterval.strokeRate != nil ? String(gtInterval.strokeRate!) : nil,
                            parsed: parsedRow.strokeRate?.text
                        )

                        ComparisonRow(
                            label: "Heart Rate",
                            groundTruth: gtInterval.heartRate != nil ? String(gtInterval.heartRate!) : nil,
                            parsed: parsedRow.heartRate?.text
                        )
                    } else {
                        Text("Row not detected in parsed table")
                            .font(.caption)
                            .foregroundColor(.red)
                            .italic()
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }

            // Show extra parsed rows that don't have ground truth
            if parsed.rows.count > gtIntervals.count {
                ForEach(gtIntervals.count..<parsed.rows.count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Extra Row \(index + 1)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)

                        Text("This row was detected but has no ground truth")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()

                        let parsedRow = parsed.rows[index]
                        if let time = parsedRow.time?.text {
                            Text("Time: \(time)")
                                .font(.caption)
                        }
                        if let meters = parsedRow.meters?.text {
                            Text("Meters: \(meters)")
                                .font(.caption)
                        }
                        if let split = parsedRow.splitPer500m?.text {
                            Text("Split: \(split)")
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - No Data View

    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Test Results")
                .font(.headline)
                .foregroundColor(.primary)

            Text("This image hasn't been tested yet. Run a full retest first to generate OCR results.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helper Functions

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.9 { return .green }
        if accuracy >= 0.7 { return .orange }
        return .red
    }
}

// MARK: - Comparison Row Component

struct ComparisonRow: View {
    let label: String
    let groundTruth: String?
    let parsed: String?
    var note: String? = nil

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ground Truth")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(groundTruth ?? "—")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parsed")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(parsed ?? "—")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Match indicator
                    matchIndicator
                }

                if let note = note {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    private var matchIndicator: some View {
        Group {
            if groundTruth == nil && parsed == nil {
                Image(systemName: "minus.circle")
                    .foregroundColor(.gray)
            } else if groundTruth == nil || parsed == nil {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.orange)
            } else if groundTruth == parsed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.title3)
    }
}
