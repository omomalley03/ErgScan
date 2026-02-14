//
//  LogView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Binding var showSearch: Bool
    @Binding var highlightDate: Date?
    @State private var highlightedIDs: Set<UUID> = []

    // Filter workouts by current user
    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID }
    }

    private var myUserID: String {
        currentUser?.appleUserID ?? ""
    }

    var body: some View {
        NavigationStack {
            if workouts.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(workouts) { workout in
                                NavigationLink(destination: UnifiedWorkoutDetailView(
                                    localWorkout: workout,
                                    currentUserID: myUserID
                                )) {
                                    LogWorkoutCard(workout: workout)
                                }
                                .buttonStyle(.plain)
                                .id(workout.id)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteWorkout(workout)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .background(
                                    highlightedIDs.contains(workout.id)
                                        ? RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.15))
                                        : nil
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                    }
                    .navigationTitle("Log")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                showSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                    .onAppear {
                        processHighlight(proxy: proxy)
                    }
                    .onChange(of: highlightDate) { _, _ in
                        processHighlight(proxy: proxy)
                    }
                    .refreshable {
                        // Triggers SwiftData @Query refresh
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Workouts Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to log your first workout")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Log")
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

    // MARK: - Highlight

    private func processHighlight(proxy: ScrollViewProxy) {
        guard let date = highlightDate else { return }
        let calendar = Calendar.current
        let matching = workouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
        guard let first = matching.first else {
            highlightDate = nil
            return
        }
        highlightedIDs = Set(matching.map(\.id))
        withAnimation {
            proxy.scrollTo(first.id, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.5)) {
                highlightedIDs.removeAll()
            }
            highlightDate = nil
        }
    }

    // MARK: - Actions

    private func deleteWorkout(_ workout: Workout) {
        let workoutIDString = workout.id.uuidString
        Task { await socialService.deleteSharedWorkout(localWorkoutID: workoutIDString) }
        modelContext.delete(workout)
    }
}

// MARK: - Log Workout Card (condensed feed-style)

struct LogWorkoutCard: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Workout type + zone + erg test + date
            HStack(spacing: 8) {
                Text(workout.workoutType)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                if let zone = workout.zone {
                    ZoneTag(zone: zone)
                }

                if workout.isErgTest {
                    Image(systemName: "flag.checkered")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Spacer()

                Text(workout.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Row 2: Stats
            HStack(spacing: 16) {
                if !workout.workTime.isEmpty {
                    statRow(label: "Time", value: workout.workTime)
                }
                if let dist = workout.totalDistance, dist > 0 {
                    statRow(label: "Dist", value: "\(dist)m")
                }
                Spacer()
                if let split = workout.averageSplit, !split.isEmpty {
                    statRow(label: "Split", value: split)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
