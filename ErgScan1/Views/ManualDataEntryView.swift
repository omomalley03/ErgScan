import SwiftUI

/// Full-screen manual data entry view for reviewing/editing scanned workout data
struct ManualDataEntryView: View {

    let initialTable: RecognizedTable?
    let validateOnLoad: Bool
    let scanOnBehalfOf: String?
    let scanOnBehalfOfUsername: String?
    let assignmentID: String?
    let assignmentTeamID: String?
    let onComplete: (RecognizedTable) -> Void
    let onCancel: () -> Void

    // Workout type selection
    enum WorkoutType: String, CaseIterable {
        case singleTime = "Single Time"
        case singleDistance = "Single Distance"
        case intervals = "Intervals"
    }

    @State private var workoutType: WorkoutType = .singleDistance

    // Averages row
    @State private var avgTime: String = ""
    @State private var avgMeters: String = ""
    @State private var avgSplit: String = ""
    @State private var avgRate: String = ""
    @State private var avgHR: String = ""

    // Data rows
    @State private var dataRows: [EditableRow] = []

    // Whether HR column should be shown
    private let showHeartRate: Bool

    // Custom keypad state
    enum FieldFocus: Hashable {
        case avgTime, avgMeters, avgSplit, avgRate, avgHR
        case rowField(Int, RowColumn)

        enum RowColumn: Hashable {
            case time, meters, split, rate, hr
        }
    }
    @State private var activeField: FieldFocus? = nil
    @State private var isReplaceMode: Bool = false

    // Validation state
    @State private var splitErrorRows: Set<Int> = []
    @State private var consistencyErrorRows: Set<Int> = []
    @State private var completenessWarning: String? = nil
    @State private var isForceSubmitMode: Bool = false

    struct EditableRow: Identifiable {
        let id = UUID()
        var time: String = ""
        var meters: String = ""
        var split: String = ""
        var rate: String = ""
        var heartRate: String = ""
    }

    init(
        initialTable: RecognizedTable?,
        validateOnLoad: Bool = false,
        scanOnBehalfOf: String? = nil,
        scanOnBehalfOfUsername: String? = nil,
        assignmentID: String? = nil,
        assignmentTeamID: String? = nil,
        onComplete: @escaping (RecognizedTable) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialTable = initialTable
        self.validateOnLoad = validateOnLoad
        self.scanOnBehalfOf = scanOnBehalfOf
        self.scanOnBehalfOfUsername = scanOnBehalfOfUsername
        self.assignmentID = assignmentID
        self.assignmentTeamID = assignmentTeamID
        self.onComplete = onComplete
        self.onCancel = onCancel

        let hasHR = initialTable?.averages?.heartRate != nil ||
            (initialTable?.rows.contains { $0.heartRate != nil } ?? false)
        self.showHeartRate = hasHR

        if let table = initialTable {
            if table.category == .interval {
                _workoutType = State(initialValue: .intervals)
            } else if let wt = table.workoutType, wt.hasSuffix("m") {
                _workoutType = State(initialValue: .singleDistance)
            } else {
                _workoutType = State(initialValue: .singleTime)
            }

            if let avg = table.averages {
                _avgTime = State(initialValue: avg.time?.text ?? "")
                _avgMeters = State(initialValue: avg.meters?.text ?? "")
                _avgSplit = State(initialValue: avg.splitPer500m?.text ?? "")
                _avgRate = State(initialValue: avg.strokeRate?.text ?? "")
                _avgHR = State(initialValue: avg.heartRate?.text ?? "")
            }

            // Build data rows from scanned data
            var initialRows = table.rows.map { row in
                EditableRow(
                    time: row.time?.text ?? "",
                    meters: row.meters?.text ?? "",
                    split: row.splitPer500m?.text ?? "",
                    rate: row.strokeRate?.text ?? "",
                    heartRate: row.heartRate?.text ?? ""
                )
            }

            // Auto-fill missing interval rows if we know the expected count and work per rep
            if table.category == .interval,
               let expectedReps = table.reps,
               let workPerRep = table.workPerRep,
               table.isVariableInterval != true,
               initialRows.count < expectedReps {
                let isDistanceBased = workPerRep.hasSuffix("m")
                while initialRows.count < expectedReps {
                    var newRow = EditableRow()
                    if isDistanceBased {
                        newRow.meters = String(workPerRep.dropLast()) // "500m" → "500"
                    } else {
                        newRow.time = workPerRep // "20:00"
                    }
                    initialRows.append(newRow)
                }
            }

            _dataRows = State(initialValue: initialRows)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Workout type buttons
                HStack(spacing: 8) {
                    ForEach(WorkoutType.allCases, id: \.self) { type in
                        Button {
                            workoutType = type
                            clearValidationState()
                            recalculateAllSplits()
                        } label: {
                            Text(type.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(workoutType == type ? Color.accentColor : Color(.tertiarySystemBackground))
                                )
                                .foregroundColor(workoutType == type ? .white : .primary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                Divider()

                // Column headers
                columnHeaders
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Averages row (fixed, above list)
                averagesRow
                    .padding(.bottom, 4)

                Divider().padding(.horizontal)

                // Data rows section label
                HStack {
                    Text(workoutType == .intervals ? "Intervals" : "Splits")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                // Data rows in List (enables drag-to-reorder)
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(dataRows.enumerated()), id: \.element.id) { index, _ in
                            dataRowView(index: index)
                                .id(dataRows[index].id)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(
                                    (splitErrorRows.contains(index) || consistencyErrorRows.contains(index))
                                        ? Color.red.opacity(0.15)
                                        : Color.clear
                                )
                                .listRowSeparator(.hidden)
                        }
                        .onMove(perform: moveRows)
                        .onDelete(perform: deleteRows)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                    .onChange(of: activeField) { newField in
                        if case .rowField(let idx, _) = newField, idx < dataRows.count {
                            // Delay so keypad has time to appear before scrolling
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation {
                                    proxy.scrollTo(dataRows[idx].id, anchor: .center)
                                }
                            }
                        }
                    }
                }

                // Completeness warning banner
                if let warning = completenessWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                // Action buttons row
                HStack(spacing: 8) {
                    Button {
                        onCancel()
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Retry Scan")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }

                    Button {
                        recalculateAllSplits()
                        recalculateAvgSplit()
                    } label: {
                        HStack {
                            Image(systemName: "function")
                            Text("Fill Splits")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(12)
                    }

                    Button {
                        withAnimation {
                            dataRows.append(EditableRow())
                        }
                        clearValidationState()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(workoutType == .intervals ? "+Interval" : "+Split")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                // Custom keypad (shown when a field is active)
                if activeField != nil {
                    customKeypad
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activeField != nil)
            .navigationTitle("Enter Data Manually")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if validateOnLoad {
                    runInitialValidation()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if isForceSubmitMode {
                            attemptSubmit(forceCompleteness: true)
                        } else {
                            attemptSubmit()
                        }
                    } label: {
                        Text(isForceSubmitMode ? "Force Submit" : "Done")
                            .fontWeight(.semibold)
                            .foregroundColor(isForceSubmitMode ? .red : nil)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Column Headers

    @ViewBuilder
    private var columnHeaders: some View {
        HStack(spacing: 4) {
            Text("Time")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Meters")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("/500m")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("s/m")
                .frame(width: 50, alignment: .leading)
            if showHeartRate {
                Text("HR")
                    .frame(width: 50, alignment: .leading)
            }
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
        .padding(.horizontal)
    }

    // MARK: - Averages Row

    @ViewBuilder
    private var averagesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Totals / Averages")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                editableCell(value: avgTime, placeholder: "0:00.0", field: .avgTime)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                editableCell(value: avgMeters, placeholder: "0", field: .avgMeters)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                editableCell(value: avgSplit, placeholder: "0:00.0", field: .avgSplit)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                editableCell(value: avgRate, placeholder: "0", field: .avgRate)
                    .fontWeight(.semibold)
                    .frame(width: 50)
                if showHeartRate {
                    editableCell(value: avgHR, placeholder: "0", field: .avgHR)
                        .fontWeight(.semibold)
                        .frame(width: 50)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 2)
        )
        .padding(.horizontal)
    }

    // MARK: - Data Row

    @ViewBuilder
    private func dataRowView(index: Int) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                editableCell(
                    value: index < dataRows.count ? dataRows[index].time : "",
                    placeholder: "0:00.0",
                    field: .rowField(index, .time)
                )
                .frame(maxWidth: .infinity)

                editableCell(
                    value: index < dataRows.count ? dataRows[index].meters : "",
                    placeholder: "0",
                    field: .rowField(index, .meters)
                )
                .frame(maxWidth: .infinity)

                editableCell(
                    value: index < dataRows.count ? dataRows[index].split : "",
                    placeholder: "0:00.0",
                    field: .rowField(index, .split)
                )
                .frame(maxWidth: .infinity)

                editableCell(
                    value: index < dataRows.count ? dataRows[index].rate : "",
                    placeholder: "0",
                    field: .rowField(index, .rate)
                )
                .frame(width: 50)

                if showHeartRate {
                    editableCell(
                        value: index < dataRows.count ? dataRows[index].heartRate : "",
                        placeholder: "0",
                        field: .rowField(index, .hr)
                    )
                    .frame(width: 50)
                }
            }
            .padding(.horizontal)

            if consistencyErrorRows.contains(index) {
                Text("check this row")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing)
            }
        }
    }

    // MARK: - Editable Cell (replaces TextField)

    @ViewBuilder
    private func editableCell(value: String, placeholder: String, field: FieldFocus) -> some View {
        let isActive = activeField == field
        let showSelection = isActive && isReplaceMode && !value.isEmpty
        let isSplitError: Bool = {
            if case .rowField(let idx, .split) = field {
                return splitErrorRows.contains(idx)
            }
            return false
        }()

        Text(value.isEmpty ? placeholder : value)
            .font(.body.monospacedDigit())
            .foregroundColor(
                isSplitError ? .red :
                value.isEmpty ? .secondary.opacity(0.4) :
                showSelection ? .white : .primary
            )
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(showSelection ? Color.accentColor.opacity(0.6) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.accentColor : Color(.systemGray4), lineWidth: isActive ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                activeField = field
                isReplaceMode = true
            }
    }

    // MARK: - Custom Keypad

    @ViewBuilder
    private var customKeypad: some View {
        VStack(spacing: 1) {
            Divider()

            VStack(spacing: 8) {
                // Row 1: 1 2 3
                HStack(spacing: 8) {
                    keypadButton("1")
                    keypadButton("2")
                    keypadButton("3")
                }
                // Row 2: 4 5 6
                HStack(spacing: 8) {
                    keypadButton("4")
                    keypadButton("5")
                    keypadButton("6")
                }
                // Row 3: 7 8 9
                HStack(spacing: 8) {
                    keypadButton("7")
                    keypadButton("8")
                    keypadButton("9")
                }
                // Row 4: . 0 :
                HStack(spacing: 8) {
                    keypadButton(":")
                    keypadButton("0")
                    keypadButton(".")
                }
                // Row 5: ⌫, ▼ Hide, Next/Done
                HStack(spacing: 8) {
                    Button {
                        handleBackspace()
                    } label: {
                        Image(systemName: "delete.left.fill")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    .foregroundColor(.primary)

                    Button {
                        activeField = nil
                        isReplaceMode = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                    }
                    .foregroundColor(.primary)

                    Button {
                        handleDoneOrNext()
                    } label: {
                        Text(hasEmptyCells ? "Next" : "Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func keypadButton(_ key: String) -> some View {
        Button {
            handleKeypress(key)
        } label: {
            Text(key)
                .font(.title2)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(.systemBackground))
                .cornerRadius(8)
        }
        .foregroundColor(.primary)
    }

    // MARK: - Keypad Input Handling

    private func handleKeypress(_ key: String) {
        guard let field = activeField else { return }
        clearValidationState()
        if isReplaceMode {
            writeToField(field, value: key)
            isReplaceMode = false
        } else {
            appendToField(field, character: key)
        }
        triggerSplitRecalc(for: field)
    }

    private func handleBackspace() {
        guard let field = activeField else { return }
        clearValidationState()
        if isReplaceMode {
            writeToField(field, value: "")
            isReplaceMode = false
        } else {
            removeLastCharFromField(field)
        }
        triggerSplitRecalc(for: field)
    }

    private func handleDoneOrNext() {
        if let nextField = nextEmptyField(after: activeField) {
            activeField = nextField
            isReplaceMode = true
        } else {
            activeField = nil
            isReplaceMode = false
        }
    }

    // MARK: - Smart Navigation

    private var hasEmptyCells: Bool {
        return nextEmptyField(after: nil) != nil
    }

    private func nextEmptyField(after current: FieldFocus?) -> FieldFocus? {
        let allFields = orderedEditableFields()
        guard !allFields.isEmpty else { return nil }

        let startIdx: Int
        if let current = current, let idx = allFields.firstIndex(of: current) {
            startIdx = idx + 1
        } else {
            startIdx = 0
        }

        // Search from after current to end
        for i in startIdx..<allFields.count {
            if readField(allFields[i]).isEmpty { return allFields[i] }
        }
        // Wrap around from start to current
        for i in 0..<min(startIdx, allFields.count) {
            if readField(allFields[i]).isEmpty { return allFields[i] }
        }
        return nil
    }

    private func orderedEditableFields() -> [FieldFocus] {
        // Required fields only — HR is always optional
        var fields: [FieldFocus] = [.avgTime, .avgMeters, .avgSplit, .avgRate]
        for i in 0..<dataRows.count {
            fields.append(.rowField(i, .time))
            fields.append(.rowField(i, .meters))
            fields.append(.rowField(i, .split))
            fields.append(.rowField(i, .rate))
        }
        return fields
    }

    // MARK: - Field Read/Write Helpers

    private func readField(_ field: FieldFocus) -> String {
        switch field {
        case .avgTime: return avgTime
        case .avgMeters: return avgMeters
        case .avgSplit: return avgSplit
        case .avgRate: return avgRate
        case .avgHR: return avgHR
        case .rowField(let idx, let col):
            guard idx < dataRows.count else { return "" }
            switch col {
            case .time: return dataRows[idx].time
            case .meters: return dataRows[idx].meters
            case .split: return dataRows[idx].split
            case .rate: return dataRows[idx].rate
            case .hr: return dataRows[idx].heartRate
            }
        }
    }

    private func writeToField(_ field: FieldFocus, value: String) {
        switch field {
        case .avgTime: avgTime = value
        case .avgMeters: avgMeters = value
        case .avgSplit: avgSplit = value
        case .avgRate: avgRate = value
        case .avgHR: avgHR = value
        case .rowField(let idx, let col):
            guard idx < dataRows.count else { return }
            switch col {
            case .time: dataRows[idx].time = value
            case .meters: dataRows[idx].meters = value
            case .split: dataRows[idx].split = value
            case .rate: dataRows[idx].rate = value
            case .hr: dataRows[idx].heartRate = value
            }
        }
    }

    private func appendToField(_ field: FieldFocus, character: String) {
        let current = readField(field)
        writeToField(field, value: current + character)
    }

    private func removeLastCharFromField(_ field: FieldFocus) {
        let current = readField(field)
        guard !current.isEmpty else { return }
        writeToField(field, value: String(current.dropLast()))
    }

    // MARK: - Drag-to-Reorder & Delete

    private func moveRows(from source: IndexSet, to destination: Int) {
        activeField = nil
        isReplaceMode = false
        clearValidationState()
        dataRows.move(fromOffsets: source, toOffset: destination)
        recalculateAllSplits()
    }

    private func deleteRows(at offsets: IndexSet) {
        activeField = nil
        isReplaceMode = false
        clearValidationState()
        dataRows.remove(atOffsets: offsets)
        recalculateAllSplits()
    }

    // MARK: - Auto-Calculate Split

    private func parseTime(_ str: String) -> Double? {
        PowerCurveService.timeStringToSeconds(str)
    }

    private func parseMeters(_ str: String) -> Double? {
        let cleaned = str.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func formatSplit(_ seconds: Double) -> String {
        let floored = floor(seconds * 10.0) / 10.0
        return PowerCurveService.secondsToSplitString(floored)
    }

    private func triggerSplitRecalc(for field: FieldFocus) {
        switch field {
        case .avgTime, .avgMeters:
            recalculateAvgSplit()
        case .rowField(let idx, let col):
            if col == .time || col == .meters {
                if workoutType == .singleTime || workoutType == .singleDistance {
                    recalculateAllSplits()
                } else {
                    recalculateSplit(for: idx)
                }
            }
        default:
            break
        }
    }

    private func recalculateAvgSplit() {
        guard let time = parseTime(avgTime),
              let meters = parseMeters(avgMeters),
              meters > 0, time > 0 else { return }
        let splitSec = (time / meters) * 500.0
        avgSplit = formatSplit(splitSec)
    }

    private func recalculateSplit(for index: Int) {
        guard index < dataRows.count else { return }
        let row = dataRows[index]

        switch workoutType {
        case .intervals:
            guard let time = parseTime(row.time),
                  let meters = parseMeters(row.meters),
                  meters > 0, time > 0 else { return }
            dataRows[index].split = formatSplit((time / meters) * 500.0)

        case .singleTime:
            guard let currentTime = parseTime(row.time),
                  let meters = parseMeters(row.meters),
                  meters > 0 else { return }
            let prevTime: Double = index > 0 ? (parseTime(dataRows[index - 1].time) ?? 0) : 0
            let effectiveTime = currentTime - prevTime
            guard effectiveTime > 0 else { return }
            dataRows[index].split = formatSplit((effectiveTime / meters) * 500.0)

        case .singleDistance:
            guard let time = parseTime(row.time),
                  let currentMeters = parseMeters(row.meters),
                  time > 0 else { return }
            let prevMeters: Double = index > 0 ? (parseMeters(dataRows[index - 1].meters) ?? 0) : 0
            let effectiveMeters = currentMeters - prevMeters
            guard effectiveMeters > 0 else { return }
            dataRows[index].split = formatSplit((time / effectiveMeters) * 500.0)
        }
    }

    private func recalculateAllSplits() {
        for i in 0..<dataRows.count {
            recalculateSplit(for: i)
        }
    }

    // MARK: - Validation

    private func clearValidationState() {
        splitErrorRows = []
        consistencyErrorRows = []
        completenessWarning = nil
        isForceSubmitMode = false
    }

    private func runInitialValidation() {
        // Mirror attemptSubmit's flow but don't call completeEntry
        // 1. Split accuracy (hard block)
        let splitErrors = validateSplits()
        if !splitErrors.isEmpty {
            splitErrorRows = splitErrors
            return
        }

        // 2. Split consistency (soft block)
        let consErrors = checkSplitConsistency()
        if !consErrors.isEmpty {
            consistencyErrorRows = consErrors
            isForceSubmitMode = true
            return
        }

        // 3. Meters completeness (soft block)
        if let warning = checkMetersCompleteness() {
            completenessWarning = warning
            isForceSubmitMode = true
        }
    }

    private func calculateExpectedSplit(for index: Int) -> Double? {
        guard index < dataRows.count else { return nil }
        let row = dataRows[index]

        switch workoutType {
        case .intervals:
            guard let time = parseTime(row.time),
                  let meters = parseMeters(row.meters),
                  meters > 0, time > 0 else { return nil }
            return floor((time / meters) * 500.0 * 10.0) / 10.0

        case .singleTime:
            guard let currentTime = parseTime(row.time),
                  let meters = parseMeters(row.meters),
                  meters > 0 else { return nil }
            let prevTime: Double = index > 0 ? (parseTime(dataRows[index - 1].time) ?? 0) : 0
            let effective = currentTime - prevTime
            guard effective > 0 else { return nil }
            return floor((effective / meters) * 500.0 * 10.0) / 10.0

        case .singleDistance:
            guard let time = parseTime(row.time),
                  let currentMeters = parseMeters(row.meters),
                  time > 0 else { return nil }
            let prevMeters: Double = index > 0 ? (parseMeters(dataRows[index - 1].meters) ?? 0) : 0
            let effective = currentMeters - prevMeters
            guard effective > 0 else { return nil }
            return floor((time / effective) * 500.0 * 10.0) / 10.0
        }
    }

    private func validateSplits() -> Set<Int> {
        var errors = Set<Int>()
        for i in 0..<dataRows.count {
            guard let expected = calculateExpectedSplit(for: i),
                  let actual = parseTime(dataRows[i].split) else { continue }
            if abs(expected - actual) > 0.1 {
                errors.insert(i)
            }
        }
        return errors
    }

    private func checkMetersCompleteness() -> String? {
        guard let totalMeters = parseMeters(avgMeters), totalMeters > 0 else { return nil }

        switch workoutType {
        case .intervals, .singleTime:
            let sum = dataRows.compactMap { parseMeters($0.meters) }.reduce(0, +)
            let tolerance = totalMeters * 0.01
            if abs(sum - totalMeters) > tolerance {
                return "Check completeness: \(Int(sum)) of \(Int(totalMeters)) meters accounted for"
            }
        case .singleDistance:
            guard let lastMeters = dataRows.last.flatMap({ parseMeters($0.meters) }) else { return nil }
            let tolerance = totalMeters * 0.01
            if abs(lastMeters - totalMeters) > tolerance {
                return "Check completeness: \(Int(lastMeters)) of \(Int(totalMeters)) meters accounted for"
            }
        }
        return nil
    }

    private func checkSplitConsistency() -> Set<Int> {
        guard dataRows.count >= 2 else { return [] }
        var errors = Set<Int>()

        switch workoutType {
        case .singleTime:
            // Gaps between cumulative time should match first gap (except last)
            guard let firstTime = parseTime(dataRows[0].time),
                  firstTime > 0 else { return [] }
            for i in 1..<(dataRows.count - 1) {
                guard let current = parseTime(dataRows[i].time),
                      let prev = parseTime(dataRows[i - 1].time) else { continue }
                let gap = current - prev
                if abs(gap - firstTime) > 1 {
                    errors.insert(i)
                }
            }

        case .singleDistance:
            // Gaps between cumulative meters should match first gap (except last)
            guard let firstMeters = parseMeters(dataRows[0].meters),
                  firstMeters > 0 else { return [] }
            for i in 1..<(dataRows.count - 1) {
                guard let current = parseMeters(dataRows[i].meters),
                      let prev = parseMeters(dataRows[i - 1].meters) else { continue }
                let gap = current - prev
                if abs(gap - firstMeters) > 1 {
                    errors.insert(i)
                }
            }

        case .intervals:
            break
        }
        return errors
    }

    private func attemptSubmit(forceCompleteness: Bool = false) {
        // 1. Always check split accuracy (hard block)
        let splitErrors = validateSplits()
        if !splitErrors.isEmpty {
            splitErrorRows = splitErrors
            consistencyErrorRows = []
            completenessWarning = nil
            isForceSubmitMode = false
            return
        }
        splitErrorRows = []

        // 2. Check split marker consistency (soft block, skip if force)
        if !forceCompleteness {
            let consErrors = checkSplitConsistency()
            if !consErrors.isEmpty {
                consistencyErrorRows = consErrors
                completenessWarning = nil
                isForceSubmitMode = true
                return
            }
        }
        consistencyErrorRows = []

        // 3. Check completeness (soft block, skip if force)
        if !forceCompleteness {
            if let warning = checkMetersCompleteness() {
                completenessWarning = warning
                isForceSubmitMode = true
                return
            }
        }

        // 4. All checks pass
        completenessWarning = nil
        isForceSubmitMode = false
        completeEntry()
    }

    // MARK: - Completion

    private var isValid: Bool {
        // Check averages row: time, meters, split, and rate must be filled
        guard !avgTime.isEmpty, !avgMeters.isEmpty, !avgSplit.isEmpty, !avgRate.isEmpty else {
            return false
        }

        // Check all data rows: time, meters, split, and rate must be filled
        // HR is always optional
        for row in dataRows {
            if row.time.isEmpty || row.meters.isEmpty || row.split.isEmpty || row.rate.isEmpty {
                return false
            }
        }

        return true
    }

    private func completeEntry() {
        let category: WorkoutCategory = workoutType == .intervals ? .interval : .single

        var avgRow = TableRow(boundingBox: .zero)
        if !avgTime.isEmpty {
            avgRow.time = OCRResult(text: avgTime, confidence: 1.0, boundingBox: .zero)
        }
        if !avgMeters.isEmpty {
            avgRow.meters = OCRResult(text: avgMeters, confidence: 1.0, boundingBox: .zero)
        }
        if !avgSplit.isEmpty {
            avgRow.splitPer500m = OCRResult(text: avgSplit, confidence: 1.0, boundingBox: .zero)
        }
        if !avgRate.isEmpty {
            avgRow.strokeRate = OCRResult(text: avgRate, confidence: 1.0, boundingBox: .zero)
        }
        if showHeartRate && !avgHR.isEmpty {
            avgRow.heartRate = OCRResult(text: avgHR, confidence: 1.0, boundingBox: .zero)
        }

        let rows: [TableRow] = dataRows.map { row in
            var tableRow = TableRow(boundingBox: .zero)
            if !row.time.isEmpty {
                tableRow.time = OCRResult(text: row.time, confidence: 1.0, boundingBox: .zero)
            }
            if !row.meters.isEmpty {
                tableRow.meters = OCRResult(text: row.meters, confidence: 1.0, boundingBox: .zero)
            }
            if !row.split.isEmpty {
                tableRow.splitPer500m = OCRResult(text: row.split, confidence: 1.0, boundingBox: .zero)
            }
            if !row.rate.isEmpty {
                tableRow.strokeRate = OCRResult(text: row.rate, confidence: 1.0, boundingBox: .zero)
            }
            if showHeartRate && !row.heartRate.isEmpty {
                tableRow.heartRate = OCRResult(text: row.heartRate, confidence: 1.0, boundingBox: .zero)
            }
            return tableRow
        }

        let workoutTypeStr = generateWorkoutType()

        let table = RecognizedTable(
            workoutType: workoutTypeStr,
            category: category,
            date: initialTable?.date ?? Date(),
            totalTime: avgTime.isEmpty ? nil : avgTime,
            description: workoutTypeStr,
            reps: category == .interval ? dataRows.count : nil,
            workPerRep: initialTable?.workPerRep,
            restPerRep: initialTable?.restPerRep,
            isVariableInterval: category == .interval && dataRows.count > 1,
            totalDistance: Int(avgMeters.replacingOccurrences(of: ",", with: "")),
            averages: avgRow,
            rows: rows,
            averageConfidence: 1.0
        )

        onComplete(table)
    }

    private func generateWorkoutType() -> String {
        switch workoutType {
        case .singleDistance:
            let m = avgMeters.replacingOccurrences(of: ",", with: "")
            return m.isEmpty ? "Unknown" : "\(m)m"
        case .singleTime:
            return avgTime.isEmpty ? "Unknown" : avgTime
        case .intervals:
            if dataRows.isEmpty { return "Unknown" }
            let distances = dataRows.map { $0.meters.isEmpty ? "?" : "\($0.meters)m" }
            let allSame = Set(distances).count == 1
            if allSame && !dataRows.isEmpty {
                return "\(dataRows.count)x\(distances[0])"
            }
            return distances.joined(separator: " / ")
        }
    }
}

#Preview {
    ManualDataEntryView(
        initialTable: nil,
        onComplete: { table in print("Completed: \(table.workoutType ?? "Unknown")") },
        onCancel: { print("Cancelled") }
    )
}
