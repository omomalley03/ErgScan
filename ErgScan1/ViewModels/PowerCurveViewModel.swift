import SwiftUI

@Observable
class PowerCurveViewModel {
    var curveData: [PowerCurveService.PowerCurvePoint] = []
    var isLoading = false
    var selectedPoint: PowerCurveService.PowerCurvePoint?

    func loadCurve(workouts: [Workout]) {
        isLoading = true

        Task.detached {
            let points = PowerCurveService.rebuildPowerCurve(from: workouts)
            await MainActor.run {
                self.curveData = points
                self.isLoading = false
            }
        }
    }
}
