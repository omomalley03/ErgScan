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
    @StateObject private var themeViewModel = ThemeViewModel()
    @StateObject private var socialService = SocialService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Workout.self,
            Interval.self,
            BenchmarkWorkout.self,
            BenchmarkInterval.self,
            BenchmarkImage.self,
            Goal.self,
        ])

        // Try CloudKit first
        do {
            print("🔵 Attempting to create ModelContainer with CloudKit sync...")
            print("   Container: iCloud.com.omomalley03.ErgScan1")
            let cloudKitConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.omomalley03.ErgScan1")
            )
            let container = try ModelContainer(for: schema, configurations: [cloudKitConfig])
            print("✅ SUCCESS: ModelContainer created with CloudKit sync enabled!")
            print("   Your workouts WILL sync to iCloud")
            return container
        } catch {
            print("❌ CLOUDKIT SYNC FAILED!")
            print("   Error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Localized: \(error.localizedDescription)")
            print("🔄 Falling back to local-only storage...")
            print("⚠️  WARNING: Workouts will NOT sync to iCloud in this mode!")

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
        .environmentObject(themeViewModel)
        .environmentObject(socialService)
    }
}

// Wrapper view to handle authentication and pass modelContext to authService
struct ContentViewWrapper: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeViewModel: ThemeViewModel
    @EnvironmentObject var socialService: SocialService

    var body: some View {
        Group {
            // Authentication gate
            if case .authenticated(let user) = authService.authState {
                MainTabView()
                    .environment(\.currentUser, user)
                    .environmentObject(themeViewModel)
                    .onAppear {
                        socialService.setCurrentUser(user.appleUserID, context: modelContext)
                    }
            } else {
                AuthenticationView(authService: authService)
                    .environmentObject(themeViewModel)
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
