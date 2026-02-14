//
//  DashboardView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI
import SwiftData

// MARK: - Zone bar segment data

struct ZoneSegment: Identifiable {
    let id = UUID()
    let zone: IntensityZone
    let meters: Int
}

struct BarData: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    let totalMeters: Int
    let segments: [ZoneSegment]  // bottom-to-top stacking order
    let unzonedMeters: Int       // meters with no zone assigned
}

// MARK: - Dashboard View

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Binding var showSearch: Bool
    var onViewDay: ((Date) -> Void)?
    @Query private var allGoals: [Goal]
    @State private var weekOffset: Int = 0  // 0 = this week, 1 = last week, etc.
    @State private var selectedFeedWorkout: SocialService.SharedWorkoutResult?

    private var userGoal: Goal? {
        guard let currentUser = currentUser else { return nil }
        return allGoals.first { $0.userID == currentUser.appleUserID }
    }

    private var weeklyMeters: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return workouts
            .filter { $0.date >= startOfWeek }
            .compactMap { $0.totalDistance }
            .reduce(0, +)
    }

    // Filter workouts by current user
    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID }
    }

    private var recentWorkouts: [Workout] {
        Array(workouts.prefix(3))
    }

    // Monday of the displayed week
    private var displayedMonday: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7  // Mon=0, Tue=1, ..., Sun=6
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        return calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: thisMonday)!
    }

    // Title for the displayed week
    private var weekTitle: String {
        if weekOffset == 0 {
            return "This Week"
        } else if weekOffset == 1 {
            return "Last Week"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return "Week of \(formatter.string(from: displayedMonday))"
        }
    }

    // Monday-based week: 7 days Mon-Sun for the displayed week
    private func barDataForWeek(offset: Int) -> [BarData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let monday = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisMonday)!

        return (0..<7).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: monday)!
            let dayName = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]

            let dayWorkouts = workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
            return buildBarData(label: dayName, date: date, from: dayWorkouts)
        }
    }

    private var weeklyBarData: [BarData] {
        barDataForWeek(offset: weekOffset)
    }

    // 8-week data — commented out / disabled
    // private var eightWeekBarData: [BarData] { ... }

    private func buildBarData(label: String, date: Date, from subset: [Workout]) -> BarData {
        var segments: [ZoneSegment] = []
        var unzoned = 0

        for zone in IntensityZone.allCases {
            let meters = subset
                .filter { $0.zone == zone }
                .compactMap { $0.totalDistance }
                .reduce(0, +)
            if meters > 0 {
                segments.append(ZoneSegment(zone: zone, meters: meters))
            }
        }

        unzoned = subset
            .filter { $0.zone == nil }
            .compactMap { $0.totalDistance }
            .reduce(0, +)

        let total = segments.map(\.meters).reduce(0, +) + unzoned
        return BarData(label: label, date: date, totalMeters: total, segments: segments, unzonedMeters: unzoned)
    }

    private var myUserID: String {
        currentUser?.appleUserID ?? ""
    }

    @ViewBuilder
    private var friendsActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friends Activity")
                .font(.headline)
                .padding(.horizontal)

            if socialService.friendActivity.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "figure.rowing")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(socialService.friends.isEmpty ? "Add friends to see their activity" : "No recent activity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(socialService.friendActivity) { workout in
                        WorkoutFeedCard(
                            workout: workout,
                            showProfileHeader: true,
                            currentUserID: myUserID
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFeedWorkout = workout
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    var body: some View {
        NavigationStack {
            if workouts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Goal progress (if set)
                        if let goal = userGoal, goal.weeklyMeterGoal > 0 {
                            GoalProgressWidget(currentMeters: weeklyMeters, targetMeters: goal.weeklyMeterGoal)
                                .padding(.horizontal)
                        }

                        // Swipeable weekly chart
                        SwipeableWeekChart(
                            weekOffset: $weekOffset,
                            weekTitle: weekTitle,
                            bars: weeklyBarData,
                            barDataForWeek: barDataForWeek,
                            onViewDay: onViewDay
                        )
                        .padding(.horizontal)

                        // 8-Week Overview — disabled
                        // ZoneStackedBarChart(
                        //     title: "8-Week Overview",
                        //     bars: eightWeekBarData,
                        //     barHeight: 100
                        // )
                        // .padding(.horizontal)

                        // Friends Activity Feed
                        friendsActivitySection
                    }
                    .padding(.top, 16)
                    // .padding(.bottom, 80)
                }
                .navigationTitle("Dashboard")
                .task {
                    await socialService.loadFriendActivity()
                }
                .refreshable {
                    await socialService.loadFriendActivity()
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
                .navigationDestination(item: $selectedFeedWorkout) { workout in
                    UnifiedWorkoutDetailView(sharedWorkout: workout, currentUserID: myUserID)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "house")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Workouts Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to scan your first workout")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
    }
}

// MARK: - Week Chart with Arrow Navigation

struct SwipeableWeekChart: View {
    @Binding var weekOffset: Int
    let weekTitle: String
    let bars: [BarData]
    let barDataForWeek: (Int) -> [BarData]
    var onViewDay: ((Date) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Navigation header
            HStack {
                Button {
                    weekOffset += 1
                    HapticService.shared.lightImpact()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(weekTitle)
                    .font(.headline)

                Spacer()

                Button {
                    guard weekOffset > 0 else { return }
                    weekOffset -= 1
                    HapticService.shared.lightImpact()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(weekOffset > 0 ? .blue : .secondary.opacity(0.3))
                }
                .disabled(weekOffset == 0)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            ZoneStackedBarChart(
                title: "",
                bars: bars,
                barHeight: 120,
                onViewDay: onViewDay
            )
        }
    }
}

// MARK: - Zone Stacked Bar Chart

struct ZoneStackedBarChart: View {
    let title: String
    let bars: [BarData]
    let barHeight: CGFloat
    var onViewDay: ((Date) -> Void)?

    @State private var selectedIndex: Int?

    private var maxMeters: Int {
        bars.map(\.totalMeters).max() ?? 1
    }

    private var totalMeters: Int {
        bars.map(\.totalMeters).reduce(0, +)
    }

    // Y-axis tick values
    private var yAxisTicks: [Int] {
        let max = maxMeters
        guard max > 0 else { return [0] }
        let step = niceStep(for: max)
        var ticks: [Int] = []
        var value = 0
        while value <= max {
            ticks.append(value)
            value += step
        }
        if let last = ticks.last, last < max {
            ticks.append(last + step)
        }
        return ticks
    }

    private func niceStep(for value: Int) -> Int {
        guard value > 0 else { return 1 }
        let rough = Double(value) / 3.0
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let niceNorm: Double
        if normalized <= 1 { niceNorm = 1 }
        else if normalized <= 2 { niceNorm = 2 }
        else if normalized <= 5 { niceNorm = 5 }
        else { niceNorm = 10 }
        return max(Int(niceNorm * magnitude), 1)
    }

    private func formatMeters(_ m: Int) -> String {
        if m >= 1000 {
            let k = Double(m) / 1000.0
            if k == floor(k) {
                return "\(Int(k))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(m)"
    }

    private var yAxisMax: Int {
        yAxisTicks.last ?? maxMeters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

            // Selected bar detail
            if let index = selectedIndex, index < bars.count {
                let bar = bars[index]
                VStack(spacing: 8) {
                    HStack {
                        Text(bar.date, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(bar.totalMeters)m")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }

                    if bar.totalMeters > 0, let onViewDay {
                        Button {
                            HapticService.shared.lightImpact()
                            onViewDay(bar.date)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption)
                                Text("View Day")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }

            // Chart area with y-axis
            HStack(alignment: .bottom, spacing: 0) {
                // Y-axis labels
                VStack(alignment: .trailing, spacing: 0) {
                    GeometryReader { geo in
                        let chartH = geo.size.height
                        ForEach(yAxisTicks, id: \.self) { tick in
                            let frac = yAxisMax > 0 ? CGFloat(tick) / CGFloat(yAxisMax) : 0
                            let y = chartH - (frac * chartH)
                            Text(formatMeters(tick))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .position(x: 16, y: y)
                        }
                    }
                }
                .frame(width: 36, height: barHeight)

                // Bars
                HStack(alignment: .bottom, spacing: bars.count > 7 ? 4 : 8) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                        VStack(spacing: 4) {
                            // Stacked bar
                            ZStack(alignment: .bottom) {
                                // Background track
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: barHeight)

                                // Stacked zone segments
                                stackedBar(for: bar, isSelected: selectedIndex == index)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if selectedIndex == index {
                                        selectedIndex = nil
                                    } else {
                                        selectedIndex = index
                                        HapticService.shared.lightImpact()
                                    }
                                }
                            }

                            // Label
                            Text(bar.label)
                                .font(.system(size: bars.count > 7 ? 8 : 10))
                                .foregroundColor(selectedIndex == index ? .blue : .secondary)
                                .fontWeight(selectedIndex == index ? .bold : .regular)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
            .frame(height: barHeight + 20)

            // Zone legend + total
            HStack {
                HStack(spacing: 10) {
                    ForEach(IntensityZone.allCases, id: \.self) { zone in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(zone.color)
                                .frame(width: 7, height: 7)
                            Text(zone.displayName)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Text("Total: \(formatMeters(totalMeters))m")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .onChange(of: bars.map(\.label).joined()) { _, _ in
            // Reset selection when week changes
            selectedIndex = nil
        }
    }

    @ViewBuilder
    private func stackedBar(for bar: BarData, isSelected: Bool) -> some View {
        let totalH = yAxisMax > 0 ? CGFloat(bar.totalMeters) / CGFloat(yAxisMax) * barHeight : 0
        let dimmed = selectedIndex != nil && !isSelected

        if bar.totalMeters > 0 {
            VStack(spacing: 0) {
                if bar.unzonedMeters > 0 {
                    let segH = CGFloat(bar.unzonedMeters) / CGFloat(bar.totalMeters) * totalH
                    Color.gray.opacity(dimmed ? 0.2 : 0.4)
                        .frame(height: segH)
                }

                ForEach(bar.segments.reversed()) { seg in
                    let segH = CGFloat(seg.meters) / CGFloat(bar.totalMeters) * totalH
                    seg.zone.color.opacity(dimmed ? 0.3 : 1.0)
                        .frame(height: segH)
                }
            }
            .frame(height: totalH)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Goal Progress Widget

struct GoalProgressWidget: View {
    let currentMeters: Int
    let targetMeters: Int

    private var progress: Double {
        guard targetMeters > 0 else { return 0 }
        return min(Double(currentMeters) / Double(targetMeters), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weekly Goal")
                    .font(.headline)
                Spacer()
                Text("\(currentMeters)m / \(targetMeters)m")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(progress >= 1.0 ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * progress, height: 12)
                }
            }
            .frame(height: 12)

            Text("\(Int(progress * 100))% complete")
                .font(.caption)
                .foregroundColor(progress >= 1.0 ? .green : .secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Recent Workout Widget

struct RecentWorkoutWidget: View {
    let workout: Workout
    var currentUserID: String = ""

    var body: some View {
        NavigationLink(destination: UnifiedWorkoutDetailView(localWorkout: workout, currentUserID: currentUserID)) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(workout.workoutType)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        if let zone = workout.zone {
                            Text(zone.displayName)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(zone.color))
                        }
                    }

                    HStack(spacing: 12) {
                        if let split = workout.averageSplit, !split.isEmpty {
                            Label(split, systemImage: "timer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let distance = workout.totalDistance {
                            Label("\(distance)m", systemImage: "figure.rowing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(workout.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}
