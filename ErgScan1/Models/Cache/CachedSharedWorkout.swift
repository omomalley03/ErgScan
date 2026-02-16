import Foundation
import SwiftData

@Model
final class CachedSharedWorkout {
    @Attribute(.unique) var recordID: String
    var ownerID: String
    var ownerUsername: String
    var ownerDisplayName: String
    var workoutDate: Date
    var workoutType: String
    var totalTime: String
    var totalDistance: Int
    var averageSplit: String
    var intensityZone: String
    var isErgTest: Bool
    var privacy: String
    var submittedByCoxUsername: String?
    var createdAt: Date
    var cachedAt: Date
    var source: String  // "friend" or "team:<teamID>"

    init(
        recordID: String,
        ownerID: String,
        ownerUsername: String,
        ownerDisplayName: String,
        workoutDate: Date,
        workoutType: String,
        totalTime: String,
        totalDistance: Int,
        averageSplit: String,
        intensityZone: String,
        isErgTest: Bool,
        privacy: String,
        submittedByCoxUsername: String?,
        createdAt: Date,
        source: String
    ) {
        self.recordID = recordID
        self.ownerID = ownerID
        self.ownerUsername = ownerUsername
        self.ownerDisplayName = ownerDisplayName
        self.workoutDate = workoutDate
        self.workoutType = workoutType
        self.totalTime = totalTime
        self.totalDistance = totalDistance
        self.averageSplit = averageSplit
        self.intensityZone = intensityZone
        self.isErgTest = isErgTest
        self.privacy = privacy
        self.submittedByCoxUsername = submittedByCoxUsername
        self.createdAt = createdAt
        self.cachedAt = Date()
        self.source = source
    }

    convenience init(from result: SocialService.SharedWorkoutResult, source: String) {
        self.init(
            recordID: result.id,
            ownerID: result.ownerID,
            ownerUsername: result.ownerUsername,
            ownerDisplayName: result.ownerDisplayName,
            workoutDate: result.workoutDate,
            workoutType: result.workoutType,
            totalTime: result.totalTime,
            totalDistance: result.totalDistance,
            averageSplit: result.averageSplit,
            intensityZone: result.intensityZone,
            isErgTest: result.isErgTest,
            privacy: result.privacy,
            submittedByCoxUsername: result.submittedByCoxUsername,
            createdAt: result.workoutDate,
            source: source
        )
    }

    func toSharedWorkoutResult() -> SocialService.SharedWorkoutResult {
        SocialService.SharedWorkoutResult(
            id: recordID,
            ownerID: ownerID,
            ownerUsername: ownerUsername,
            ownerDisplayName: ownerDisplayName,
            workoutDate: workoutDate,
            workoutType: workoutType,
            totalTime: totalTime,
            totalDistance: totalDistance,
            averageSplit: averageSplit,
            intensityZone: intensityZone,
            isErgTest: isErgTest,
            privacy: privacy,
            submittedByCoxUsername: submittedByCoxUsername
        )
    }
}
