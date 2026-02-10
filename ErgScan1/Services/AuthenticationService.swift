import Foundation
import Combine
import AuthenticationServices
import SwiftUI
import SwiftData
import Security

class AuthenticationService: ObservableObject {
    @Published var authState: AuthState = .unauthenticated
    @Published var currentUser: User?
    @Published var errorMessage: String?

    enum AuthState {
        case unauthenticated
        case authenticating
        case authenticated(User)
        case error(String)
    }

    // Keychain keys for secure storage
    private let keychainService = "com.ergscan.ErgScan1"
    private let userIDKey = "appleUserID"

    private var modelContext: ModelContext?

    init() {
        checkExistingAuth()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Sign In

    func signInWithApple() {
        authState = .authenticating
        errorMessage = nil
    }

    @MainActor
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                await handleError("Invalid credential type")
                return
            }

            let userID = appleIDCredential.user
            let email = appleIDCredential.email
            let fullName = appleIDCredential.fullName

            // Save to keychain
            if !saveToKeychain(userID: userID) {
                await handleError("Failed to save credentials securely")
                return
            }

            // Create or find user in SwiftData
            await createOrFindUser(
                appleUserID: userID,
                email: email,
                fullName: fullName.map { formatName($0) }
            )

        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                await handleError("Sign in was canceled")
            } else {
                await handleError("Sign in failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func createOrFindUser(appleUserID: String, email: String?, fullName: String?) async {
        guard let context = modelContext else {
            await handleError("Database not available")
            return
        }

        do {
            // Try to find existing user
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate { user in
                    user.appleUserID == appleUserID
                }
            )

            let existingUsers = try context.fetch(descriptor)

            let user: User
            if let existingUser = existingUsers.first {
                // Update last sign-in date
                existingUser.lastSignInAt = Date()
                user = existingUser
                print("✅ Found existing user: \(appleUserID)")
            } else {
                // Create new user
                user = User(
                    appleUserID: appleUserID,
                    email: email,
                    fullName: fullName
                )
                context.insert(user)
                print("✅ Created new user: \(appleUserID)")

                // Clear orphaned local data for new user
                await handleFirstTimeSignIn(user: user, context: context)
            }

            try context.save()

            // Update state
            currentUser = user
            authState = .authenticated(user)
            errorMessage = nil

        } catch {
            await handleError("Failed to create user: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Existing Auth

    func checkExistingAuth() {
        guard let userID = loadFromKeychain() else {
            authState = .unauthenticated
            return
        }

        // Will authenticate once modelContext is set
        print("📱 Found saved credentials for user: \(userID)")
    }

    @MainActor
    func authenticateWithSavedCredentials() async {
        guard let userID = loadFromKeychain(),
              let context = modelContext else {
            authState = .unauthenticated
            return
        }

        do {
            let descriptor = FetchDescriptor<User>(
                predicate: #Predicate { user in
                    user.appleUserID == userID
                }
            )

            let existingUsers = try context.fetch(descriptor)

            if let user = existingUsers.first {
                user.lastSignInAt = Date()
                try context.save()

                currentUser = user
                authState = .authenticated(user)
                print("✅ Restored session for user: \(userID)")
            } else {
                // Credentials exist but user not in database - sign in again
                authState = .unauthenticated
                clearKeychain()
            }
        } catch {
            print("❌ Failed to restore session: \(error)")
            authState = .unauthenticated
        }
    }

    // MARK: - Sign Out

    @MainActor
    func signOut() async {
        clearKeychain()
        currentUser = nil
        authState = .unauthenticated
        errorMessage = nil
        print("👋 User signed out")
    }

    // MARK: - First Time Sign-In

    private func handleFirstTimeSignIn(user: User, context: ModelContext) async {
        // Skip cleanup for now - can cause issues with schema migration
        print("ℹ️ Skipping orphaned workout cleanup (first-time sign-in)")

        // Note: To properly clean up old data, delete the app and reinstall
    }

    // MARK: - Keychain

    private func saveToKeychain(userID: String) -> Bool {
        let data = userID.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIDKey,
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIDKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let userID = String(data: data, encoding: .utf8) else {
            return nil
        }

        return userID
    }

    private func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIDKey
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Helpers

    private func formatName(_ nameComponents: PersonNameComponents) -> String {
        let formatter = PersonNameComponentsFormatter()
        return formatter.string(from: nameComponents)
    }

    @MainActor
    private func handleError(_ message: String) async {
        errorMessage = message
        authState = .error(message)
        print("❌ Auth error: \(message)")
    }
}
