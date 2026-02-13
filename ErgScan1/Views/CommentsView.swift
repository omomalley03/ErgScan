import SwiftUI
import CloudKit

struct CommentsView: View {
    let workoutID: String
    let workoutType: String
    let ownerUsername: String
    let workoutDate: Date
    let averageSplit: String
    let currentUserID: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var socialService: SocialService

    @State private var comments: [CommentInfo] = []
    @State private var newCommentText = ""
    @State private var chupInfo = ChupInfo(count: 0, currentUserChupped: false)
    @State private var isChupAnimating = false
    @State private var isBigChup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Workout header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(workoutType)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("— @\(ownerUsername)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        Text(workoutDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !averageSplit.isEmpty {
                            Text("Avg Split: \(averageSplit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Chup row
                    HStack {
                        Button {
                            Task { await toggleChup() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chupInfo.currentUserChupped ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .foregroundColor(chupInfo.currentUserChupped ? .blue : .secondary)
                                    .scaleEffect(isChupAnimating ? 1.3 : 1.0)
                                Text("Chup")
                                    .font(.subheadline)
                                    .foregroundColor(chupInfo.currentUserChupped ? .blue : .secondary)
                            }
                        }

                        if chupInfo.count > 0 {
                            Text(chupInfo.count == 1 ? "1 person gave a Chup" : "\(chupInfo.count) people gave a Chup")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Comments list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { comment in
                            CommentRow(
                                comment: comment,
                                onHeart: { Task { await heartComment(comment) } },
                                onProfileTap: {
                                    // Navigate to profile — handled by NavigationLink wrapping
                                }
                            )
                        }

                        if comments.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No comments yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Be the first to comment!")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding()
                }

                Divider()

                // Input bar
                HStack(spacing: 8) {
                    TextField("Add a comment...", text: $newCommentText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await postComment() }
                    } label: {
                        Text("Send")
                            .fontWeight(.semibold)
                            .foregroundColor(canSend ? .blue : .secondary)
                    }
                    .disabled(!canSend)
                }
                .padding()
            }
            .overlay {
                BigChupOverlay(isShowing: $isBigChup)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadData()
            }
        }
    }

    // MARK: - Computed

    private var canSend: Bool {
        !newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func loadData() async {
        chupInfo = await socialService.fetchChups(for: workoutID)
        comments = await socialService.fetchComments(for: workoutID)
    }

    private func toggleChup() async {
        let myUsername = socialService.myProfile?["username"] as? String ?? ""
        do {
            let result = try await socialService.toggleChup(
                workoutID: workoutID,
                userID: currentUserID,
                username: myUsername
            )
            chupInfo.currentUserChupped = result
            chupInfo.count += result ? 1 : -1
            if result {
                HapticService.shared.chupFeedback()
                withAnimation(.spring(response: 0.3)) { isChupAnimating = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isChupAnimating = false }
            }
        } catch {
            print("⚠️ Chup failed: \(error)")
        }
    }

    private func postComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let myUsername = socialService.myProfile?["username"] as? String ?? ""
        do {
            let comment = try await socialService.postComment(
                workoutID: workoutID,
                userID: currentUserID,
                username: myUsername,
                text: text
            )
            comments.append(comment)
            newCommentText = ""
            HapticService.shared.lightImpact()
        } catch {
            print("⚠️ Comment failed: \(error)")
        }
    }

    private func heartComment(_ comment: CommentInfo) async {
        do {
            let hearted = try await socialService.toggleCommentHeart(
                commentID: comment.id,
                userID: currentUserID
            )
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].currentUserHearted = hearted
                comments[index].heartCount += hearted ? 1 : -1
            }
            HapticService.shared.commentHeartFeedback()
        } catch {
            print("⚠️ Heart failed: \(error)")
        }
    }
}
