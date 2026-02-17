import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.currentUser) private var currentUser
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var themeViewModel: ThemeViewModel
    @EnvironmentObject var socialService: SocialService
    @State private var showingSignOutAlert = false
    @State private var usernameInput = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var saveError: String?
    @State private var showSuccessAlert = false
    @State private var isSaving = false

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

                // Username Section
                Section("Username") {
                    HStack {
                        TextField("Choose a username", text: $usernameInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: usernameInput) { _, newValue in
                                debounceTask?.cancel()

                                // Reset status if empty
                                if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                                    socialService.usernameStatus = .unchecked
                                    return
                                }

                                debounceTask = Task {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    if !Task.isCancelled {
                                        await socialService.checkUsernameAvailability(newValue)
                                    }
                                }
                            }

                        // Availability indicator
                        switch socialService.usernameStatus {
                        case .checking:
                            ProgressView()
                                .scaleEffect(0.8)
                        case .available:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .taken, .invalid:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        case .unchecked:
                            if !usernameInput.isEmpty && !socialService.errorMessage.isNilOrEmpty {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            } else {
                                EmptyView()
                            }
                        }
                    }

                    Button("Save Username") {
                        Task {
                            isSaving = true
                            saveError = nil

                            if let user = currentUser {
                                do {
                                    try await socialService.saveUsername(
                                        usernameInput,
                                        displayName: user.fullName ?? "User",
                                        context: modelContext
                                    )
                                    await MainActor.run {
                                        showSuccessAlert = true
                                        isSaving = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        saveError = error.localizedDescription
                                        isSaving = false
                                    }
                                }
                            } else {
                                await MainActor.run {
                                    saveError = "No user found"
                                    isSaving = false
                                }
                            }
                        }
                    }
                    .disabled(socialService.usernameStatus != .available || isSaving)

                    // Retry check when CloudKit check failed
                    if socialService.usernameStatus == .unchecked && !socialService.errorMessage.isNilOrEmpty {
                        Button("Retry Check") {
                            Task {
                                socialService.errorMessage = nil
                                await socialService.checkUsernameAvailability(usernameInput)
                            }
                        }
                        .foregroundColor(.blue)
                        .disabled(isSaving || usernameInput.count < 3)
                    }

                    Text("3-20 characters, letters/numbers/underscores")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if socialService.usernameStatus == .taken {
                        Text("Username already taken")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if socialService.usernameStatus == .invalid {
                        Text("Invalid username format")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if socialService.usernameStatus == .unchecked && !socialService.errorMessage.isNilOrEmpty {
                        Text(socialService.errorMessage ?? "Error checking username")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Privacy Section
                Section("Privacy") {
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.blue)
                            Text("Workout Privacy")
                            Spacer()
                            if let privacy = currentUser?.defaultPrivacy {
                                Text(privacyDisplayText(privacy))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Appearance Section
                Section("Appearance") {
                    Picker("Theme", selection: $themeViewModel.currentTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Choose your preferred theme or use system setting")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .onAppear {
                if let username = currentUser?.username, !username.isEmpty {
                    usernameInput = username
                } else if let cloudUsername = socialService.myProfile?["username"] as? String {
                    usernameInput = cloudUsername
                }
            }
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
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Username saved successfully!")
            }
            .alert("Error", isPresented: .constant(saveError != nil)) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "Unknown error")
            }
        }
    }

    private func privacyDisplayText(_ privacyString: String) -> String {
        if privacyString == "private" {
            return "Private"
        } else if WorkoutPrivacy.includesFriends(privacyString) && WorkoutPrivacy.includesTeam(privacyString) {
            return "Friends + Team"
        } else if WorkoutPrivacy.includesFriends(privacyString) {
            return "Friends"
        } else if WorkoutPrivacy.includesTeam(privacyString) {
            return "Team"
        } else {
            return "Friends"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
