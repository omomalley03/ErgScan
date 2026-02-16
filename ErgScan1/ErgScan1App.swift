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
    @StateObject private var teamService = TeamService()
    @StateObject private var assignmentService = AssignmentService()
    @StateObject private var cacheService = SocialCacheService()

    var sharedModelContainer: ModelContainer = {
        // Schema 1: Personal data — syncs to CloudKit private DB
        let personalSchema = Schema([
            User.self,
            Workout.self,
            Interval.self,
            BenchmarkWorkout.self,
            BenchmarkInterval.self,
            BenchmarkImage.self,
            Goal.self,
        ])

        // Schema 2: Social cache — strictly local, NEVER syncs to CloudKit
        let cacheSchema = Schema([
            CachedSharedWorkout.self,
            CachedFriend.self,
            CachedTeam.self,
            CachedTeamMembership.self,
            SyncMetadata.self,
        ])

        // Combined schema (union of both)
        let fullSchema = Schema([
            User.self,
            Workout.self,
            Interval.self,
            BenchmarkWorkout.self,
            BenchmarkInterval.self,
            BenchmarkImage.self,
            Goal.self,
            CachedSharedWorkout.self,
            CachedFriend.self,
            CachedTeam.self,
            CachedTeamMembership.self,
            SyncMetadata.self,
        ])

        // Try CloudKit + local cache dual configuration
        do {
            print("🔵 Attempting to create ModelContainer with CloudKit sync + local cache...")
            print("   Container: iCloud.com.omomalley03.ErgScan1")

            let cloudKitConfig = ModelConfiguration(
                "PersonalData",
                schema: personalSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.omomalley03.ErgScan1")
            )

            let cacheConfig = ModelConfiguration(
                "SocialCache",
                schema: cacheSchema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )

            let container = try ModelContainer(for: fullSchema, configurations: [cloudKitConfig, cacheConfig])
            print("✅ SUCCESS: Dual ModelContainer created (CloudKit + local cache)")
            return container
        } catch {
            print("❌ DUAL CONTAINER FAILED: \(error)")
            print("🔄 Falling back to local-only storage for everything...")

            // Fallback to local-only for all models
            do {
                let localConfig = ModelConfiguration(
                    schema: personalSchema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                let cacheConfig = ModelConfiguration(
                    "SocialCache",
                    schema: cacheSchema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(for: fullSchema, configurations: [localConfig, cacheConfig])
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
        .environmentObject(teamService)
        .environmentObject(assignmentService)
        .environmentObject(cacheService)
    }
}

// Wrapper view to handle authentication and pass modelContext to authService
struct ContentViewWrapper: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var themeViewModel: ThemeViewModel
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var teamService: TeamService
    @EnvironmentObject var assignmentService: AssignmentService
    @EnvironmentObject var cacheService: SocialCacheService

    var body: some View {
        Group {
            // Authentication gate
            if case .authenticated(let user) = authService.authState {
                if user.isOnboarded {
                    MainTabView()
                        .environment(\.currentUser, user)
                        .environmentObject(themeViewModel)
                        .onAppear {
                            configureCacheAndServices(user: user)
                        }
                } else {
                    OnboardingContainerView()
                        .environment(\.currentUser, user)
                        .environmentObject(themeViewModel)
                        .onAppear {
                            configureCacheAndServices(user: user)
                        }
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

    private func configureCacheAndServices(user: User) {
        // Configure cache service with modelContext
        cacheService.configure(context: modelContext, userID: user.appleUserID)

        // Inject cache into services
        socialService.cacheService = cacheService
        teamService.cacheService = cacheService

        // Set up services (will now load cache first, then background sync)
        socialService.setCurrentUser(user.appleUserID, context: modelContext)
        teamService.setCurrentUser(user.appleUserID, context: modelContext)
        assignmentService.setCurrentUser(userID: user.appleUserID, username: user.username ?? "")
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
