import Foundation
import SwiftData

@Model
final class User {
    var id: UUID
    var appleUserID: String        // Unique Apple ID identifier
    var email: String?             // Optional (user may hide)
    var fullName: String?          // Optional (user may hide)
    var createdAt: Date
    var lastSignInAt: Date

    @Relationship(deleteRule: .cascade)
    var workouts: [Workout] = []

    init(appleUserID: String, email: String? = nil, fullName: String? = nil) {
        self.id = UUID()
        self.appleUserID = appleUserID
        self.email = email
        self.fullName = fullName
        self.createdAt = Date()
        self.lastSignInAt = Date()
    }
}
