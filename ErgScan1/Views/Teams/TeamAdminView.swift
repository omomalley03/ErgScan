import SwiftUI

struct TeamAdminView: View {
    let teamID: String
    @EnvironmentObject var teamService: TeamService

    var body: some View {
        Group {
            if teamService.pendingJoinRequests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("No pending requests")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(teamService.pendingJoinRequests) { request in
                        requestRow(request)
                    }
                }
            }
        }
        .navigationTitle("Join Requests")
        .task {
            await teamService.loadPendingJoinRequests(teamID: teamID)
        }
        .refreshable {
            await teamService.loadPendingJoinRequests(teamID: teamID)
        }
    }

    private func requestRow(_ request: TeamJoinRequest) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("@\(request.username)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(request.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text("Wants to join as")
                        .font(.caption)
                        .foregroundColor(.blue)
                    ForEach(request.roleList) { role in
                        Text(role.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task {
                        try? await teamService.rejectJoinRequest(membershipRecordName: request.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        try? await teamService.approveJoinRequest(membershipRecordName: request.id)
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
