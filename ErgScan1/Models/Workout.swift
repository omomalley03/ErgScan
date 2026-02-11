import Foundation
import SwiftData

enum WorkoutCategory: String, Codable {
    case single    // Single continuous piece (e.g., "2000m", "4:00")
    case interval  // Interval workout (e.g., "3x4:00/3:00r")
}

@Model
final class Workout {
    var id: UUID = UUID()
    var date: Date = Date()             // Extracted from monitor
    var workoutType: String = ""        // e.g., "3x4:00/3:00r" or "2000m"
    var category: WorkoutCategory = WorkoutCategory.single  // single or interval
    var totalTime: String = ""          // e.g., "21:00.3"
    var totalDistance: Int?             // Total meters (e.g., 2000, 3845)
    var createdAt: Date = Date()
    var lastModifiedAt: Date = Date()

    @Attribute(.externalStorage)
    var imageData: Data?                // Last captured image (JPEG compressed)

    @Relationship(deleteRule: .cascade)
    var intervals: [Interval]?          // For interval: actual intervals
                                        // For single: splits of the piece

    var ocrConfidence: Double = 0.0     // Average confidence across all fields
    var wasManuallyEdited: Bool = false  // Track if user corrected data
    var isErgTest: Bool = false          // Whether this is an erg test piece

    // Training intensity zone
    var intensityZone: String?          // Raw string for SwiftData/CloudKit compatibility

    // Convenience computed property (not persisted)
    var zone: IntensityZone? {
        get {
            guard let raw = intensityZone else { return nil }
            return IntensityZone(rawValue: raw)
        }
        set {
            intensityZone = newValue?.rawValue
        }
    }

    // Average split from the averages interval (orderIndex == 0)
    var averageSplit: String? {
        (intervals ?? [Interval]()).first(where: { $0.orderIndex == 0 })?.splitPer500m
    }

    // User relationship for CloudKit sync
    var user: User?
    var userID: String?                 // Denormalized for query performance

    // CloudKit sync metadata
    var syncedToCloud: Bool = false
    var cloudKitRecordID: String?
    var lastSyncedAt: Date?

    init(
        date: Date,
        workoutType: String,
        category: WorkoutCategory,
        totalTime: String,
        totalDistance: Int? = nil,
        ocrConfidence: Double = 0.0,
        imageData: Data? = nil,
        intensityZone: String? = nil,
        isErgTest: Bool = false
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
        self.isErgTest = isErgTest
        self.intensityZone = intensityZone
        self.syncedToCloud = false
    }
}
