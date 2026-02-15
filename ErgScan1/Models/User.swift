import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var appleUserID: String = ""   // Unique Apple ID identifier
    var email: String?             // Optional (user may hide)
    var fullName: String?          // Optional (user may hide)
    var username: String?          // Unique handle for social features
    var role: String?              // "rower", "coxswain", or "coach" (CSV for multi-role)
    var isOnboarded: Bool = false  // True after completing onboarding flow
    var defaultPrivacy: String?    // Default workout privacy: "private", "friends", "team"
    var createdAt: Date = Date()
    var lastSignInAt: Date = Date()

    @Relationship(deleteRule: .cascade)
    var workouts: [Workout]?

    init(appleUserID: String, email: String? = nil, fullName: String? = nil) {
        self.id = UUID()
        self.appleUserID = appleUserID
        self.email = email
        self.fullName = fullName
        self.role = nil
        self.isOnboarded = false
        self.defaultPrivacy = "friends"
        self.createdAt = Date()
        self.lastSignInAt = Date()
    }
}
