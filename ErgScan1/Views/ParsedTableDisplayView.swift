import SwiftUI

/// Displays parsed workout data in a structured JSON-like format
struct ParsedTableDisplayView: View {
    let table: RecognizedTable

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("{")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                // Workout type
                if let workoutType = table.workoutType {
                    HStack(spacing: 4) {
                        Text("  workoutType:")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("\"\(workoutType)\",")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Category
                if let category = table.category {
                    HStack(spacing: 4) {
                        Text("  category:")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("\"\(category.rawValue)\",")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Date
                if let date = table.date {
                    HStack(spacing: 4) {
                        Text("  date:")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("\"\(dateFormatter.string(from: date))\",")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Total time
                if let totalTime = table.totalTime {
                    HStack(spacing: 4) {
                        Text("  totalTime:")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.blue)
                        Text("\"\(totalTime)\",")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Averages
                if let averages = table.averages {
                    Text("  averages: {")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)

                    if let time = averages.time?.text {
                        Text("    time: \"\(time)\",")
                            .font(.system(.caption, design: .monospaced))
                    }
                    if let meters = averages.meters?.text {
                        Text("    meters: \"\(meters)\",")
                            .font(.system(.caption, design: .monospaced))
                    }
                    if let split = averages.splitPer500m?.text {
                        Text("    split: \"\(split)\",")
                            .font(.system(.caption, design: .monospaced))
                    }
                    if let rate = averages.strokeRate?.text {
                        Text("    rate: \"\(rate)\"")
                            .font(.system(.caption, design: .monospaced))
                    }

                    Text("  },")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                }

                // Intervals/splits
                let rowsLabel = table.category == .interval ? "intervals" : "splits"
                Text("  \(rowsLabel): [")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)

                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    Text("    {")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let time = row.time?.text {
                        Text("      time: \"\(time)\",")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    if let meters = row.meters?.text {
                        Text("      meters: \"\(meters)\",")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    if let split = row.splitPer500m?.text {
                        Text("      split: \"\(split)\",")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    if let rate = row.strokeRate?.text {
                        Text("      rate: \"\(rate)\"")
                            .font(.system(.caption2, design: .monospaced))
                    }

                    let isLast = index == table.rows.count - 1
                    Text("    }\(isLast ? "" : ",")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text("  ]")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)

                Text("}")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                // Confidence footer
                Text("Confidence: \(String(format: "%.0f%%", table.averageConfidence * 100))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ParsedTableDisplayView(table: RecognizedTable())
}
