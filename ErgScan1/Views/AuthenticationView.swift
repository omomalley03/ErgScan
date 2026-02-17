import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @ObservedObject var authService: AuthenticationService

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App branding
            Image("figure.rowing")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)

            Text("Argo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Scan your erg screens, track your workouts, and connect with teammates.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Sign in with Apple button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task {
                    await authService.handleSignInResult(result)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

            // Error message
            if let error = authService.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Info text
            Text("Your workouts sync automatically across all your Apple devices")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Loading indicator
            if case .authenticating = authService.authState {
                ProgressView()
                    .padding()
            }
        }
        .padding()
    }
}

#Preview {
    AuthenticationView(authService: AuthenticationService())
}
