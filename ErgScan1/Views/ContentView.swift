import SwiftUI
import SwiftData

/// Main content view with tab navigation
struct ContentView: View {

    var body: some View {
        TabView {
            // Scanner tab
            ScannerView()
                .tabItem {
                    Label("Scanner", systemImage: "camera.fill")
                }

            // Workouts tab
            WorkoutListView()
                .tabItem {
                    Label("Workouts", systemImage: "list.bullet")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Workout.self, Interval.self])
}
