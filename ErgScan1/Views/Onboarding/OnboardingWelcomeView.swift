import SwiftUI

struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "figure.rowing")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Welcome to ErgScan")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track your rowing workouts, connect with teammates, and see your progress over time.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                onContinue()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}
