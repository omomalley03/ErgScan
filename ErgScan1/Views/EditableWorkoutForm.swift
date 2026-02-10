import SwiftUI

/// Editable form view for reviewing and editing parsed workout data after lock
struct EditableWorkoutForm: View {

    let table: RecognizedTable
    let onSave: (Date, IntensityZone?, Bool) -> Void
    let onRetake: () -> Void

    @State private var editedWorkoutType: String
    @State private var editedDescription: String
    @State private var editedDate: Date
    @State private var showDatePicker: Bool = false
    @State private var selectedZone: IntensityZone? = nil
    @State private var isErgTest: Bool = false

    init(table: RecognizedTable, onSave: @escaping (Date, IntensityZone?, Bool) -> Void, onRetake: @escaping () -> Void) {
        self.table = table
        self.onSave = onSave
        self.onRetake = onRetake

        // Initialize editable fields with current values
        _editedWorkoutType = State(initialValue: table.workoutType ?? "")
        _editedDescription = State(initialValue: table.description ?? "")
        // Default to today if OCR didn't capture the date
        _editedDate = State(initialValue: table.date ?? Date())
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

                // 2. Date Selector (always editable)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(table.date == nil ? .orange : .secondary)
                            Text(editedDate, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(showDatePicker ? 180 : 0))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }

                    // Show warning if date wasn't detected by OCR
                    if table.date == nil {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Date not detected - defaulted to today. Tap to change.")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }

                    // Date Picker (shown when tapped)
                    if showDatePicker {
                        DatePicker(
                            "Select Date",
                            selection: $editedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 4)

                // 3. Intensity Zone Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Intensity Zone")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(IntensityZone.allCases, id: \.self) { zone in
                            Button {
                                if selectedZone == zone {
                                    selectedZone = nil
                                } else {
                                    selectedZone = zone
                                }
                            } label: {
                                Text(zone.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedZone == zone
                                                  ? zone.color.opacity(0.8)
                                                  : zone.color.opacity(0.15))
                                    )
                                    .foregroundColor(selectedZone == zone ? .white : zone.color)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)

                // 4. Erg Test Checkbox
                Button {
                    isErgTest.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isErgTest ? "flag.checkered" : "flag.checkered")
                            .font(.title3)
                            .foregroundColor(isErgTest ? .primary : .secondary.opacity(0.4))
                        Text("Erg Test?")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isErgTest ? Color(.secondarySystemBackground) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isErgTest ? Color.primary.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.bottom, 4)

                // 5. Descriptor Row (editable)
                TextField("Description", text: $editedDescription)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 8)

                Divider()

                // 4. Column Headers
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

                // 5. Summary/Averages Row (bold to distinguish from data rows)
                if let averages = table.averages {
                    EditableTableRowView(row: averages, showHeartRate: showHeartRate)
                        .fontWeight(.semibold)

                    Divider()
                }

                // 6. Data Rows in tabular format
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
                onSave(editedDate, selectedZone, isErgTest)
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
        onSave: { date, zone, isTest in print("Save with date: \(date), zone: \(zone?.rawValue ?? "none"), test: \(isTest)") },
        onRetake: { print("Retake") }
    )
}
