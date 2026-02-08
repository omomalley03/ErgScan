import SwiftUI

/// Displays parsed workout data with a summary card and scrollable rep/split list
struct WorkoutResultView: View {
    let table: RecognizedTable

    private var hasData: Bool {
        table.workoutType != nil || table.averages != nil || !table.rows.isEmpty
    }

    var body: some View {
        if hasData {
            ScrollView {
                VStack(spacing: 12) {
                    SummaryCardView(table: table)
                    RepSplitListView(table: table)
                }
                .padding()
            }
            .background(Color(.systemBackground))
        } else {
            Text("No parsed data")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        }
    }
}

// MARK: - Summary Card

private struct SummaryCardView: View {
    let table: RecognizedTable

    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: descriptor + badge
            HStack {
                Text(table.workoutType ?? "Unknown")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                if let category = table.category {
                    Text(category == .interval ? "INTERVALS" : "SINGLE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(category == .interval ? Color.blue : Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }

            // Interval detail
            if let reps = table.reps, let work = table.workPerRep, let rest = table.restPerRep {
                Text("\(reps) x \(work) / \(rest) rest")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Date
            if let date = table.date {
                Text(dateFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Summary stats
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    if let totalTime = table.totalTime {
                        StatRow(label: "Total Time", value: totalTime)
                    }
                    if let totalDist = table.totalDistance {
                        StatRow(label: "Total Meters", value: formatMeters(totalDist))
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    if let split = table.averages?.splitPer500m?.text {
                        StatRow(label: "Avg Split", value: "\(split) /500m")
                    }
                    if let rate = table.averages?.strokeRate?.text {
                        StatRow(label: "Avg S/M", value: rate)
                    }
                }
            }

            // Confidence
            Text("OCR Confidence: \(String(format: "%.0f%%", table.averageConfidence * 100))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatMeters(_ meters: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: meters)) ?? "\(meters)"
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Rep/Split List

private struct RepSplitListView: View {
    let table: RecognizedTable

    private var isInterval: Bool { table.category == .interval }
    private var fastestSplitIndex: Int? { findExtremeSplit(fastest: true) }
    private var slowestSplitIndex: Int? { findExtremeSplit(fastest: false) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                RepCardView(
                    row: row,
                    index: index,
                    label: isInterval ? "Rep" : "Split",
                    highlight: highlightColor(for: index)
                )
            }
        }
    }

    private func highlightColor(for index: Int) -> Color? {
        if table.rows.count < 2 { return nil }
        if index == fastestSplitIndex { return .green }
        if index == slowestSplitIndex { return .red }
        return nil
    }

    private func findExtremeSplit(fastest: Bool) -> Int? {
        guard table.rows.count >= 2 else { return nil }

        var bestIndex: Int? = nil
        var bestValue: Double? = nil

        for (i, row) in table.rows.enumerated() {
            guard let splitText = row.splitPer500m?.text else { continue }
            let seconds = splitToSeconds(splitText)
            guard seconds > 0 else { continue }

            if bestValue == nil ||
               (fastest && seconds < bestValue!) ||
               (!fastest && seconds > bestValue!) {
                bestValue = seconds
                bestIndex = i
            }
        }

        return bestIndex
    }

    private func splitToSeconds(_ text: String) -> Double {
        // Parse "1:59.6" → 119.6
        let parts = text.split(separator: ":")
        guard parts.count == 2 else { return 0 }
        guard let minutes = Double(parts[0]) else { return 0 }
        guard let seconds = Double(parts[1]) else { return 0 }
        return minutes * 60 + seconds
    }
}

private struct RepCardView: View {
    let row: TableRow
    let index: Int
    let label: String
    let highlight: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("\(label) \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let color = highlight {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
            }

            // Data grid
            HStack(spacing: 16) {
                if let time = row.time?.text {
                    DataCell(label: "Time", value: time)
                }
                if let meters = row.meters?.text {
                    DataCell(label: "Distance", value: "\(formatMeters(meters))m")
                }
                if let split = row.splitPer500m?.text {
                    DataCell(label: "Split", value: split)
                }
                if let rate = row.strokeRate?.text {
                    DataCell(label: "S/M", value: rate)
                }
                if let hr = row.heartRate?.text {
                    DataCell(label: "HR", value: hr)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(highlight ?? .clear, lineWidth: 2)
                )
        )
    }

    private func formatMeters(_ text: String) -> String {
        guard let val = Int(text) else { return text }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: val)) ?? text
    }
}

private struct DataCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

#Preview {
    WorkoutResultView(table: RecognizedTable())
}
