import SwiftUI

struct PrivateProfilePlaceholder: View {
    let relationship: ProfileRelationship
    let onSendRequest: () -> Void
    let onAcceptRequest: () -> Void
    let onDeclineRequest: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Private Profile")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Send a friend request to see their workouts")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            switch relationship {
            case .notFriends:
                Button {
                    HapticService.shared.lightImpact()
                    onSendRequest()
                } label: {
                    Text("Add Friend")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(10)
                }

            case .requestSentByMe:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                    Text("Request Sent")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)

            case .requestSentToMe:
                HStack(spacing: 12) {
                    Button {
                        HapticService.shared.lightImpact()
                        onDeclineRequest()
                    } label: {
                        Text("Decline")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                    }

                    Button {
                        HapticService.shared.lightImpact()
                        onAcceptRequest()
                    } label: {
                        Text("Accept Request")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                }

            case .friends:
                EmptyView() // Should never be shown
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .padding()
    }
}
