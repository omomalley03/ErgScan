import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID
    var weeklyMeterGoal: Int
    var monthlyMeterGoal: Int
    var targetUT2Percent: Int
    var targetUT1Percent: Int
    var targetATPercent: Int
    var targetMaxPercent: Int
    var userID: String?
    var lastModifiedAt: Date
    var syncedToCloud: Bool

    init(
        weeklyMeterGoal: Int = 0,
        monthlyMeterGoal: Int = 0,
        targetUT2Percent: Int = 60,
        targetUT1Percent: Int = 25,
        targetATPercent: Int = 10,
        targetMaxPercent: Int = 5,
        userID: String? = nil
    ) {
        self.id = UUID()
        self.weeklyMeterGoal = weeklyMeterGoal
        self.monthlyMeterGoal = monthlyMeterGoal
        self.targetUT2Percent = targetUT2Percent
        self.targetUT1Percent = targetUT1Percent
        self.targetATPercent = targetATPercent
        self.targetMaxPercent = targetMaxPercent
        self.userID = userID
        self.lastModifiedAt = Date()
        self.syncedToCloud = false
    }
}
