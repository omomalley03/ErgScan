import SwiftUI
import CloudKit

struct WorkoutFeedCard: View {
    let workout: any WorkoutDisplayable
    let showProfileHeader: Bool
    let currentUserID: String

    @EnvironmentObject var socialService: SocialService

    @State private var chupInfo = ChupInfo(totalCount: 0, regularCount: 0, bigChupCount: 0, currentUserChupType: .none)
    @State private var latestComment: CommentInfo? = nil
    @State private var commentCount: Int = 0
    @State private var showComments = false
    @State private var isChupAnimating = false
    @State private var isBigChup = false
    @State private var isChupInProgress = false

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

            // Coxswain tag
            if let coxUsername = workout.displaySubmittedByCox {
                Text("Submitted by @\(coxUsername)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)
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
                    guard !isChupInProgress else { return }
                    isChupInProgress = true
                    Task {
                        defer { isChupInProgress = false }
                        let myUsername = socialService.myProfile?["username"] as? String ?? ""
                        let previousChupInfo = chupInfo
                        do {
                            let newType = try await socialService.toggleChup(
                                workoutID: workout.workoutRecordID,
                                userID: currentUserID,
                                username: myUsername,
                                isBigChup: false
                            )
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    chupInfo.applyCurrentUserTransition(to: newType)
                                }
                            }
                            if newType != .none {
                                HapticService.shared.chupFeedback()
                                withAnimation(.spring(response: 0.3)) { isChupAnimating = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isChupAnimating = false }
                            }
                        } catch {
                            await MainActor.run {
                                chupInfo = previousChupInfo
                            }
                            print("⚠️ Chup failed: \(error)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: chupInfo.currentUserChupType != .none ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundColor(
                                chupInfo.currentUserChupType == .big ? .yellow :
                                chupInfo.currentUserChupType == .regular ? .blue :
                                .secondary
                            )
                            .scaleEffect(isChupAnimating ? 1.3 : 1.0)
                        Text("Chup")
                            .font(.subheadline)
                            .foregroundColor(
                                chupInfo.currentUserChupType == .big ? .yellow :
                                chupInfo.currentUserChupType == .regular ? .blue :
                                .secondary
                            )
                    }
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            guard !isChupInProgress else { return }
                            isChupInProgress = true
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                                isBigChup = true
                            }
                            HapticService.shared.bigChupFeedback()
                            Task {
                                defer { isChupInProgress = false }
                                let myUsername = socialService.myProfile?["username"] as? String ?? ""
                                let previousChupInfo = chupInfo
                                do {
                                    let newType = try await socialService.toggleChup(
                                        workoutID: workout.workoutRecordID,
                                        userID: currentUserID,
                                        username: myUsername,
                                        isBigChup: true
                                    )
                                    await MainActor.run {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            chupInfo.applyCurrentUserTransition(to: newType)
                                        }
                                    }
                                } catch {
                                    await MainActor.run {
                                        chupInfo = previousChupInfo
                                    }
                                    print("⚠️ Big chup failed: \(error)")
                                }
                            }
                        }
                )

                if chupInfo.totalCount > 0 {
                    Text(chupCountText)
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

    // MARK: - Helpers

    private var chupCountText: String {
        if chupInfo.totalCount == 0 { return "" }

        var parts: [String] = []
        if chupInfo.regularCount > 0 {
            parts.append("\(chupInfo.regularCount) Chup\(chupInfo.regularCount == 1 ? "" : "s")")
        }
        if chupInfo.bigChupCount > 0 {
            parts.append("\(chupInfo.bigChupCount) Big Chup\(chupInfo.bigChupCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " and ")
    }

    // MARK: - Data Loading

    private func loadChupAndCommentData() async {
        // Load chups (always needed for the button state)
        chupInfo = await socialService.fetchChups(for: workout.workoutRecordID)

        // Only fetch comment count + latest preview (not full comments)
        // Full comments are loaded lazily when user taps the comment button
        let comments = await socialService.fetchComments(for: workout.workoutRecordID)
        commentCount = comments.count
        latestComment = comments.last
    }
}
