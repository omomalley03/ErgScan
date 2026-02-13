import Foundation

/// Protocol unifying local Workout and CloudKit SharedWorkoutResult for feed cards
protocol WorkoutDisplayable {
    var displayName: String { get }
    var displayUsername: String { get }
    var displayDate: Date { get }
    var displayWorkoutType: String { get }
    var displayTotalTime: String { get }
    var displayTotalDistance: Int { get }
    var displayAverageSplit: String { get }
    var displayIntensityZone: IntensityZone? { get }
    var displayIsErgTest: Bool { get }
    var workoutRecordID: String { get }
    var ownerUserID: String { get }
}

// MARK: - SharedWorkoutResult Conformance

extension SocialService.SharedWorkoutResult: WorkoutDisplayable {
    var displayName: String { ownerDisplayName }
    var displayUsername: String { ownerUsername }
    var displayDate: Date { workoutDate }
    var displayWorkoutType: String { workoutType }
    var displayTotalTime: String { totalTime }
    var displayTotalDistance: Int { totalDistance }
    var displayAverageSplit: String { averageSplit }
    var displayIntensityZone: IntensityZone? { IntensityZone(rawValue: intensityZone) }
    var displayIsErgTest: Bool { isErgTest }
    var workoutRecordID: String { id }
    var ownerUserID: String { ownerID }
}

// MARK: - Local Workout Conformance

extension Workout: WorkoutDisplayable {
    var displayName: String { user?.fullName ?? "You" }
    var displayUsername: String { user?.username ?? "" }
    var displayDate: Date { date }
    var displayWorkoutType: String { workoutType }
    var displayTotalTime: String { totalTime }
    var displayTotalDistance: Int { totalDistance ?? 0 }
    var displayAverageSplit: String { averageSplit ?? "" }
    var displayIntensityZone: IntensityZone? { zone }
    var displayIsErgTest: Bool { isErgTest }
    var workoutRecordID: String { id.uuidString }
    var ownerUserID: String { userID ?? "" }
}
