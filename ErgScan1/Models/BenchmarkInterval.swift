import Foundation
import SwiftData

/// Ground truth interval/split data for benchmark testing
@Model
final class BenchmarkInterval {
    var id: UUID
    var workout: BenchmarkWorkout?
    var orderIndex: Int

    // Core metrics (ground truth from locked RecognizedTable.rows)
    var time: String?
    var meters: Int?
    var splitPer500m: String?
    var strokeRate: Int?
    var heartRate: Int?

    init(
        id: UUID = UUID(),
        orderIndex: Int = 0,
        time: String? = nil,
        meters: Int? = nil,
        splitPer500m: String? = nil,
        strokeRate: Int? = nil,
        heartRate: Int? = nil
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.time = time
        self.meters = meters
        self.splitPer500m = splitPer500m
        self.strokeRate = strokeRate
        self.heartRate = heartRate
    }
}
