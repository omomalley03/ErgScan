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
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]
    @Binding var showSearch: Bool
    @Binding var highlightDate: Date?
    @State private var highlightedIDs: Set<UUID> = []

    // Filter workouts by current user
    private var workouts: [Workout] {
        guard let currentUser = currentUser else { return [] }
        return allWorkouts.filter { $0.userID == currentUser.appleUserID }
    }

    var body: some View {
        NavigationStack {
            if workouts.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(workouts) { workout in
                            NavigationLink(destination: EnhancedWorkoutDetailView(workout: workout)) {
                                WorkoutRow(workout: workout)
                            }
                            .id(workout.id)
                            .listRowBackground(
                                highlightedIDs.contains(workout.id)
                                    ? Color.blue.opacity(0.15)
                                    : nil
                            )
                        }
                        .onDelete(perform: deleteWorkouts)
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
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EditButton()
                        }
                    }
                    .onAppear {
                        processHighlight(proxy: proxy)
                    }
                    .onChange(of: highlightDate) { _, _ in
                        processHighlight(proxy: proxy)
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

    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(workouts[index])
        }
    }
}
