//
//  DashboardView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Binding var showSearch: Bool

    // Filter workouts by current user
    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID }
    }

    private var recentWorkout: Workout? {
        workouts.first
    }

    // Get workouts for the last 7 days
    private var weeklyData: [(day: String, meters: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayName = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]

            let metersForDay = workouts
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .compactMap { $0.totalDistance }
                .reduce(0, +)

            return (dayName, metersForDay)
        }.reversed()
    }

    var body: some View {
        NavigationStack {
            if workouts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Weekly Progress Widget
                        WeeklyProgressWidget(weeklyData: weeklyData)
                            .padding(.horizontal)

                        // Most Recent Workout Widget
                        if let recentWorkout = recentWorkout {
                            RecentWorkoutWidget(workout: recentWorkout)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 100) // Space for tab bar
                }
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

// MARK: - Weekly Progress Widget

struct WeeklyProgressWidget: View {
    let weeklyData: [(day: String, meters: Int)]

    private var maxMeters: Int {
        weeklyData.map { $0.meters }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(weeklyData, id: \.day) { data in
                    VStack(spacing: 4) {
                        // Bar
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 100)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(height: data.meters > 0 ? CGFloat(data.meters) / CGFloat(maxMeters) * 100 : 2)
                        }
                        .frame(maxWidth: .infinity)

                        // Day label
                        Text(data.day)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 120)

            // Total meters
            HStack {
                Text("Total:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(weeklyData.map { $0.meters }.reduce(0, +))m")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
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

    var body: some View {
        NavigationLink(destination: EnhancedWorkoutDetailView(workout: workout)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Most Recent")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.workoutType)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        HStack(spacing: 12) {
                            Label(workout.totalTime, systemImage: "clock")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if let distance = workout.totalDistance {
                                Label("\(distance)m", systemImage: "figure.rowing")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(workout.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}

