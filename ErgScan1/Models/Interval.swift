import Foundation
import SwiftData

@Model
final class Interval {
    var id: UUID
    var workout: Workout?
    var orderIndex: Int                 // Row position in table

    var time: String                    // "4:00.0"
    var meters: String                  // "1179"
    var splitPer500m: String            // "1:41.2"
    var strokeRate: String              // "29"
    var heartRate: String?              // "145" (optional, only when HR monitor connected)

    var timeConfidence: Double          // Per-field confidence scores
    var metersConfidence: Double
    var splitConfidence: Double
    var rateConfidence: Double
    var heartRateConfidence: Double

    // Note: For interval workouts, each row is a separate interval
    //       For single pieces, each row is a split of the continuous piece

    init(
        orderIndex: Int,
        time: String,
        meters: String,
        splitPer500m: String,
        strokeRate: String,
        heartRate: String? = nil,
        timeConfidence: Double = 0.0,
        metersConfidence: Double = 0.0,
        splitConfidence: Double = 0.0,
        rateConfidence: Double = 0.0,
        heartRateConfidence: Double = 0.0
    ) {
        self.id = UUID()
        self.orderIndex = orderIndex
        self.time = time
        self.meters = meters
        self.splitPer500m = splitPer500m
        self.strokeRate = strokeRate
        self.heartRate = heartRate
        self.timeConfidence = timeConfidence
        self.metersConfidence = metersConfidence
        self.splitConfidence = splitConfidence
        self.rateConfidence = rateConfidence
        self.heartRateConfidence = heartRateConfidence
    }
}
