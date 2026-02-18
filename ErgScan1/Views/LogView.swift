//
//  LogView.swift
//  ErgScan1
//
//  Created by Claude on 2/10/26.
//

import SwiftUI
import SwiftData

struct LogView: View {
    private enum WorkoutTypeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case interval = "Intervals"
        case singleTime = "Single Time"
        case singleDistance = "Single Distance"

        var id: String { rawValue }
    }

    private static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var teamService: TeamService
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Binding var highlightDate: Date?
    @State private var highlightedIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var zoneFilter: IntensityZone?
    @State private var typeFilter: WorkoutTypeFilter = .all
    @State private var isDateFilterEnabled = false
    @State private var dateFilter = Date()
    @State private var isErgTestOnly = false

    // Filter workouts by current user
    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID && $0.scannedForUserID == nil }
    }

    private var filteredWorkouts: [Workout] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let calendar = Calendar.current

        return workouts.filter { workout in
            if !query.isEmpty {
                let dateText = Self.searchDateFormatter.string(from: workout.date).lowercased()
                var tokens: [String] = [
                    workout.workoutType,
                    workout.workTime,
                    workout.averageSplit ?? "",
                    dateText
                ]
                if let distance = workout.totalDistance {
                    tokens.append("\(distance)")
                }
                if let zone = workout.zone?.displayName {
                    tokens.append(zone)
                }
                if workout.isErgTest {
                    tokens.append("erg test")
                    tokens.append("test")
                }

                let matchesSearch = tokens.joined(separator: " ").lowercased().contains(query)
                if !matchesSearch { return false }
            }

            if let zoneFilter, workout.zone != zoneFilter {
                return false
            }

            switch typeFilter {
            case .all:
                break
            case .interval:
                if workout.category != .interval { return false }
            case .singleTime:
                if workout.category != .single || isSingleDistance(workout) { return false }
            case .singleDistance:
                if workout.category != .single || !isSingleDistance(workout) { return false }
            }

            if isDateFilterEnabled && !calendar.isDate(workout.date, inSameDayAs: dateFilter) {
                return false
            }

            if isErgTestOnly && !workout.isErgTest {
                return false
            }

            return true
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if zoneFilter != nil { count += 1 }
        if typeFilter != .all { count += 1 }
        if isDateFilterEnabled { count += 1 }
        if isErgTestOnly { count += 1 }
        return count
    }

    private var myUserID: String {
        currentUser?.appleUserID ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    emptyState
                } else if filteredWorkouts.isEmpty {
                    noResultsState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredWorkouts) { workout in
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
                        .onAppear {
                            processHighlight(proxy: proxy)
                        }
                        .onChange(of: highlightDate) { _, _ in
                            processHighlight(proxy: proxy)
                        }
                        .refreshable {
                            await socialService.loadFriendActivity(forceRefresh: true)
                        }
                    }
                }
            }
            .navigationTitle("Log")
            .searchable(text: $searchText, prompt: "Search your workouts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
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
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No Matching Workouts")
                .font(.headline)
            Text("Try a different search or clear one or more filters.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !searchText.isEmpty || activeFilterCount > 0 {
                Button("Clear Search & Filters") {
                    clearAllFilters(includeSearch: true)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Highlight

    private func processHighlight(proxy: ScrollViewProxy) {
        guard let date = highlightDate else { return }
        let calendar = Calendar.current
        let matching = filteredWorkouts.filter { calendar.isDate($0.date, inSameDayAs: date) }
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

    private func isSingleDistance(_ workout: Workout) -> Bool {
        workout.workoutType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasSuffix("m")
    }

    private func clearAllFilters(includeSearch: Bool = false) {
        if includeSearch {
            searchText = ""
        }
        zoneFilter = nil
        typeFilter = .all
        isDateFilterEnabled = false
        isErgTestOnly = false
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Zone") {
                    Picker("Intensity Zone", selection: $zoneFilter) {
                        Text("Any").tag(IntensityZone?.none)
                        ForEach(IntensityZone.allCases, id: \.self) { zone in
                            Text(zone.displayName).tag(IntensityZone?.some(zone))
                        }
                    }
                }

                Section("Workout Type") {
                    Picker("Type", selection: $typeFilter) {
                        ForEach(WorkoutTypeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Date") {
                    Toggle("Filter by date", isOn: $isDateFilterEnabled)
                    if isDateFilterEnabled {
                        DatePicker("Workout Date", selection: $dateFilter, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                }

                Section("Flags") {
                    Toggle("Erg Test only", isOn: $isErgTestOnly)
                }

                Section {
                    Button("Clear All Filters") {
                        clearAllFilters()
                    }
                    .disabled(activeFilterCount == 0)
                }
            }
            .navigationTitle("Log Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showFilterSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteWorkout(_ workout: Workout) {
        let workoutIDString = workout.id.uuidString
        Task {
            if let deletedID = await socialService.deleteSharedWorkout(
                localWorkoutID: workoutIDString,
                sharedWorkoutRecordID: workout.sharedWorkoutRecordID
            ) {
                await MainActor.run {
                    teamService.removeFromTeamActivity(workoutID: deletedID)
                }
            }
            await socialService.loadFriendActivity(forceRefresh: true)
            if let teamID = teamService.selectedTeamID {
                await teamService.loadTeamActivity(teamID: teamID, forceRefresh: true)
            }
        }
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
