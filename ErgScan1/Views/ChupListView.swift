import SwiftUI

struct ChupListView: View {
    let workoutID: String
    @EnvironmentObject var socialService: SocialService
    @State private var chupUsers: [ChupUser] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if chupUsers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No chups yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(chupUsers) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName ?? user.username)
                                .font(.headline)
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if user.isBigChup {
                            Image(systemName: "hand.thumbsup.fill")
                                .foregroundColor(.yellow)
                                .font(.title3)
                        } else {
                            Image(systemName: "hand.thumbsup.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }
                    .listRowBackground(user.isBigChup ? Color.yellow.opacity(0.1) : nil)
                }
            }
        }
        .navigationTitle("Chups")
        .task {
            chupUsers = await socialService.fetchChupUsers(for: workoutID)
            isLoading = false
        }
    }
}
