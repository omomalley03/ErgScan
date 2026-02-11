import Foundation
import SwiftData

@Model
final class Goal {
    var id: UUID = UUID()
    var weeklyMeterGoal: Int = 0
    var monthlyMeterGoal: Int = 0
    var targetUT2Percent: Int = 60
    var targetUT1Percent: Int = 25
    var targetATPercent: Int = 10
    var targetMaxPercent: Int = 5
    var userID: String?
    var lastModifiedAt: Date = Date()
    var syncedToCloud: Bool = false

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
