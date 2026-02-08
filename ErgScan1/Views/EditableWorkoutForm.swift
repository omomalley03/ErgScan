import SwiftUI

/// Editable form view for reviewing and editing parsed workout data after lock
struct EditableWorkoutForm: View {

    let table: RecognizedTable
    let onSave: () -> Void
    let onRetake: () -> Void

    @State private var editedWorkoutType: String
    @State private var editedDescription: String

    init(table: RecognizedTable, onSave: @escaping () -> Void, onRetake: @escaping () -> Void) {
        self.table = table
        self.onSave = onSave
        self.onRetake = onRetake

        // Initialize editable fields with current values
        _editedWorkoutType = State(initialValue: table.workoutType ?? "")
        _editedDescription = State(initialValue: table.description ?? "")
    }

    // Helper computed property to determine if heart rate column should be shown
    private var showHeartRate: Bool {
        table.averages?.heartRate != nil || table.rows.contains(where: { $0.heartRate != nil })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 1. Workout Type + Completeness Indicator
                HStack {
                    TextField("Workout Type", text: $editedWorkoutType)
                        .font(.title2)
                        .fontWeight(.bold)
                        .textFieldStyle(.plain)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(table.isComplete ? .green : .orange)
                        Text("\(Int(table.completenessScore * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)

                // 2. Descriptor Row (editable)
                TextField("Description", text: $editedDescription)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 8)

                Divider()

                // 3. Column Headers
                HStack(spacing: 0) {
                    Text("Time")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Meters")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("/500m")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("s/m")
                        .frame(width: 50, alignment: .leading)
                    if showHeartRate {
                        Text("♥")
                            .frame(width: 50, alignment: .leading)
                    }
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.vertical, 8)

                Divider()

                // 4. Summary/Averages Row (bold to distinguish from data rows)
                if let averages = table.averages {
                    EditableTableRowView(row: averages, showHeartRate: showHeartRate)
                        .fontWeight(.semibold)

                    Divider()
                }

                // 5. Data Rows in tabular format
                if !table.rows.isEmpty {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                        EditableTableRowView(row: row, showHeartRate: showHeartRate)

                        if index < table.rows.count - 1 {
                            Divider()
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }

        // Action buttons
        HStack(spacing: 16) {
            Button {
                onRetake()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Retake")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }

            Button {
                onSave()
            } label: {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Save Workout")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Supporting Views

/// Table row view with confidence indicators matching PM5 monitor layout
struct EditableTableRowView: View {
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
            if showHeartRate {
                cellView(row.heartRate)
                    .frame(width: 50, alignment: .leading)
            }
        }
        .font(.body.monospacedDigit())
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func cellView(_ result: OCRResult?) -> some View {
        if let result = result {
            HStack(spacing: 4) {
                Text(result.text)
                    .foregroundColor(result.confidence < 0.6 ? .orange : .primary)

                if result.confidence < 0.6 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
        } else {
            Text("--")
                .foregroundStyle(.quaternary)
        }
    }
}

#Preview {
    let sampleTable = RecognizedTable(
        workoutType: "Just Row",
        totalTime: "8:24.5",
        description: "2000m",
        totalDistance: 2000,
        averages: TableRow(boundingBox: .zero),
        rows: [],
        averageConfidence: 0.85
    )

    EditableWorkoutForm(
        table: sampleTable,
        onSave: { print("Save") },
        onRetake: { print("Retake") }
    )
}
