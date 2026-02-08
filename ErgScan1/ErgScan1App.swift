//
//  ErgScan1App.swift
//  ErgScan1
//
//  Created by Owen O'Malley on 2/7/26.
//

import SwiftUI
import SwiftData

@main
struct ErgScan1App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Workout.self,
            Interval.self,
            BenchmarkWorkout.self,
            BenchmarkInterval.self,
            BenchmarkImage.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
