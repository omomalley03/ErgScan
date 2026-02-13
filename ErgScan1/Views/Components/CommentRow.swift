import SwiftUI

struct CommentRow: View {
    let comment: CommentInfo
    let onHeart: () -> Void
    let onProfileTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Profile icon (tappable)
            Button(action: onProfileTap) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button(action: onProfileTap) {
                        Text("@\(comment.username)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)

                    Text(relativeTime(from: comment.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(comment.text)
                    .font(.body)
            }

            Spacer()

            // Heart button
            Button(action: onHeart) {
                VStack(spacing: 2) {
                    Image(systemName: comment.currentUserHearted ? "heart.fill" : "heart")
                        .font(.subheadline)
                        .foregroundColor(comment.currentUserHearted ? .red : .secondary)
                    if comment.heartCount > 0 {
                        Text("\(comment.heartCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
