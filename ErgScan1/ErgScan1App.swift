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
    @StateObject private var authService = AuthenticationService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Workout.self,
            Interval.self,
            BenchmarkWorkout.self,
            BenchmarkInterval.self,
            BenchmarkImage.self,
        ])

        // Try CloudKit first
        do {
            let cloudKitConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.omomalley03.ErgScan1")
            )
            let container = try ModelContainer(for: schema, configurations: [cloudKitConfig])
            print("✅ ModelContainer created with CloudKit sync enabled!")
            return container
        } catch {
            print("⚠️ CloudKit failed: \(error)")
            print("🔄 Falling back to local-only storage...")

            // Fallback to local-only
            do {
                let localConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(for: schema, configurations: [localConfig])
                print("✅ ModelContainer created in LOCAL-ONLY mode (no sync)")
                return container
            } catch {
                print("❌ Fatal: Could not create ModelContainer: \(error)")
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentViewWrapper(authService: authService)
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(authService)
    }
}

// Wrapper view to handle authentication and pass modelContext to authService
struct ContentViewWrapper: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            // Authentication gate
            if case .authenticated(let user) = authService.authState {
                ContentView()
                    .environment(\.currentUser, user)
            } else {
                AuthenticationView(authService: authService)
            }
        }
        .onAppear {
            // Pass modelContext to authService for database operations
            authService.setModelContext(modelContext)

            // Attempt to restore session from keychain
            Task {
                await authService.authenticateWithSavedCredentials()
            }
        }
    }
}

// MARK: - Custom Environment Key for Current User

private struct CurrentUserKey: EnvironmentKey {
    static let defaultValue: User? = nil
}

extension EnvironmentValues {
    var currentUser: User? {
        get { self[CurrentUserKey.self] }
        set { self[CurrentUserKey.self] = newValue }
    }
}
