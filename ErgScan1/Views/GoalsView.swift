import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @Query private var allGoals: [Goal]

    @State private var weeklyGoal: String = ""
    @State private var monthlyGoal: String = ""
    @State private var ut2Percent: Double = 60
    @State private var ut1Percent: Double = 25
    @State private var atPercent: Double = 10
    @State private var maxPercent: Double = 5
    @State private var loaded = false

    private var userGoal: Goal? {
        guard let currentUser = currentUser else { return nil }
        return allGoals.first { $0.userID == currentUser.appleUserID }
    }

    // Current week meters
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]

    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID }
    }

    private var weeklyMeters: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return workouts
            .filter { $0.date >= startOfWeek }
            .compactMap { $0.totalDistance }
            .reduce(0, +)
    }

    private var monthlyMeters: Int {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return workouts
            .filter { $0.date >= startOfMonth }
            .compactMap { $0.totalDistance }
            .reduce(0, +)
    }

    private var zoneTotal: Double {
        ut2Percent + ut1Percent + atPercent + maxPercent
    }

    var body: some View {
        NavigationStack {
            Form {
                // Current Progress
                if let goal = userGoal {
                    Section("Current Progress") {
                        if goal.weeklyMeterGoal > 0 {
                            ProgressRow(
                                label: "Weekly",
                                current: weeklyMeters,
                                target: goal.weeklyMeterGoal,
                                color: .blue
                            )
                        }
                        if goal.monthlyMeterGoal > 0 {
                            ProgressRow(
                                label: "Monthly",
                                current: monthlyMeters,
                                target: goal.monthlyMeterGoal,
                                color: .green
                            )
                        }
                    }
                }

                // Meter Goals
                Section("Meter Goals") {
                    HStack {
                        Text("Weekly")
                        Spacer()
                        TextField("0", text: $weeklyGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Monthly")
                        Spacer()
                        TextField("0", text: $monthlyGoal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }
                }

                // Target Zone Distribution
                Section {
                    ZoneSliderRow(label: "UT2", percent: $ut2Percent, color: .blue)
                    ZoneSliderRow(label: "UT1", percent: $ut1Percent, color: .green)
                    ZoneSliderRow(label: "AT", percent: $atPercent, color: .yellow)
                    ZoneSliderRow(label: "Max", percent: $maxPercent, color: .red)

                    // Stacked bar preview
                    HStack(spacing: 2) {
                        if ut2Percent > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(height: 20)
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: ut2Percent / 100, anchor: .leading)
                        }
                        if ut1Percent > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(height: 20)
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: ut1Percent / 100, anchor: .leading)
                        }
                        if atPercent > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.yellow)
                                .frame(height: 20)
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: atPercent / 100, anchor: .leading)
                        }
                        if maxPercent > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.red)
                                .frame(height: 20)
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: maxPercent / 100, anchor: .leading)
                        }
                    }

                    if abs(zoneTotal - 100) > 0.5 {
                        Text("Zone percentages total \(Int(zoneTotal))% (should be 100%)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Target Zone Distribution")
                } footer: {
                    Text("Optional — set your ideal training mix")
                }

                // Save Button
                Section {
                    Button {
                        saveGoal()
                        dismiss()
                    } label: {
                        Text("Save Goals")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if !loaded {
                    loadExistingGoal()
                    loaded = true
                }
            }
        }
    }

    private func loadExistingGoal() {
        guard let goal = userGoal else { return }
        weeklyGoal = goal.weeklyMeterGoal > 0 ? "\(goal.weeklyMeterGoal)" : ""
        monthlyGoal = goal.monthlyMeterGoal > 0 ? "\(goal.monthlyMeterGoal)" : ""
        ut2Percent = Double(goal.targetUT2Percent)
        ut1Percent = Double(goal.targetUT1Percent)
        atPercent = Double(goal.targetATPercent)
        maxPercent = Double(goal.targetMaxPercent)
    }

    private func saveGoal() {
        let weekly = Int(weeklyGoal) ?? 0
        let monthly = Int(monthlyGoal) ?? 0

        if let goal = userGoal {
            goal.weeklyMeterGoal = weekly
            goal.monthlyMeterGoal = monthly
            goal.targetUT2Percent = Int(ut2Percent)
            goal.targetUT1Percent = Int(ut1Percent)
            goal.targetATPercent = Int(atPercent)
            goal.targetMaxPercent = Int(maxPercent)
            goal.lastModifiedAt = Date()
        } else {
            let goal = Goal(
                weeklyMeterGoal: weekly,
                monthlyMeterGoal: monthly,
                targetUT2Percent: Int(ut2Percent),
                targetUT1Percent: Int(ut1Percent),
                targetATPercent: Int(atPercent),
                targetMaxPercent: Int(maxPercent),
                userID: currentUser?.appleUserID
            )
            modelContext.insert(goal)
        }
    }
}

// MARK: - Supporting Views

private struct ProgressRow: View {
    let label: String
    let current: Int
    let target: Int
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(current)m / \(target)m")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ZoneSliderRow: View {
    let label: String
    @Binding var percent: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(percent))%")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            Slider(value: $percent, in: 0...100, step: 5)
                .tint(color)
        }
    }
}
