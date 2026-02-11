import Foundation
import SwiftData

/// Ground truth workout labels for benchmark testing
/// Stores the final locked data from a scanning session as the "correct" labels
@Model
final class BenchmarkWorkout {
    var id: UUID = UUID()
    var createdDate: Date = Date()

    // Workout metadata (ground truth from locked RecognizedTable)
    var workoutType: String?
    var category: WorkoutCategory?
    var workoutDescription: String?
    var totalTime: String?
    var totalDistance: Int?
    var date: Date?

    // Interval-specific fields
    var reps: Int?
    var workPerRep: String?
    var restPerRep: String?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \BenchmarkImage.workout)
    var images: [BenchmarkImage]?

    @Relationship(deleteRule: .cascade, inverse: \BenchmarkInterval.workout)
    var intervals: [BenchmarkInterval]?

    // Metadata
    var notes: String?  // User notes about this benchmark
    var isApproved: Bool = false  // Whether ground truth is finalized
    var approvedDate: Date?

    init(
        id: UUID = UUID(),
        createdDate: Date = Date(),
        workoutType: String? = nil,
        category: WorkoutCategory? = nil,
        workoutDescription: String? = nil,
        totalTime: String? = nil,
        totalDistance: Int? = nil,
        date: Date? = nil,
        reps: Int? = nil,
        workPerRep: String? = nil,
        restPerRep: String? = nil
    ) {
        self.id = id
        self.createdDate = createdDate
        self.workoutType = workoutType
        self.category = category
        self.workoutDescription = workoutDescription
        self.totalTime = totalTime
        self.totalDistance = totalDistance
        self.date = date
        self.reps = reps
        self.workPerRep = workPerRep
        self.restPerRep = restPerRep
    }
}
