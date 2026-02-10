import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.currentUser) private var currentUser
    @EnvironmentObject var authService: AuthenticationService
    @State private var showingSignOutAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    if let user = currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.fullName ?? "User")
                                    .font(.headline)

                                if let email = user.email {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Text("Signed in with Apple")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Sync Section
                Section("iCloud Sync") {
                    HStack {
                        Image(systemName: "icloud")
                        Text("Sync Status")
                        Spacer()
                        Text("Active")
                            .foregroundColor(.green)
                    }

                    Text("Your workouts sync across all your Apple devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                // Sign Out
                Section {
                    Button(role: .destructive) {
                        showingSignOutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authService.signOut()
                    }
                }
            } message: {
                Text("Your workouts will remain in iCloud and sync when you sign in again.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
}
