import Foundation
import SwiftData

/// Protocol unifying Interval model and friend workout JSON data for display
protocol DisplayableInterval {
    var id: UUID { get }
    var orderIndex: Int { get }
    var time: String { get }
    var meters: String { get }
    var splitPer500m: String { get }
    var strokeRate: String { get }
    var heartRate: String? { get }
}

/// Lightweight view model for displaying friend workout intervals
struct IntervalViewModel: DisplayableInterval, Identifiable {
    let id: UUID
    let orderIndex: Int
    let time: String
    let meters: String
    let splitPer500m: String
    let strokeRate: String
    let heartRate: String?

    /// Initialize from CloudKit JSON dictionary
    init?(from dict: [String: Any]) {
        guard let orderIndex = dict["orderIndex"] as? Int,
              let time = dict["time"] as? String,
              let meters = dict["meters"] as? String,
              let splitPer500m = dict["splitPer500m"] as? String,
              let strokeRate = dict["strokeRate"] as? String
        else {
            return nil
        }

        self.id = UUID()
        self.orderIndex = orderIndex
        self.time = time
        self.meters = meters
        self.splitPer500m = splitPer500m
        self.strokeRate = strokeRate
        self.heartRate = dict["heartRate"] as? String
    }
}

/// Extend Interval to conform to DisplayableInterval
extension Interval: DisplayableInterval {
    // All properties already exist - automatic conformance
}
