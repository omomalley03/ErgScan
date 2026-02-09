import Foundation
import SwiftData

enum WorkoutCategory: String, Codable {
    case single    // Single continuous piece (e.g., "2000m", "4:00")
    case interval  // Interval workout (e.g., "3x4:00/3:00r")
}

@Model
final class Workout {
    var id: UUID
    var date: Date                      // Extracted from monitor
    var workoutType: String             // e.g., "3x4:00/3:00r" or "2000m"
    var category: WorkoutCategory       // single or interval
    var totalTime: String               // e.g., "21:00.3"
    var totalDistance: Int?             // Total meters (e.g., 2000, 3845)
    var createdAt: Date
    var lastModifiedAt: Date

    @Attribute(.externalStorage)
    var imageData: Data?                // Last captured image (JPEG compressed)

    @Relationship(deleteRule: .cascade)
    var intervals: [Interval] = []      // For interval: actual intervals
                                        // For single: splits of the piece

    var ocrConfidence: Double           // Average confidence across all fields
    var wasManuallyEdited: Bool         // Track if user corrected data

    init(
        date: Date,
        workoutType: String,
        category: WorkoutCategory,
        totalTime: String,
        totalDistance: Int? = nil,
        ocrConfidence: Double = 0.0,
        imageData: Data? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.workoutType = workoutType
        self.category = category
        self.totalTime = totalTime
        self.totalDistance = totalDistance
        self.createdAt = Date()
        self.lastModifiedAt = Date()
        self.imageData = imageData
        self.ocrConfidence = ocrConfidence
        self.wasManuallyEdited = false
    }
}
