import Foundation

class PowerCurveService {

    // MARK: - Types

    struct ParsedSplit {
        let timeSeconds: Double
        let distanceM: Double
    }

    struct PowerCurvePoint: Identifiable {
        let id = UUID()
        let durationSeconds: Double
        let watts: Double

        var splitSeconds: Double {
            PowerCurveService.wattsToSplit(watts)
        }
    }

    // MARK: - Conversion Utilities

    /// Convert a /500m split (in seconds) to watts using Concept2 formula
    static func splitToWatts(_ splitSeconds: Double) -> Double {
        return 2.80 / pow(splitSeconds / 500.0, 3)
    }

    /// Convert watts back to a /500m split (in seconds)
    static func wattsToSplit(_ watts: Double) -> Double {
        guard watts > 0 else { return 0 }
        return 500.0 * pow(2.80 / watts, 1.0 / 3.0)
    }

    /// Parse a time/split string like "1:33.4" or "12:00.0" into total seconds
    static func timeStringToSeconds(_ timeStr: String) -> Double? {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return nil
        }
        return minutes * 60.0 + seconds
    }

    /// Format seconds back to split string "M:SS.s"
    static func secondsToSplitString(_ totalSeconds: Double) -> String {
        let minutes = Int(totalSeconds / 60.0)
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60.0)
        return String(format: "%d:%04.1f", minutes, seconds)
    }

    /// Format duration for display on chart axis and tooltips
    static func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let min = Int(seconds) / 60
            let sec = Int(seconds) % 60
            return sec == 0 ? "\(min)m" : "\(min)m\(sec)s"
        } else {
            let hr = Int(seconds) / 3600
            let min = (Int(seconds) % 3600) / 60
            return min == 0 ? "\(hr)h" : "\(hr)h\(min)m"
        }
    }

    // MARK: - Workout Type Detection

    /// Distance types end with "m" (e.g., "2000m", "5000m").
    /// Time types are formatted as time (e.g., "30:00", "20:00").
    static func isDistanceWorkoutType(_ workoutType: String) -> Bool {
        return workoutType.lowercased().hasSuffix("m")
    }

    // MARK: - Split Parsing (De-cumulation)

    static func parseSplits(from workout: Workout) -> [ParsedSplit] {
        let intervals = (workout.intervals ?? [])
            .filter { $0.orderIndex >= 1 }
            .sorted { $0.orderIndex < $1.orderIndex }

        guard !intervals.isEmpty else { return [] }

        if workout.category == .interval {
            // INTERVAL: each row is independent, nothing is cumulative
            return intervals.compactMap { interval in
                guard let timeSeconds = timeStringToSeconds(interval.time),
                      let distanceM = Double(interval.meters),
                      timeSeconds > 0, distanceM > 0 else {
                    return nil
                }
                return ParsedSplit(timeSeconds: timeSeconds, distanceM: distanceM)
            }
        }

        // SINGLE PIECE
        if isDistanceWorkoutType(workout.workoutType) {
            // SINGLE DISTANCE: meters is cumulative, time is per-split
            var prevCumulativeMeters: Double = 0
            return intervals.compactMap { interval in
                guard let timeSeconds = timeStringToSeconds(interval.time),
                      let cumulativeMeters = Double(interval.meters),
                      timeSeconds > 0 else {
                    return nil
                }
                let splitDistance = cumulativeMeters - prevCumulativeMeters
                prevCumulativeMeters = cumulativeMeters
                guard splitDistance > 0 else { return nil }
                return ParsedSplit(timeSeconds: timeSeconds, distanceM: splitDistance)
            }
        } else {
            // SINGLE TIME: time is cumulative, meters is per-split
            var prevCumulativeTime: Double = 0
            return intervals.compactMap { interval in
                guard let cumulativeTime = timeStringToSeconds(interval.time),
                      let distanceM = Double(interval.meters),
                      distanceM > 0 else {
                    return nil
                }
                let splitTime = cumulativeTime - prevCumulativeTime
                prevCumulativeTime = cumulativeTime
                guard splitTime > 0 else { return nil }
                return ParsedSplit(timeSeconds: splitTime, distanceM: distanceM)
            }
        }
    }

    // MARK: - Power Curve Building

    static func isDominated(duration: Double, watts: Double, curve: [Double: Double]) -> Bool {
        for (existingDuration, existingWatts) in curve {
            if existingDuration >= duration && existingWatts >= watts {
                return true
            }
        }
        return false
    }

    static func updatePowerCurve(duration: Double, watts: Double, curve: inout [Double: Double]) {
        if isDominated(duration: duration, watts: watts, curve: curve) {
            return
        }
        let key = (duration * 100).rounded() / 100
        if let existing = curve[key] {
            if watts > existing {
                curve[key] = watts
            }
        } else {
            curve[key] = watts
        }
    }

    static func enforceMonotonicity(_ curve: [Double: Double]) -> [Double: Double] {
        // Sort by duration descending (longest first)
        let sorted = curve.sorted { $0.key > $1.key }
        var cleaned: [Double: Double] = [:]
        var maxPowerSoFar: Double = 0

        for (duration, watts) in sorted {
            if watts >= maxPowerSoFar {
                cleaned[duration] = watts
                maxPowerSoFar = watts
            }
        }

        return cleaned
    }

    // MARK: - Main Entry Point

    static func rebuildPowerCurve(from workouts: [Workout]) -> [PowerCurvePoint] {
        var curve: [Double: Double] = [:]

        for workout in workouts {
            let parsedSplits = parseSplits(from: workout)
            let n = parsedSplits.count
            guard n > 0 else { continue }

            if workout.category == .interval {
                // Each interval is independent — one point per interval
                for split in parsedSplits {
                    guard split.distanceM > 0 else { continue }
                    let avgSplitSeconds = split.timeSeconds / split.distanceM * 500.0
                    let avgWatts = splitToWatts(avgSplitSeconds)
                    updatePowerCurve(duration: split.timeSeconds, watts: avgWatts, curve: &curve)
                }
            } else {
                // Single piece — all contiguous blocks of splits
                for blockLength in 1...n {
                    for startIndex in 0...(n - blockLength) {
                        let block = Array(parsedSplits[startIndex ..< startIndex + blockLength])

                        let totalTime = block.reduce(0) { $0 + $1.timeSeconds }
                        let totalDistance = block.reduce(0) { $0 + $1.distanceM }

                        guard totalDistance > 0 else { continue }

                        let avgSplitSeconds = totalTime / totalDistance * 500.0
                        let avgWatts = splitToWatts(avgSplitSeconds)

                        updatePowerCurve(duration: totalTime, watts: avgWatts, curve: &curve)
                    }
                }
            }
        }

        let cleaned = enforceMonotonicity(curve)
        return cleaned
            .sorted { $0.key < $1.key }
            .filter { $0.key >= 5 && $0.value > 0 && $0.value <= 1500 }
            .map { PowerCurvePoint(durationSeconds: $0.key, watts: $0.value) }
    }
}
