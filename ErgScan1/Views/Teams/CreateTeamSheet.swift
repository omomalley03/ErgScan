import SwiftUI

struct CreateTeamSheet: View {
    let onCreated: () -> Void

    @EnvironmentObject var teamService: TeamService
    @Environment(\.dismiss) private var dismiss
    @State private var teamName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Create a Team")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("Team Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("e.g. CDPC Varsity", text: $teamName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                createTeam()
            } label: {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray)
                        .cornerRadius(14)
                } else {
                    Text("Create Team")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(teamName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(14)
                }
            }
            .disabled(teamName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .navigationTitle("Create Team")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createTeam() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                _ = try await teamService.createTeam(name: teamName.trimmingCharacters(in: .whitespaces))
                await MainActor.run {
                    isCreating = false
                    dismiss()
                    onCreated()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
