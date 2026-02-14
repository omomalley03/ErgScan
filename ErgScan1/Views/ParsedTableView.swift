import SwiftUI

/// Bottom-half view that displays parsed OCR data as a structured table
struct ParsedTableView: View {

    let table: RecognizedTable?

    var body: some View {
        if let table = table, hasAnyData(table) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Workout metadata
                    HStack(spacing: 8) {
                        if let workoutType = table.workoutType {
                            Text(workoutType)
                                .font(.headline)
                        }

                        if let category = table.category {
                            Text(category == .interval ? "INTERVAL" : "SINGLE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        category == .interval ? Color.blue : Color.green
                                    )
                                )
                        }

                        Spacer()

                        if let date = table.date {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Column headers
                    HStack(spacing: 0) {
                        Text("Time")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Meters")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("/500m")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("s/m")
                            .frame(width: 50, alignment: .leading)

                        // Show HR header if any row has HR data
                        if hasHeartRateData(table) {
                            Text("HR")
                                .frame(width: 50, alignment: .leading)
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                    Divider()

                    // Averages row
                    if let averages = table.averages {
                        ParsedTableRowView(row: averages, showHeartRate: hasHeartRateData(table))
                            .fontWeight(.semibold)
                        Divider()
                    }

                    // Data rows
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                        ParsedTableRowView(row: row, showHeartRate: hasHeartRateData(table))
                        if index < table.rows.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .padding(.bottom, 80)
            }
        } else {
            // Empty state
            VStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Point camera at the erg monitor")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hasAnyData(_ table: RecognizedTable) -> Bool {
        table.workoutType != nil || table.averages != nil || !table.rows.isEmpty
    }

    private func hasHeartRateData(_ table: RecognizedTable) -> Bool {
        // Check averages row
        if table.averages?.heartRate != nil { return true }

        // Check any data row
        return table.rows.contains { $0.heartRate != nil }
    }
}

// MARK: - Row View

struct ParsedTableRowView: View {

    let row: TableRow
    let showHeartRate: Bool

    var body: some View {
        HStack(spacing: 0) {
            cellView(row.time)
                .frame(maxWidth: .infinity, alignment: .leading)
            cellView(row.meters)
                .frame(maxWidth: .infinity, alignment: .leading)
            cellView(row.splitPer500m)
                .frame(maxWidth: .infinity, alignment: .leading)
            cellView(row.strokeRate)
                .frame(width: 50, alignment: .leading)

            // Show HR cell if any row has HR data
            if showHeartRate {
                cellView(row.heartRate)
                    .frame(width: 50, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ result: OCRResult?) -> some View {
        if let result = result {
            Text(result.text)
                .font(.body.monospacedDigit())
                .foregroundColor(confidenceColor(result.confidence))
        } else {
            Text("--")
                .font(.body.monospacedDigit())
                .foregroundStyle(.quaternary)
        }
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .primary
        } else if confidence > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}
