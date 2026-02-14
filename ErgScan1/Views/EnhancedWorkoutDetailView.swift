import SwiftUI
import CloudKit

struct UnifiedWorkoutDetailView: View {
    let workout: any WorkoutDisplayable
    let localWorkout: Workout?
    let isOwnWorkout: Bool
    let currentUserID: String

    @EnvironmentObject var socialService: SocialService

    // UI state
    @State private var currentIntervalIndex = 0
    @State private var showSwipeHint = true
    @State private var showImageViewer = false
    @State private var showEditSheet = false

    // Social state
    @State private var resolvedWorkoutRecordID: String?
    @State private var chupInfo = ChupInfo(count: 0, currentUserChupped: false)
    @State private var comments: [CommentInfo] = []
    @State private var isChupAnimating = false
    @State private var isBigChup = false
    @State private var newCommentText = ""
    @State private var fetchedDetail: SocialService.WorkoutDetailResult?

    // Convenience init for own workout (from Log)
    init(localWorkout: Workout, currentUserID: String) {
        self.workout = localWorkout
        self.localWorkout = localWorkout
        self.isOwnWorkout = true
        self.currentUserID = currentUserID
    }

    // Convenience init for shared workout (from Dashboard / FriendProfile)
    init(sharedWorkout: SocialService.SharedWorkoutResult, currentUserID: String) {
        self.workout = sharedWorkout
        self.localWorkout = nil
        self.isOwnWorkout = sharedWorkout.ownerID == currentUserID
        self.currentUserID = currentUserID
    }

    // MARK: - Computed

    private var sortedIntervals: [Interval] {
        (localWorkout?.intervals ?? [])
            .filter { $0.orderIndex >= 1 }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private var averagesInterval: Interval? {
        (localWorkout?.intervals ?? []).first(where: { $0.orderIndex == 0 })
    }

    private var effectiveWorkoutRecordID: String? {
        if localWorkout != nil {
            return resolvedWorkoutRecordID
        } else {
            return workout.workoutRecordID
        }
    }

    // MARK: - Friend Workout Data Processing

    /// Process friend workout intervals into ViewModels
    private var friendIntervalViewModels: [IntervalViewModel] {
        guard let intervals = fetchedDetail?.intervals else { return [] }
        return intervals.compactMap { IntervalViewModel(from: $0) }
    }

    /// Extract averages (orderIndex == 0) for summary
    private var friendAveragesViewModel: IntervalViewModel? {
        friendIntervalViewModels.first(where: { $0.orderIndex == 0 })
    }

    /// Extract actual intervals/splits (orderIndex >= 1)
    private var friendSortedIntervals: [IntervalViewModel] {
        friendIntervalViewModels
            .filter { $0.orderIndex >= 1 }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    /// Determine workout category from workoutType string
    private var friendWorkoutCategory: WorkoutCategory {
        let type = workout.displayWorkoutType
        // Interval workouts contain "x" and "/" (e.g., "3x4:00/3:00r")
        if type.contains("x") && type.contains("/") {
            return .interval
        }
        // Single workouts are distance/time based (e.g., "2000m", "20:00")
        return .single
    }

    /// Find fastest interval for highlighting
    private var friendFastestInterval: IntervalViewModel? {
        friendSortedIntervals.min { parseTime($0.time) < parseTime($1.time) }
    }

    /// Find slowest interval for highlighting
    private var friendSlowestInterval: IntervalViewModel? {
        friendSortedIntervals.max { parseTime($0.time) < parseTime($1.time) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Friend identity header
                if !isOwnWorkout {
                    friendIdentityHeader
                }

                // 2. Erg image (own workout only)
                savedImageView

                // 3. Summary card
                summarySection

                // 4. Chup + comment bar
                if effectiveWorkoutRecordID != nil {
                    socialBar
                }

                // 5. Splits / Intervals (own workout only)
                intervalsContent

                // 6. Inline comments section
                if effectiveWorkoutRecordID != nil {
                    commentsSection
                }
            }
            .padding(.bottom, 80)
        }
        .overlay {
            BigChupOverlay(isShowing: $isBigChup)
        }
        .navigationTitle(workout.displayWorkoutType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isOwnWorkout && localWorkout != nil {
                    Button("Edit") {
                        showEditSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showImageViewer) {
            imageViewerSheet
        }
        .sheet(isPresented: $showEditSheet) {
            if let lw = localWorkout {
                NavigationStack {
                    EditWorkoutView(workout: lw)
                }
            }
        }
        .task {
            // Resolve CloudKit record ID for own workouts
            if let lw = localWorkout {
                resolvedWorkoutRecordID = await socialService.resolveSharedWorkoutRecordID(
                    localWorkoutID: lw.id.uuidString
                )
            }
            // Fetch full workout detail for friend workouts
            if !isOwnWorkout, !workout.workoutRecordID.isEmpty {
                fetchedDetail = await socialService.fetchWorkoutDetail(sharedWorkoutID: workout.workoutRecordID)
            }
            // Load social data
            if let wid = effectiveWorkoutRecordID {
                chupInfo = await socialService.fetchChups(for: wid)
                comments = await socialService.fetchComments(for: wid)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { showSwipeHint = false }
            }
        }
    }

    // MARK: - Friend Identity Header

    private var friendIdentityHeader: some View {
        NavigationLink(destination: FriendProfileView(
            userID: workout.ownerUserID,
            username: workout.displayUsername,
            displayName: workout.displayName
        )) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.body)
                            .foregroundColor(.blue)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.displayName.isEmpty ? "@\(workout.displayUsername)" : workout.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("@\(workout.displayUsername) \u{00B7} \(workout.displayDate, style: .date)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image

    @ViewBuilder
    private var savedImageView: some View {
        // Show local image for own workouts
        if let imageData = localWorkout?.imageData,
           let uiImage = UIImage(data: imageData) {
            ergImageDisplay(uiImage)
        }
        // Show fetched image for friend workouts
        else if let imageData = fetchedDetail?.ergImageData,
                let uiImage = UIImage(data: imageData) {
            ergImageDisplay(uiImage)
        }
    }

    private func ergImageDisplay(_ uiImage: UIImage) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 200)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .onTapGesture { showImageViewer = true }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(8)
            }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        if let averages = averagesInterval, let lw = localWorkout {
            // Own workout: use Interval directly
            AveragesSummaryCard(interval: averages, category: lw.category, date: lw.date, intensityZone: lw.zone)
        } else if let friendAverages = friendAveragesViewModel {
            // Friend workout: use IntervalViewModel from JSON
            AveragesSummaryCard(
                interval: friendAverages,
                category: friendWorkoutCategory,
                date: workout.displayDate,
                intensityZone: workout.displayIntensityZone
            )
        } else {
            // Fallback: generic summary from WorkoutDisplayable
            displayableSummaryCard
        }
    }

    private var displayableSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUMMARY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                if let zone = workout.displayIntensityZone {
                    Text(zone.displayName)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(zone.color.opacity(0.8)))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(workout.displayDate, style: .date)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if !workout.displayTotalTime.isEmpty {
                        DataRow(label: "Time", value: workout.displayTotalTime)
                    }
                    if workout.displayTotalDistance > 0 {
                        DataRow(label: "Distance", value: "\(workout.displayTotalDistance)m")
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if !workout.displayAverageSplit.isEmpty {
                        DataRow(label: "Split", value: workout.displayAverageSplit)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }

    // MARK: - Social Bar (Chups + Comments)

    private var socialBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Chup button
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
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 1.0)
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                                isBigChup = true
                            }
                            HapticService.shared.bigChupFeedback()
                            if !chupInfo.currentUserChupped {
                                Task {
                                    let myUsername = socialService.myProfile?["username"] as? String ?? ""
                                    if let wid = effectiveWorkoutRecordID,
                                       let result = try? await socialService.toggleChup(workoutID: wid, userID: currentUserID, username: myUsername),
                                       result {
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

                // Comment count
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(.secondary)
                    if !comments.isEmpty {
                        Text("\(comments.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Splits / Intervals

    @ViewBuilder
    private var intervalsContent: some View {
        // Show local intervals for own workouts
        if let lw = localWorkout {
            if lw.category == .interval && !sortedIntervals.isEmpty {
                intervalCardsView
                PageIndicator(currentPage: currentIntervalIndex, totalPages: sortedIntervals.count)
                swipeHintView
            } else if !sortedIntervals.isEmpty {
                SplitsListView(
                    intervals: sortedIntervals,
                    workoutType: lw.workoutType,
                    fastestId: fastestInterval?.id,
                    slowestId: slowestInterval?.id
                )
            }
        }
        // Show friend intervals with same components
        else if !friendSortedIntervals.isEmpty {
            if friendWorkoutCategory == .interval {
                friendIntervalCardsView
                PageIndicator(currentPage: currentIntervalIndex, totalPages: friendSortedIntervals.count)
                swipeHintView
            } else {
                SplitsListView(
                    intervals: friendSortedIntervals,
                    workoutType: workout.displayWorkoutType,
                    fastestId: friendFastestInterval?.id,
                    slowestId: friendSlowestInterval?.id
                )
            }
        }
    }

    private var intervalCardsView: some View {
        TabView(selection: $currentIntervalIndex) {
            ForEach(Array(sortedIntervals.enumerated()), id: \.element.id) { index, interval in
                IntervalCardView(
                    interval: interval,
                    number: index + 1,
                    total: sortedIntervals.count,
                    isFastest: interval.id == fastestInterval?.id,
                    isSlowest: interval.id == slowestInterval?.id
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 450)
        .onChange(of: currentIntervalIndex) { _, _ in
            HapticService.shared.lightImpact()
        }
    }

    /// Swipeable interval cards for friend workouts
    private var friendIntervalCardsView: some View {
        TabView(selection: $currentIntervalIndex) {
            ForEach(Array(friendSortedIntervals.enumerated()), id: \.element.id) { index, interval in
                IntervalCardView(
                    interval: interval,
                    number: index + 1,
                    total: friendSortedIntervals.count,
                    isFastest: interval.id == friendFastestInterval?.id,
                    isSlowest: interval.id == friendSlowestInterval?.id
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 450)
        .onChange(of: currentIntervalIndex) { _, _ in
            HapticService.shared.lightImpact()
        }
    }

    @ViewBuilder
    private var swipeHintView: some View {
        if showSwipeHint && sortedIntervals.count > 1 {
            Text("← Swipe to navigate →")
                .font(.caption)
                .foregroundColor(.secondary)
                .transition(.opacity)
        }
    }

    // MARK: - Inline Comments Section

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMMENTS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            if comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("No comments yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(comments) { comment in
                    CommentRow(
                        comment: comment,
                        onHeart: { Task { await heartComment(comment) } },
                        onProfileTap: {}
                    )
                }
            }

            // Comment input
            HStack(spacing: 8) {
                TextField("Add a comment...", text: $newCommentText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await postComment() }
                } label: {
                    Text("Send")
                        .fontWeight(.semibold)
                        .foregroundColor(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .blue)
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }

    // MARK: - Image Viewer Sheet

    @ViewBuilder
    private var imageViewerSheet: some View {
        // Show local image for own workouts
        if let imageData = localWorkout?.imageData,
           let uiImage = UIImage(data: imageData) {
            FullScreenImageViewer(image: uiImage, workoutType: workout.displayWorkoutType)
        }
        // Show fetched image for friend workouts
        else if let imageData = fetchedDetail?.ergImageData,
                let uiImage = UIImage(data: imageData) {
            FullScreenImageViewer(image: uiImage, workoutType: workout.displayWorkoutType)
        }
    }

    // MARK: - Helpers

    private var fastestInterval: Interval? {
        sortedIntervals.min { parseTime($0.time) < parseTime($1.time) }
    }

    private var slowestInterval: Interval? {
        sortedIntervals.max { parseTime($0.time) < parseTime($1.time) }
    }

    private func parseTime(_ timeString: String) -> Double {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]) else { return 0 }
        return minutes * 60 + seconds
    }

    // MARK: - Social Actions

    private func toggleChup() async {
        guard let wid = effectiveWorkoutRecordID else { return }
        let myUsername = socialService.myProfile?["username"] as? String ?? ""
        do {
            let result = try await socialService.toggleChup(workoutID: wid, userID: currentUserID, username: myUsername)
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
        guard !text.isEmpty, let wid = effectiveWorkoutRecordID else { return }
        let myUsername = socialService.myProfile?["username"] as? String ?? ""
        do {
            let comment = try await socialService.postComment(workoutID: wid, userID: currentUserID, username: myUsername, text: text)
            comments.append(comment)
            newCommentText = ""
            HapticService.shared.lightImpact()
        } catch {
            print("⚠️ Comment failed: \(error)")
        }
    }

    private func heartComment(_ comment: CommentInfo) async {
        do {
            let hearted = try await socialService.toggleCommentHeart(commentID: comment.id, userID: currentUserID)
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


// MARK: - Supporting Components

struct AveragesSummaryCard: View {
    let interval: any DisplayableInterval
    let category: WorkoutCategory?
    let date: Date
    let intensityZone: IntensityZone?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SUMMARY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                if let zone = intensityZone {
                    Text(zone.displayName)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(zone.color.opacity(0.8)))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(date, style: .date)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    DataRow(label: "Time", value: interval.time)
                    DataRow(label: "Distance", value: "\(interval.meters)m")
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    DataRow(label: "Split", value: interval.splitPer500m)
                    DataRow(label: "Rate", value: "\(interval.strokeRate) s/m")
                    if let hr = interval.heartRate {
                        DataRow(label: "HR", value: "\(hr) bpm")
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }
}

struct DataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

struct IntervalCardView: View {
    let interval: any DisplayableInterval
    let number: Int
    let total: Int
    let isFastest: Bool
    let isSlowest: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("INTERVAL \(number) of \(total)")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                if isFastest {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.green)
                }
                if isSlowest {
                    Image(systemName: "tortoise.fill")
                        .foregroundColor(.red)
                }
            }

            Divider()

            // Data fields
            VStack(spacing: 16) {
                LargeDataField(label: "Time", value: interval.time)
                LargeDataField(label: "Distance", value: "\(interval.meters)m")
                LargeDataField(label: "Split", value: interval.splitPer500m, suffix: "/500m")
                LargeDataField(label: "Rate", value: interval.strokeRate, suffix: "s/m")

                if let hr = interval.heartRate {
                    LargeDataField(label: "Heart Rate", value: hr, suffix: "bpm")
                }
            }

            Spacer()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackgroundColor)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.horizontal)
    }

    private var cardBackgroundColor: Color {
        if isFastest {
            return Color.green.opacity(0.1)
        } else if isSlowest {
            return Color.red.opacity(0.1)
        } else {
            return Color(.systemBackground)
        }
    }

}

struct LargeDataField: View {
    let label: String
    let value: String
    let suffix: String?

    init(label: String, value: String, suffix: String? = nil) {
        self.label = label
        self.value = value
        self.suffix = suffix
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Spacer()

            HStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                if let suffix = suffix {
                    Text(suffix)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct SplitsListView: View {
    let intervals: [any DisplayableInterval]
    let workoutType: String
    let fastestId: UUID?
    let slowestId: UUID?

    private var isDistanceBased: Bool {
        // Check if workout type ends with "m" (e.g., "2000m", "5000m")
        workoutType.trimmingCharacters(in: .whitespaces).hasSuffix("m")
    }

    private var splitInterval: String {
        guard let firstInterval = intervals.first else {
            return "500m"  // Default fallback
        }

        if isDistanceBased {
            // Distance-based split (e.g., "400" -> "400m")
            if let metersValue = Int(firstInterval.meters.trimmingCharacters(in: .whitespaces)),
               metersValue > 0 {
                return "\(metersValue)m"
            }
            return "500m"  // Default distance split
        } else {
            // Time-based split (e.g., "6:00.0" -> "6:00")
            let timeValue = firstInterval.time.trimmingCharacters(in: .whitespaces)
            // Remove trailing .0 or decimal for cleaner display
            if let dotIndex = timeValue.firstIndex(of: ".") {
                return String(timeValue[..<dotIndex])
            }
            return timeValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SPLITS")// (\(splitInterval))")
                .font(.headline)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                ForEach(Array(intervals.enumerated()), id: \.element.id) { index, interval in
                    SplitRow(
                        interval: interval,
                        isDistanceBased: isDistanceBased,
                        isFastest: interval.id == fastestId,
                        isSlowest: interval.id == slowestId
                    )
                }
            }

            // Summary stats
            if let fastest = intervals.first(where: { $0.id == fastestId }),
               let slowest = intervals.first(where: { $0.id == slowestId }) {
                Divider()
                    .padding(.vertical, 8)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fastest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(fastest.splitPer500m)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Slowest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(slowest.splitPer500m)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
    }
}

struct SplitRow: View {
    let interval: any DisplayableInterval
    let isDistanceBased: Bool
    let isFastest: Bool
    let isSlowest: Bool

    private var splitLabel: String {
        if isDistanceBased {
            // Show distance (e.g., "400m", "800m")
            return interval.meters.trimmingCharacters(in: .whitespaces) + "m"
        } else {
            // Show time (e.g., "6:00", "12:00") - remove decimal
            let timeValue = interval.time.trimmingCharacters(in: .whitespaces)
            if let dotIndex = timeValue.firstIndex(of: ".") {
                return String(timeValue[..<dotIndex])
            }
            return timeValue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(splitLabel)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)

            Text(interval.splitPer500m)
                .font(.body)
                .fontWeight(isFastest || isSlowest ? .bold : .regular)
                .foregroundColor(isFastest ? .green : (isSlowest ? .red : .primary))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text("\(interval.strokeRate)s/m")
                .font(.body)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            if let hr = interval.heartRate {
                Text(hr)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackgroundColor)
        )
    }

    private var rowBackgroundColor: Color {
        if isFastest {
            return Color.green.opacity(0.1)
        } else if isSlowest {
            return Color.red.opacity(0.1)
        } else {
            return Color(.secondarySystemBackground)
        }
    }
}

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: currentPage)
            }
        }
    }
}
