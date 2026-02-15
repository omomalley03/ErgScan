import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Environment(\.currentUser) private var currentUser
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var socialService: SocialService
    @EnvironmentObject var teamService: TeamService

    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedRoles: Set<UserRole> = []

    // Username fields (for users who don't have one yet)
    @State private var usernameInput = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var isSavingUsername = false
    @State private var usernameSaveError: String?

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case username = 1
        case roleSelection = 2
        case teamSetup = 3
    }

    private var hasUsername: Bool {
        currentUser?.username != nil && !(currentUser?.username?.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .welcome:
                    OnboardingWelcomeView {
                        withAnimation(.easeInOut) {
                            if hasUsername {
                                currentStep = .roleSelection
                            } else {
                                currentStep = .username
                            }
                        }
                    }

                case .username:
                    usernameSetupView

                case .roleSelection:
                    OnboardingRoleSelectionView(selectedRoles: $selectedRoles) {
                        saveRoles()
                        withAnimation(.easeInOut) {
                            currentStep = .teamSetup
                        }
                    }

                case .teamSetup:
                    OnboardingTeamSetupView(
                        selectedRoles: selectedRoles,
                        onComplete: { completeOnboarding() },
                        onSkip: { completeOnboarding() }
                    )
                }
            }
        }
    }

    // MARK: - Username Setup View

    private var usernameSetupView: some View {
        VStack(spacing: 24) {
            Text("Choose a Username")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 40)

            Text("This is how teammates and friends will find you")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 8) {
                HStack {
                    Text("@")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    TextField("username", text: $usernameInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: usernameInput) { _, newValue in
                            debounceTask?.cancel()
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
                        EmptyView()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal)

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
                }

                if let error = usernameSaveError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button {
                saveUsername()
            } label: {
                if isSavingUsername {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .cornerRadius(14)
                } else {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(socialService.usernameStatus == .available ? Color.blue : Color.gray)
                        .cornerRadius(14)
                }
            }
            .disabled(socialService.usernameStatus != .available || isSavingUsername)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    private func saveUsername() {
        guard let user = currentUser else { return }
        isSavingUsername = true
        usernameSaveError = nil

        Task {
            do {
                try await socialService.saveUsername(
                    usernameInput,
                    displayName: user.fullName ?? "User",
                    context: modelContext
                )
                await MainActor.run {
                    isSavingUsername = false
                    withAnimation(.easeInOut) {
                        currentStep = .roleSelection
                    }
                }
            } catch {
                await MainActor.run {
                    usernameSaveError = error.localizedDescription
                    isSavingUsername = false
                }
            }
        }
    }

    private func saveRoles() {
        guard !selectedRoles.isEmpty, let user = currentUser else { return }
        let csv = UserRole.toCSV(selectedRoles)
        user.role = csv
        try? modelContext.save()
        Task {
            await socialService.updateProfileRole(csv)
        }
    }

    private func completeOnboarding() {
        guard let user = currentUser else { return }
        user.isOnboarded = true
        try? modelContext.save()
    }
}
