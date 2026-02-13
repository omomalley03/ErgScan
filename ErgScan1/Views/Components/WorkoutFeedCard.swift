import SwiftUI
import CloudKit

struct WorkoutFeedCard: View {
    let workout: any WorkoutDisplayable
    let showProfileHeader: Bool
    let currentUserID: String

    @EnvironmentObject var socialService: SocialService

    @State private var chupInfo = ChupInfo(count: 0, currentUserChupped: false)
    @State private var latestComment: CommentInfo? = nil
    @State private var commentCount: Int = 0
    @State private var showComments = false
    @State private var isChupAnimating = false
    @State private var isBigChup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile header
            if showProfileHeader {
                profileHeader
            }

            // Workout type + zone tag
            HStack(spacing: 8) {
                Text(workout.displayWorkoutType)
                    .font(.headline)
                    .fontWeight(.bold)

                if let zone = workout.displayIntensityZone {
                    ZoneTag(zone: zone)
                }

                if workout.displayIsErgTest {
                    Image(systemName: "flag.checkered")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Stats grid
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    if !workout.displayTotalTime.isEmpty {
                        statRow(label: "Time", value: workout.displayTotalTime)
                    }
                    if workout.displayTotalDistance > 0 {
                        statRow(label: "Distance", value: "\(workout.displayTotalDistance)m")
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if !workout.displayAverageSplit.isEmpty {
                        statRow(label: "Avg Split", value: workout.displayAverageSplit)
                    }
                }
            }

            Divider()

            // Chup + Comment row
            HStack {
                // Chup button
                Button {
                    Task {
                        let myUsername = socialService.myProfile?["username"] as? String ?? ""
                        do {
                            let result = try await socialService.toggleChup(
                                workoutID: workout.workoutRecordID,
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
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 1.0)
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                                isBigChup = true
                            }
                            HapticService.shared.bigChupFeedback()
                            // Also toggle chup if not already chupped
                            if !chupInfo.currentUserChupped {
                                Task {
                                    let myUsername = socialService.myProfile?["username"] as? String ?? ""
                                    let result = try? await socialService.toggleChup(
                                        workoutID: workout.workoutRecordID,
                                        userID: currentUserID,
                                        username: myUsername
                                    )
                                    if let result, result {
                                        chupInfo.currentUserChupped = true
                                        chupInfo.count += 1
                                    }
                                }
                            }
                        }
                )

                if chupInfo.count > 0 {
                    Text(chupInfo.count == 1 ? "1 Chup" : "\(chupInfo.count) Chups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Comment button
                Button {
                    showComments = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundColor(.secondary)
                        if commentCount > 0 {
                            Text("\(commentCount)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Comment preview
            if let comment = latestComment {
                Button { showComments = true } label: {
                    HStack(spacing: 4) {
                        Text("\"\(comment.text)\"")
                            .lineLimit(1)
                        Text("— @\(comment.username)")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .foregroundColor(.primary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            BigChupOverlay(isShowing: $isBigChup)
        }
        .sheet(isPresented: $showComments) {
            CommentsView(
                workoutID: workout.workoutRecordID,
                workoutType: workout.displayWorkoutType,
                ownerUsername: workout.displayUsername,
                workoutDate: workout.displayDate,
                averageSplit: workout.displayAverageSplit,
                currentUserID: currentUserID
            )
        }
        .task {
            await loadChupAndCommentData()
        }
    }

    // MARK: - Subviews

    private var profileHeader: some View {
        NavigationLink(destination: FriendProfileView(
            userID: workout.ownerUserID,
            username: workout.displayUsername,
            displayName: workout.displayName
        )) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.displayName.isEmpty ? "@\(workout.displayUsername)" : workout.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(workout.displayDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    // MARK: - Data Loading

    private func loadChupAndCommentData() async {
        chupInfo = await socialService.fetchChups(for: workout.workoutRecordID)

        let comments = await socialService.fetchComments(for: workout.workoutRecordID)
        commentCount = comments.count
        latestComment = comments.last
    }
}
